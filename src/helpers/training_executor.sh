#!/usr/bin/env bash
# ============================================
# Training Executor Helper
# Flux.1 LoRA Training Pipeline
# ============================================

set -euo pipefail

TRAINING_BACKEND_DIR="${TRAINING_BACKEND_DIR:-/opt/backend}"
LOG_DIR="${PIPELINE_LOG_DIR:-/data/logs}"

resolve_training_backend() {
    local model_path="$1"
    if [[ -d "${TRAINING_BACKEND_DIR}/kohya-ss" ]]; then
        echo "kohya-ss"
    elif [[ -d "${TRAINING_BACKEND_DIR}/ai-toolkit" ]]; then
        echo "ai-toolkit"
    else
        echo "none"
    fi
}

get_optimal_precision() {
    local gpu_name="${1:-}"
    local compute_cap="${2:-6.1}"
    if command -v nvidia-smi &>/dev/null; then
        compute_cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 || echo "6.1")
    fi
    if (( $(echo "${compute_cap} >= 8.0" | bc -l 2>/dev/null || echo 0) )); then
        echo "bf16"
    elif [[ "${gpu_name}" == *"A100"* || "${gpu_name}" == *"H100"* || "${gpu_name}" == *"RTX 40"* ]]; then
        echo "bf16"
    else
        echo "fp16"
    fi
}

build_kohya_command() {
    local config_file="$1"
    local job_id="$2"
    local output_dir="${3}"
    local backend_dir="${TRAINING_BACKEND_DIR}/kohya-ss"

    local model_path dataset_path network_rank network_alpha learning_rate
    local optimizer lr_scheduler batch_size max_train_epochs resolution
    local seed gradient_checkpointing

    model_path=$(parse_config_value "${config_file}" "model_name_or_path" "/data/models/flux1-dev")
    dataset_path=$(parse_config_value "${config_file}" "dataset_path" "")
    network_rank=$(parse_config_value "${config_file}" "network_rank" "32")
    network_alpha=$(parse_config_value "${config_file}" "network_alpha" "${network_rank}")
    learning_rate=$(parse_config_value "${config_file}" "learning_rate" "1e-4")
    optimizer=$(parse_config_value "${config_file}" "optimizer" "adamw8bit")
    lr_scheduler=$(parse_config_value "${config_file}" "lr_scheduler" "cosine")
    batch_size=$(parse_config_value "${config_file}" "batch_size" "1")
    max_train_epochs=$(parse_config_value "${config_file}" "max_train_epochs" "20")
    resolution=$(parse_config_value "${config_file}" "resolution" "1024")
    seed=$(parse_config_value "${config_file}" "seed" "42")
    gradient_checkpointing=$(parse_config_value "${config_file}" "gradient_checkpointing" "true")

    local gpu_name="Unknown"
    local compute_cap="6.1"
    if command -v nvidia-smi &>/dev/null; then
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
        compute_cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 || echo "6.1")
    fi
    local precision
    precision=$(get_optimal_precision "${gpu_name}" "${compute_cap}")

    local cmd="python3 ${backend_dir}/train_network.py \
        --pretrained_model_name_or_path=${model_path} \
        --train_data_dir=${dataset_path} \
        --output_dir=${output_dir} \
        --output_name=${job_id} \
        --network_module=locon \
        --network_dim=${network_rank} \
        --network_alpha=${network_alpha} \
        --train_batch_size=${batch_size} \
        --max_train_epochs=${max_train_epochs} \
        --learning_rate=${learning_rate} \
        --optimizer_type=${optimizer} \
        --lr_scheduler=${lr_scheduler} \
        --resolution=${resolution}x${resolution} \
        --seed=${seed} \
        --mixed_precision=${precision} \
        --save_every_n_steps=500 \
        --sample_every_n_steps=250 \
        --sample_prompts=${output_dir}/${job_id}/sample_prompts.txt"

    if [[ "${gradient_checkpointing}" == "true" ]]; then
        cmd="${cmd} --gradient_checkpointing"
    fi

    if [[ -d "${backend_dir}/" ]]; then
        cmd="${cmd} --sdpa"
    fi

    echo "${cmd}"
}

execute_training() {
    local config_file="$1"
    local job_id="$2"
    local log_file="${LOG_DIR}/${job_id}_training.log"

    local output_dir
    output_dir=$(parse_config_value "${config_file}" "output_dir" "/data/output")
    output_dir="${output_dir}/${job_id}"
    mkdir -p "${output_dir}"

    local sample_prompts_file="${output_dir}/sample_prompts.txt"
    local sample_prompts
    sample_prompts=$(parse_config_value "${config_file}" "sample_prompts" "")
    if [[ -z "${sample_prompts}" ]]; then
        sample_prompts="a photo of a person
a portrait of a person"
    fi
    log_info "Writing sample prompts to: ${sample_prompts_file}"
    echo "${sample_prompts}" > "${sample_prompts_file}"

    local backend
    backend=$(resolve_training_backend "${config_file}")

    if [[ "${backend}" == "none" ]]; then
        log_warn "No training backend found. Simulating training."
        simulate_training "${job_id}" "${output_dir}"
        return 0
    fi

    local cmd
    if [[ "${backend}" == "kohya-ss" ]]; then
        cmd=$(build_kohya_command "${config_file}" "${job_id}" "${output_dir}")
    fi

    log_info "Executing training command: ${cmd}"
    log_info "Training log: ${log_file}"

    eval "${cmd}" 2>&1 | tee "${log_file}"
    return ${PIPESTATUS[0]}
}

