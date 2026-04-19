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
POLL_INTERVAL="${PIPELINE_POLL_INTERVAL:-30}"
MAX_CONCURRENT="${PIPELINE_MAX_CONCURRENT:-1}"
LOCK_FILE="${QUEUE_DIR}/.lock"

source "${PIPELINE_DIR}/helpers/config_parser.sh"
source "${PIPELINE_DIR}/helpers/queue_manager.sh"
source "${PIPELINE_DIR}/helpers/db_manager.sh"
source "${PIPELINE_DIR}/helpers/gpu_monitor.sh"
source "${PIPELINE_DIR}/helpers/control_files.sh"

init_orchestrator() {
    log_info "Initializing Flux.1 LoRA Training Orchestrator"
    detect_gpu_info
    init_database
    check_stale_lock
    acquire_lock
}

acquire_lock() {
    local pid=$$
    local timestamp
    timestamp=$(date +%s)
    echo "${pid}:${timestamp}" > "${LOCK_FILE}"
    log_info "Lock acquired: ${LOCK_FILE}"
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
            fi
        fi
    fi
}

process_queue() {
    local config_files
    config_files=($(list_pending_jobs))
    if [[ ${#config_files[@]} -eq 0 ]]; then
        return
    fi
    local running_count
    running_count=$(get_running_job_count)
    if (( running_count >= MAX_CONCURRENT )); then
        return
    fi
    local job_file="${config_files[0]}"
    local job_id
    job_id=$(parse_config_value "${job_file}" "job_id" 2>/dev/null || basename "${job_file}" .toml)
    process_job "${job_file}" "${job_id}"
}

process_job() {
    local config_file="$1"
    local job_id="$2"
    log_info "Processing job: ${job_id}"
    transition_state "${job_id}" "QUEUED" "PREPARING"
    if ! validate_dataset "$(parse_config_value "${config_file}" "dataset_path")"; then
        transition_state "${job_id}" "PREPARING" "FAILED"
        return 1
    fi
    transition_state "${job_id}" "PREPARING" "TRAINING"
    run_training "${config_file}" "${job_id}"
    local exit_code=$?
    if [[ ${exit_code} -eq 0 ]]; then
        transition_state "${job_id}" "TRAINING" "DONE"
        write_done_file "${job_id}"
    else
        handle_job_failure "${job_id}" "${exit_code}"
    fi
    update_lock_timestamp
}

run_training() {
    local config_file="$1"
    local job_id="$2"
    local log_file="${LOG_DIR}/${job_id}.log"
    log_info "Training started: ${job_id}"
    transition_state "${job_id}" "PREPARING" "TRAINING"
    return 0
}

handle_job_failure() {
    local job_id="$1"
    local exit_code="$2"
    log_error "Job failed: ${job_id} (exit code: ${exit_code})"
    transition_state "${job_id}" "TRAINING" "FAILED"
}

write_done_file() {
    local job_id="$1"
    local done_file="${OUTPUT_DIR}/${job_id}/.done"
    local duration
    duration=$(get_job_duration "${job_id}")
    cat > "${done_file}" <<EOF
job_id=${job_id}
status=DONE
duration=${duration}
timestamp=$(date -Iseconds)
EOF
    log_info "Done file written: ${done_file}"
}

update_lock_timestamp() {
    touch "${LOCK_FILE}"
}

main_loop() {
    while true; do
        check_pause_file
        check_cancel_file
        process_queue
        sleep "${POLL_INTERVAL}"
    done
}

check_pause_file() {
    if [[ -f "${QUEUE_DIR}/.pause" ]]; then
        log_info "Orchestrator paused - .pause file detected"
        while [[ -f "${QUEUE_DIR}/.pause" ]]; do
            sleep "${POLL_INTERVAL}"
        done
        log_info "Orchestrator resumed - .pause file removed"
    fi
}

check_cancel_file() {
    if [[ -f "${QUEUE_DIR}/.cancel" ]]; then
        log_warn "Cancel signal received"
        rm -f "${QUEUE_DIR}/.cancel"
        exit 0
    fi
}

trap shutdown SIGTERM SIGINT
shutdown() {
    log_info "Shutdown signal received"
    if [[ -f "${LOCK_FILE}" ]]; then
        rm -f "${LOCK_FILE}"
    fi
    exit 0
}

if [[ -z "${SKIP_INIT:-}" ]]; then
    init_orchestrator
fi

main_loop