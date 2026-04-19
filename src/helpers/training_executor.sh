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
    if [[ -n "${gpu_name}" ]]; then
        if [[ "${gpu_name}" == *"A100"* || "${gpu_name}" == *"H100"* || "${gpu_name}" == *"RTX 40"* ]]; then
            echo "bf16"
            return
        elif [[ "${gpu_name}" == *"RTX 30"* || "${gpu_name}" == *"RTX 20"* || "${gpu_name}" == *"GTX 16"* ]]; then
            echo "fp16"
            return
        fi
    fi
    echo "fp16"
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
    if command -v nvidia-smi &>/dev/null; then
        gpu_name=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
    fi
    local precision
    precision=$(get_optimal_precision "${gpu_name}")

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