simulate_training() {
    local job_id="$1"
    local output_dir="$2"
    log_info "Simulating training for job: ${job_id}"
    log_info "Output would be saved to: ${output_dir}"
    mkdir -p "${output_dir}"
    local sample_prompts="${output_dir}/sample_prompts.txt"
    cat > "${sample_prompts}" <<'EOF'
a photo of a person
a portrait of a person
EOF
    return 0
}

parse_config_value() {
    local config_file="$1"
    local key="$2"
    local fallback="${3:-}"
    if [[ ! -f "${config_file}" ]]; then
        echo "${fallback}"
        return 1
    fi
    local value
    if [[ "${config_file}" == *.toml ]]; then
        value=$(grep -E "^${key}\s*=" "${config_file}" | sed 's/^[^=]*=[ ]*//' | tr -d '"' | tr -d "'" | xargs)
    elif [[ "${config_file}" == *.yaml || "${config_file}" == *.yml ]]; then
        value=$(grep -E "^\s*${key}\s*:" "${config_file}" | sed 's/^[^:]*:[ ]*//' | xargs)
    fi
    echo "${value:-${fallback}}"
}

detect_oom() {
    local log_file="$1"
    if [[ -f "${log_file}" ]]; then
        if grep -qi "out of memory\|cuda oom\|oom\|cudamalloc\|allocation failed" "${log_file}"; then
            return 0
        fi
    fi
    return 1
}

halve_batch_size() {
    local config_file="$1"
    local current_batch
    current_batch=$(parse_config_value "${config_file}" "batch_size" "1")
    local new_batch=$(( current_batch / 2 ))
    if [[ ${new_batch} -lt 1 ]]; then
        new_batch=1
    fi
    sed -i "s/^batch_size.*=.*/batch_size = ${new_batch}/" "${config_file}" 2>/dev/null || true
    echo "${new_batch}"
}

send_webhook() {
    local webhook_url="$1"
    local payload="$2"
    if [[ -z "${webhook_url}" ]]; then
        return 0
    fi
    curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "${payload}" \
        --max-time 30 \
        "${webhook_url}" || log_warn "Webhook delivery failed: ${webhook_url}"
}

generate_sample_images() {
    local job_id="$1"
    local output_dir="$2"
    local sample_prompts_file="${3:-${output_dir}/sample_prompts.txt}"
    local num_samples="${4:-4}"

    if [[ ! -f "${sample_prompts_file}" ]]; then
        log_warn "Sample prompts file not found: ${sample_prompts_file}"
        return 1
    fi

    local sample_dir="${output_dir}/samples"
    mkdir -p "${sample_dir}"

    log_info "Generating ${num_samples} sample images for job: ${job_id}"

    if ! command -v python3 &>/dev/null; then
        log_warn "Python3 not available - cannot generate sample images"
        return 1
    fi

    local gen_script="/tmp/generate_samples_$$.py"
    cat > "${gen_script}" <<'PYSCRIPT'
import sys
import os

job_id = sys.argv[1] if len(sys.argv) > 1 else "sample"
output_dir = sys.argv[2] if len(sys.argv) > 2 else "/tmp"
prompts_file = sys.argv[3] if len(sys.argv) > 3 else os.path.join(output_dir, "sample_prompts.txt")
num_samples = int(sys.argv[4]) if len(sys.argv) > 4 else 4

if not os.path.exists(prompts_file):
    print(f"ERROR: Prompts file not found: {prompts_file}")
    sys.exit(1)

with open(prompts_file, "r") as f:
    prompts = [line.strip() for line in f if line.strip()]

if not prompts:
    print("ERROR: No prompts found")
    sys.exit(1)

try:
    import torch
    from diffusers import DiffusionPipeline
    from PIL import Image
    import numpy as np

    device = "cuda" if torch.cuda.is_available() else "cpu"
    pipe = DiffusionPipeline.from_pretrained("black-forest-labs/FLUX.1-dev" if device == "cuda" else "flax-community/flux-topo-diff",
                                              torch_dtype=torch.float16 if device == "cuda" else torch.float32)
    pipe = pipe.to(device)

    sample_dir = os.path.join(output_dir, "samples")
    os.makedirs(sample_dir, exist_ok=True)

    for i in range(min(num_samples, len(prompts))):
        prompt = prompts[i % len(prompts)]
        result = pipe(prompt, num_inference_steps=30, height=512, width=512)
        image = result.images[0]
        out_path = os.path.join(sample_dir, f"{job_id}_sample_{i+1}.png")
        image.save(out_path)
        print(f"Saved: {out_path}")

    print("SUCCESS")
except ImportError as e:
    print(f"ERROR: Missing dependency - {e}")
    sys.exit(1)
except Exception as e:
    print(f"ERROR: Generation failed - {e}")
    sys.exit(1)
PYSCRIPT

    local result
    result=$(python3 "${gen_script}" "${job_id}" "${output_dir}" "${sample_prompts_file}" "${num_samples}" 2>&1)
    local gen_exit=$?
    rm -f "${gen_script}"

    if [[ ${gen_exit} -eq 0 ]] && echo "${result}" | grep -q "SUCCESS"; then
        log_info "Sample images generated successfully"
        return 0
    else
        log_warn "Sample image generation failed: ${result}"
        return 1
    fi
}