#!/usr/bin/env bash
# ============================================
# GPU Monitor Helper
# Flux.1 LoRA Training Pipeline
# ============================================

detect_gpu_info() {
    if command -v nvidia-smi &>/dev/null; then
        local gpu_name gpu_vram compute_cap
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
        gpu_vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader 2>/dev/null | head -1 | awk '{print $1}' || echo "0")
        compute_cap=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 || echo "0")
        log_info "GPU detected: ${gpu_name} (${gpu_vram} MB, compute ${compute_cap})"
        log_event "SYSTEM" "GPU detected: ${gpu_name} (${gpu_vram} MB)"
        return 0
    else
        log_warn "nvidia-smi not available"
        return 1
    fi
}

get_gpu_utilization() {
    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=utilization.gpu,utilization.memory,memory.used,temperature.gpu \
            --format=csv,noheader,nounits 2>/dev/null | head -1
    fi
}

get_optimal_precision() {
    local compute_cap="${1:-6.1}"
    if (( $(echo "${compute_cap} >= 8.0" | bc -l 2>/dev/null || echo 0) )); then
        echo "bf16"
    else
        echo "fp16"
    fi
}

monitor_vram() {
    local threshold="${1:-95}"
    local utilization
    utilization=$(get_gpu_utilization)
    if [[ -n "${utilization}" ]]; then
        local vram_used
        vram_used=$(echo "${utilization}" | awk -F',' '{print $3}' | xargs)
        local vram_pct=$(( vram_used * 100 / 24576 ))
        if (( vram_pct > threshold )); then
            log_warn "VRAM usage high: ${vram_pct}% (${vram_used} MB)"
            return 1
        fi
    fi
    return 0
}

monitor_temperature() {
    local warn_threshold="${1:-85}"
    local crit_threshold="${2:-90}"
    local temp
    temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | xargs)
    if [[ -n "${temp}" ]]; then
        if (( temp > crit_threshold )); then
            log_error "GPU temperature critical: ${temp}°C"
            return 2
        elif (( temp > warn_threshold )); then
            log_warn "GPU temperature elevated: ${temp}°C"
            return 1
        fi
    fi
    return 0
}