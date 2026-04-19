#!/usr/bin/env bash
# ============================================
# Shared Logging Functions
# Flux.1 LoRA Training Pipeline
# ============================================

LOG_DIR="${PIPELINE_LOG_DIR:-/data/logs}"

log_info() {
    local message="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] ${message}"
    if [[ -d "${LOG_DIR}" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] ${message}" >> "${LOG_DIR}/orchestrator.log"
    fi
}

log_warn() {
    local message="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] ${message}" >&2
    if [[ -d "${LOG_DIR}" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [WARN] ${message}" >> "${LOG_DIR}/orchestrator.log"
    fi
}

log_error() {
    local message="$1"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] ${message}" >&2
    if [[ -d "${LOG_DIR}" ]]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] ${message}" >> "${LOG_DIR}/orchestrator.log"
    fi
}

validate_dataset() {
    local dataset_path="$1"
    if [[ ! -d "${dataset_path}" ]]; then
        log_error "Dataset directory not found: ${dataset_path}"
        return 1
    fi
    local image_count
    image_count=$(find "${dataset_path}" -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) 2>/dev/null | wc -l)
    if (( image_count < 3 )); then
        log_error "Dataset too small: ${image_count} images (minimum 3 required)"
        return 1
    fi

    local caption_count=0
    caption_count=$(find "${dataset_path}" -maxdepth 1 -type f -iname "*.txt" 2>/dev/null | wc -l)
    log_info "Dataset images: ${image_count}, caption files: ${caption_count}"

    local min_width min_height
    min_width=$(parse_config_value "${dataset_path}/../configs/$(basename ${dataset_path}).toml" "min_image_width" "512" 2>/dev/null || echo "512")
    min_height=$(parse_config_value "${dataset_path}/../configs/$(basename ${dataset_path}).toml" "min_image_height" "512" 2>/dev/null || echo "512")

    if command -v python3 &>/dev/null; then
        local validate_script="/tmp/validate_dataset_$$.py"
        cat > "${validate_script}" <<'PYSCRIPT'
import sys
import os
from PIL import Image
import glob

dataset_path = sys.argv[1] if len(sys.argv) > 1 else "."
min_w = int(sys.argv[2]) if len(sys.argv) > 2 else 512
min_h = int(sys.argv[3]) if len(sys.argv) > 3 else 512

image_files = []
for ext in ["*.jpg", "*.jpeg", "*.png", "*.webp"]:
    image_files.extend(glob.glob(os.path.join(dataset_path, ext)))
    image_files.extend(glob.glob(os.path.join(dataset_path, ext.upper())))

errors = []
small_images = 0
corrupt_images = 0
paired = 0
unpaired = 0

for img_path in image_files:
    base = os.path.splitext(os.path.basename(img_path))[0]
    caption_file = os.path.join(dataset_path, base + ".txt")
    has_caption = os.path.exists(caption_file)
    if has_caption:
        paired += 1
    else:
        unpaired += 1

    try:
        with Image.open(img_path) as img:
            img.verify()
        with Image.open(img_path) as img:
            w, h = img.size
            if w < min_w or h < min_h:
                small_images += 1
            if img.mode not in ("RGB", "RGBA", "L"):
                errors.append(f"{img_path}: unusual mode {img.mode}")
    except Exception as e:
        corrupt_images += 1
        errors.append(f"{img_path}: corrupt - {e}")

print(f"total_images={len(image_files)}")
print(f"paired_captions={paired}")
print(f"unpaired_captions={unpaired}")
print(f"small_images={small_images}")
print(f"corrupt_images={corrupt_images}")
if errors:
    for err in errors[:10]:
        print(f"ERROR:{err}", file=sys.stderr)
sys.exit(corrupt_images)
PYSCRIPT
        local validation_result
        validation_result=$(python3 "${validate_script}" "${dataset_path}" "${min_width}" "${min_height}" 2>&1)
        local validation_exit=$?
        rm -f "${validate_script}"

        local total_images paired_captions unpaired_captions small_images corrupt_images
        total_images=$(echo "${validation_result}" | grep "^total_images=" | cut -d= -f2)
        paired_captions=$(echo "${validation_result}" | grep "^paired_captions=" | cut -d= -f2)
        unpaired_captions=$(echo "${validation_result}" | grep "^unpaired_captions=" | cut -d= -f2)
        small_images=$(echo "${validation_result}" | grep "^small_images=" | cut -d= -f2)
        corrupt_images=$(echo "${validation_result}" | grep "^corrupt_images=" | cut -d= -f2)

        if [[ -n "${total_images}" ]]; then
            log_info "Dataset validation details:"
            log_info "  Total images: ${total_images}"
            log_info "  Paired captions: ${paired_captions}"
            log_info "  Unpaired captions: ${unpaired_captions}"
            log_info "  Small images (<${min_width}x${min_height}): ${small_images}"
            log_info "  Corrupt images: ${corrupt_images}"
        fi

        if [[ -n "${corrupt_images}" ]] && [[ "${corrupt_images}" -gt 0 ]]; then
            log_error "Corrupt images detected: ${corrupt_images}"
            return 1
        fi

        if [[ -n "${small_images}" ]] && [[ "${small_images}" -gt 0 ]]; then
            log_warn "Small images detected: ${small_images} (may need preprocessing)"
        fi
    else
        log_warn "Python3 not available - skipping advanced dataset validation"
    fi

    log_info "Dataset validated: ${image_count} images found"
    return 0
}

