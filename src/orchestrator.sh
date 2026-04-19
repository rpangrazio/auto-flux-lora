#!/usr/bin/env bash
# ============================================
# Orchestrator Main Entry Point
# Flux.1 LoRA Training Pipeline
# ============================================

set -euo pipefail

PIPELINE_DIR="${PIPELINE_DIR:-/opt/pipeline}"
QUEUE_DIR="${PIPELINE_QUEUE_DIR:-/data/queue}"
OUTPUT_DIR="${PIPELINE_OUTPUT_DIR:-/data/output}"
LOG_DIR="${PIPELINE_LOG_DIR:-/data/logs}"
DATASET_DIR="${PIPELINE_DATASET_DIR:-/data/datasets}"
CONFIG_DIR="${PIPELINE_CONFIG_DIR:-/data/configs}"
POLL_INTERVAL="${PIPELINE_POLL_INTERVAL:-30}"
MAX_CONCURRENT="${PIPELINE_MAX_CONCURRENT:-1}"
MAX_RETRIES="${PIPELINE_MAX_RETRIES:-2}"
GPU_TEMP_WARN="${GPU_TEMP_WARN:-85}"
GPU_TEMP_CRIT="${GPU_TEMP_CRIT:-90}"
WEBHOOK_TIMEOUT="${WEBHOOK_TIMEOUT:-30}"

LOCK_FILE="${QUEUE_DIR}/.lock"
PID_FILE="${QUEUE_DIR}/.pid"

source "${PIPELINE_DIR}/helpers/config_parser.sh"
source "${PIPELINE_DIR}/helpers/queue_manager.sh"
source "${PIPELINE_DIR}/helpers/db_manager.sh"
source "${PIPELINE_DIR}/helpers/gpu_monitor.sh"
source "${PIPELINE_DIR}/helpers/control_files.sh"
source "${PIPELINE_DIR}/helpers/training_executor.sh"
source "${PIPELINE_DIR}/helpers/utils.sh"

init_orchestrator() {
    log_info "=========================================="
    log_info "Flux.1 LoRA Training Orchestrator v1.0"
    log_info "=========================================="
    mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}" "${DATASET_DIR}" "${CONFIG_DIR}"
    detect_gpu_info
    capture_environment_info
    init_database
    check_stale_lock
    acquire_lock
    log_event "SYSTEM" "Orchestrator initialized"
}

capture_environment_info() {
    log_info "=========================================="
    log_info "Environment Capture"
    log_info "=========================================="
    if command -v nvidia-smi &>/dev/null; then
        local cuda_version gpu_driver
        cuda_version=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo "unknown")
        log_info "GPU Driver Version: ${cuda_version}"
        log_event "SYSTEM" "GPU driver: ${cuda_version}"
    fi
    if command -v nvcc &>/dev/null; then
        local nvcc_version
        nvcc_version=$(nvcc --version 2>/dev/null | grep "release" | sed 's/.*release \([0-9.]*\).*/\1/' || echo "unknown")
        log_info "CUDA Toolkit Version: ${nvcc_version}"
        log_event "SYSTEM" "CUDA toolkit: ${nvcc_version}"
    elif [[ -f /usr/local/cuda/version.txt ]]; then
        local cuda_ver
        cuda_ver=$(cat /usr/local/cuda/version.txt 2>/dev/null | grep "CUDA Version" | sed 's/CUDA Version: //' | xargs || echo "unknown")
        log_info "CUDA Version: ${cuda_ver}"
        log_event "SYSTEM" "CUDA version: ${cuda_ver}"
    fi
    local python_version
    python_version=$(python3 --version 2>&1 | awk '{print $2}' || echo "unknown")
    log_info "Python Version: ${python_version}"
    log_event "SYSTEM" "Python: ${python_version}"
    if command -v pip &>/dev/null; then
        local torch_version transformers_version diffusers_version accelerate_version
        torch_version=$(pip show torch 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "not installed")
        transformers_version=$(pip show transformers 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "not installed")
        diffusers_version=$(pip show diffusers 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "not installed")
        accelerate_version=$(pip show accelerate 2>/dev/null | grep "^Version:" | awk '{print $2}' || echo "not installed")
        log_info "Python Packages:"
        log_info "  torch: ${torch_version}"
        log_info "  transformers: ${transformers_version}"
        log_info "  diffusers: ${diffusers_version}"
        log_info "  accelerate: ${accelerate_version}"
        log_event "SYSTEM" "torch=${torch_version} transformers=${transformers_version} diffusers=${diffusers_version} accelerate=${accelerate_version}"
    fi
    log_info "=========================================="
}

