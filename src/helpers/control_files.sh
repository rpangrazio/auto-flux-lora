#!/usr/bin/env bash
# ============================================
# Control Files Helper
# Flux.1 LoRA Training Pipeline
# ============================================

QUEUE_DIR="${PIPELINE_QUEUE_DIR:-/data/queue}"
OUTPUT_DIR="${PIPELINE_OUTPUT_DIR:-/data/output}"

write_done_file() {
    local job_id="$1"
    local output_path="$2"
    local final_loss="${3:-}"
    local exit_code="${4:-0}"
    local duration="${5:-0}"
    local done_file="${OUTPUT_DIR}/${job_id}/.done"
    cat > "${done_file}" <<EOF
job_id=${job_id}
status=DONE
output_path=${output_path}
final_loss=${final_loss}
exit_code=${exit_code}
duration=${duration}
timestamp=$(date -Iseconds)
EOF
    log_info "Done file written: ${done_file}"
}

write_fail_file() {
    local job_id="$1"
    local error_message="$2"
    local exit_code="${3:-1}"
    local fail_file="${OUTPUT_DIR}/${job_id}/.failed"
    cat > "${fail_file}" <<EOF
job_id=${job_id}
status=FAILED
error_message=${error_message}
exit_code=${exit_code}
timestamp=$(date -Iseconds)
EOF
    log_info "Fail file written: ${fail_file}"
}

create_lock_file() {
    local lock_file="${QUEUE_DIR}/.lock"
    local pid=$$
    local timestamp
    timestamp=$(date +%s)
    echo "${pid}:${timestamp}" > "${lock_file}"
    log_info "Lock file created: ${lock_file}"
}

update_lock_heartbeat() {
    local lock_file="${QUEUE_DIR}/.lock"
    if [[ -f "${lock_file}" ]]; then
        touch "${lock_file}"
    fi
}

is_lock_stale() {
    local lock_file="${QUEUE_DIR}/.lock"
    local timeout="${1:-300}"
    if [[ ! -f "${lock_file}" ]]; then
        return 1
    fi
    local lock_content
    lock_content=$(cat "${lock_file}" 2>/dev/null || echo "")
    if [[ -z "${lock_content}" ]]; then
        return 0
    fi
    local lock_timestamp
    lock_timestamp=$(echo "${lock_content}" | cut -d: -f2)
    local age=$(( $(date +%s) - lock_timestamp ))
    if (( age > timeout )); then
        return 0
    fi
    return 1
}

remove_lock_file() {
    local lock_file="${QUEUE_DIR}/.lock"
    rm -f "${lock_file}"
    log_info "Lock file removed: ${lock_file}"
}