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
    log_info "Dataset validated: ${image_count} images found"
    return 0
}

export -f log_info log_warn log_error validate_dataset