acquire_lock() {
    local pid=$$
    local timestamp
    timestamp=$(date +%s)
    echo "${pid}:${timestamp}" > "${LOCK_FILE}"
    echo "${pid}" > "${PID_FILE}"
    log_info "Lock acquired: ${LOCK_FILE} (PID: ${pid})"
}

release_lock() {
    rm -f "${LOCK_FILE}" "${PID_FILE}"
    log_info "Lock released"
}

check_stale_lock() {
    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_content
        lock_content=$(cat "${LOCK_FILE}" 2>/dev/null || echo "")
        if [[ -n "${lock_content}" ]]; then
            local lock_pid lock_timestamp
            lock_pid=$(echo "${lock_content}" | cut -d: -f1)
            lock_timestamp=$(echo "${lock_content}" | cut -d: -f2)
            local age=$(( $(date +%s) - lock_timestamp ))
            if (( age > 300 )); then
                log_warn "Stale lock detected (PID ${lock_pid}, age ${age}s). Removing."
                rm -f "${LOCK_FILE}"
                log_event "SYSTEM" "Stale lock removed on startup"
            else
                local existing_pid
                existing_pid=$(cat "${PID_FILE}" 2>/dev/null || echo "")
                if [[ -n "${existing_pid}" ]] && kill -0 "${existing_pid}" 2>/dev/null; then
                    log_error "Another orchestrator instance is running (PID: ${existing_pid})"
                    exit 1
                else
                    log_warn "Stale lock from dead process. Removing."
                    rm -f "${LOCK_FILE}"
                fi
            fi
        fi
    fi
}

is_orchestrator_paused() {
    [[ -f "${QUEUE_DIR}/.pause" ]]
}

is_orchestrator_cancelled() {
    [[ -f "${QUEUE_DIR}/.cancel" ]]
}

wait_while_paused() {
    while is_orchestrator_paused; do
        log_info "Orchestrator paused - waiting for .pause removal"
        sleep "${POLL_INTERVAL}"
    done
}