preprocess_dataset() {
    local dataset_path="$1"
    local target_size="${2:-1024}"
    local bucket_mode="${3:-center}"

    if [[ ! -d "${dataset_path}" ]]; then
        log_error "Dataset directory not found: ${dataset_path}"
        return 1
    fi

    local preprocessed_dir="${dataset_path}/preprocessed"
    mkdir -p "${preprocessed_dir}"

    log_info "Preprocessing dataset: ${dataset_path} -> ${preprocessed_dir}"
    log_info "Target size: ${target_size}, bucket mode: ${bucket_mode}"

    if ! command -v python3 &>/dev/null; then
        log_warn "Python3 not available - skipping preprocessing"
        return 1
    fi

    local preprocess_script="/tmp/preprocess_$$.py"
    cat > "${preprocess_script}" <<'PYSCRIPT'
import sys
import os
from PIL import Image
import glob
import math

dataset_path = sys.argv[1] if len(sys.argv) > 1 else "."
target_size = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
bucket_mode = sys.argv[3] if len(sys.argv) > 3 else "center"

output_dir = os.path.join(dataset_path, "preprocessed")
os.makedirs(output_dir, exist_ok=True)

image_files = []
for ext in ["*.jpg", "*.jpeg", "*.png", "*.webp"]:
    image_files.extend(glob.glob(os.path.join(dataset_path, ext)))
    image_files.extend(glob.glob(os.path.join(dataset_path, ext.upper())))

ASPECT_RATIOS = [
    (512, 512),
    (512, 768),
    (512, 1024),
    (768, 512),
    (768, 768),
    (768, 1024),
    (1024, 512),
    (1024, 768),
    (1024, 1024),
]

def get_closest_bucket(w, h):
    aspect = w / h
    best = ASPECT_RATIOS[0]
    best_diff = abs(aspect - (best[0] / best[1]))
    for bucket in ASPECT_RATIOS:
        diff = abs(aspect - (bucket[0] / bucket[1]))
        if diff < best_diff:
            best = bucket
            best_diff = diff
    return best

def center_crop(img, tw, th):
    w, h = img.size
    scale = max(tw / w, th / h)
    nw, nh = int(w * scale), int(h * scale)
    img = img.resize((nw, nh), Image.LANCZOS)
    left = (nw - tw) // 2
    top = (nh - th) // 2
    return img.crop((left, top, left + tw, top + th))

def resize_and_bucket(img, bucket):
    tw, th = bucket
    w, h = img.size
    if bucket_mode == "center":
        return center_crop(img, tw, th)
    else:
        img = img.resize((tw, th), Image.LANCZOS)
        return img

processed = 0
skipped = 0

for img_path in image_files:
    base = os.path.splitext(os.path.basename(img_path))[0]
    try:
        with Image.open(img_path) as img:
            img = img.convert("RGB")
            bucket = get_closest_bucket(img.size[0], img.size[1])
            processed_img = resize_and_bucket(img, bucket)
            out_path = os.path.join(output_dir, f"{base}_processed.jpg")
            processed_img.save(out_path, "JPEG", quality=95)
            if os.path.exists(os.path.join(dataset_path, base + ".txt")):
                import shutil
                shutil.copy(os.path.join(dataset_path, base + ".txt"),
                           os.path.join(output_dir, base + "_processed.txt"))
            processed += 1
    except Exception as e:
        print(f"ERROR: {img_path}: {e}", file=sys.stderr)
        skipped += 1

print(f"processed={processed}")
print(f"skipped={skipped}")
PYSCRIPT

    local result
    result=$(python3 "${preprocess_script}" "${dataset_path}" "${target_size}" "${bucket_mode}" 2>&1)
    rm -f "${preprocess_script}"

    local processed skipped
    processed=$(echo "${result}" | grep "^processed=" | cut -d= -f2)
    skipped=$(echo "${result}" | grep "^skipped=" | cut -d= -f2)

    log_info "Preprocessing complete: ${processed} processed, ${skipped} skipped"
    echo "${preprocessed_dir}"
    return 0
}

export -f log_info log_warn log_error validate_dataset preprocess_dataset