process_queue() {
    local config_files
    config_files=($(list_pending_jobs_by_priority))
    if [[ ${#config_files[@]} -eq 0 ]]; then
        return
    fi
    local running_count
    running_count=$(get_running_job_count)
    if (( running_count >= MAX_CONCURRENT )); then
        log_info "Max concurrent jobs (${MAX_CONCURRENT}) reached. Waiting..."
        return
    fi
    local job_file="${config_files[0]}"
    local job_id
    job_id=$(get_job_id "${job_file}")
    process_job "${job_file}" "${job_id}"
}

process_job() {
    local config_file="$1"
    local job_id="$2"
    local retry_count=0
    local max_retries="${MAX_RETRIES}"
    local batch_size

    log_info "=========================================="
    log_info "Processing job: ${job_id}"
    log_info "=========================================="

    local config_hash
    config_hash=$(compute_config_hash "${config_file}")
    local config_json
    config_json=$(cat "${config_file}" 2>/dev/null || echo "{}")

    insert_run "${job_id}" "${config_hash}" "${config_json}" "$(parse_config_value "${config_file}" "priority" "0")"
    transition_state "${job_id}" "QUEUED" "PREPARING"
    snapshot_config "${config_file}" "${job_id}"

    if ! validate_dataset "$(parse_config_value "${config_file}" "dataset_path")"; then
        log_error "Dataset validation failed for job: ${job_id}"
        transition_state "${job_id}" "PREPARING" "FAILED"
        write_fail_file "${job_id}" "Dataset validation failed" "1"
        send_notification_webhook "${config_file}" "${job_id}" "FAILED"
        return 1
    fi

    batch_size=$(parse_config_value "${config_file}" "batch_size" "1")

    while true; do
        transition_state "${job_id}" "PREPARING" "TRAINING"
        log_info "Training started: ${job_id} (batch_size=${batch_size}, attempt=$((retry_count + 1)))"

        local log_file="${LOG_DIR}/${job_id}.log"
        run_training_with_hooks "${config_file}" "${job_id}" "${log_file}"
        local exit_code=$?

        if [[ ${exit_code} -eq 0 ]]; then
            transition_state "${job_id}" "TRAINING" "DONE"
            write_done_file "${job_id}" "${OUTPUT_DIR}/${job_id}" "" "0" "$(get_job_duration "${job_id}")"
            log_info "Job completed successfully: ${job_id}"
            send_notification_webhook "${config_file}" "${job_id}" "DONE"
            break
        else
            log_error "Training failed for job: ${job_id} (exit code: ${exit_code})"

            if detect_oom "${log_file}" && [[ "$(parse_config_value "${config_file}" "retry_on_oom" "true")" == "true" ]]; then
                if (( retry_count < max_retries )); then
                    retry_count=$((retry_count + 1))
                    batch_size=$(halve_batch_size "${config_file}")
                    log_warn "OOM detected. Retrying with batch_size=${batch_size} (attempt ${retry_count}/${max_retries})"
                    update_retry_count "${job_id}" "${retry_count}" "${batch_size}"
                    continue
                fi
            fi

            transition_state "${job_id}" "TRAINING" "FAILED"
            write_fail_file "${job_id}" "Training failed (exit code: ${exit_code})" "${exit_code}"
            send_notification_webhook "${config_file}" "${job_id}" "FAILED"
            break
        fi
    done

    update_lock_timestamp
    cleanup_job_artifacts "${job_id}"
}

run_training_with_hooks() {
    local config_file="$1"
    local job_id="$2"
    local log_file="$3"

    exec 3>&1
    local training_pid
    (
        exec execute_training "${config_file}" "${job_id}" > "${log_file}" 2>&1
    ) &
    training_pid=$!
    local last_monitoring=0

    while kill -0 ${training_pid} 2>/dev/null; do
        if (( $(date +%s) - last_monitoring > 30 )); then
            monitor_vram 90
            if [[ $? -ne 0 ]]; then
                log_warn "VRAM usage elevated during training: ${job_id}"
            fi
        fi
        if (( $(date +%s) - last_monitoring > 60 )); then
            local temp_status
            temp_status=$(monitor_temperature "${GPU_TEMP_WARN}" "${GPU_TEMP_CRIT}")
            local temp_code=$?
            if [[ ${temp_code} -eq 2 ]]; then
                log_error "GPU temperature critical - terminating job: ${job_id}"
                kill -TERM ${training_pid} 2>/dev/null
                sleep 5
                kill -KILL ${training_pid} 2>/dev/null || true
                return 255
            elif [[ ${temp_code} -eq 1 ]]; then
                log_warn "GPU temperature elevated - continuing monitoring"
            fi
            last_monitoring=$(date +%s)
        fi
        sleep 10
    done

    wait ${training_pid}
    return $?
}

snapshot_config() {
    local config_file="$1"
    local job_id="$2"
    local snapshot_dir="${CONFIG_DIR}/${job_id}"
    mkdir -p "${snapshot_dir}"
    cp "${config_file}" "${snapshot_dir}/config.toml"
    log_info "Config snapshot saved: ${snapshot_dir}/config.toml"
}

send_notification_webhook() {
    local config_file="$1"
    local job_id="$2"
    local status="$3"

    local webhook_url
    webhook_url=$(parse_config_value "${config_file}" "notification_webhook" "")

    if [[ -z "${webhook_url}" ]]; then
        return 0
    fi

    local duration
    duration=$(get_job_duration "${job_id}")

    local payload
    payload=$(cat <<EOF
{
    "job_id": "${job_id}",
    "status": "${status}",
    "duration": ${duration},
    "output_path": "${OUTPUT_DIR}/${job_id}",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

    log_info "Sending webhook notification: ${webhook_url}"
    send_webhook "${webhook_url}" "${payload}"
}

update_retry_count() {
    local job_id="$1"
    local retry_count="$2"
    local batch_size="$3"
    sqlite3 "${LOG_DIR}/training.db" \
        "UPDATE runs SET retry_count=${retry_count}, batch_size_used=${batch_size} WHERE job_id='${job_id}';"
}

cleanup_job_artifacts() {
    local job_id="$1"
    local job_dir="${OUTPUT_DIR}/${job_id}"
    if [[ -d "${job_dir}" ]]; then
        find "${job_dir}" -name "*.tmp" -delete 2>/dev/null || true
    fi
}

update_lock_timestamp() {
    if [[ -f "${LOCK_FILE}" ]]; then
        local pid=$$
        local timestamp
        timestamp=$(date +%s)
        echo "${pid}:${timestamp}" > "${LOCK_FILE}"
        touch "${LOCK_FILE}"
    fi
}

main_loop() {
    log_info "Starting main orchestration loop (poll_interval=${POLL_INTERVAL}s)"
    while true; do
        if is_orchestrator_cancelled; then
            log_warn "Cancel signal received - shutting down gracefully"
            rm -f "${QUEUE_DIR}/.cancel"
            release_lock
            exit 0
        fi

        wait_while_paused

        process_queue

        update_lock_timestamp
        sleep "${POLL_INTERVAL}"
    done
}

shutdown() {
    log_info "Shutdown signal received - cleaning up"
    release_lock
    log_event "SYSTEM" "Orchestrator shutdown"
    exit 0
}

trap shutdown SIGTERM SIGINT

if [[ -z "${SKIP_INIT:-}" ]]; then
    init_orchestrator
fi

main_loop