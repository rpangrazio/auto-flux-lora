#!/usr/bin/env bash
# ============================================
# Queue Manager Helper
# Flux.1 LoRA Training Pipeline
# ============================================

QUEUE_DIR="${PIPELINE_QUEUE_DIR:-/data/queue}"

list_pending_jobs() {
    find "${QUEUE_DIR}" -maxdepth 1 -type f \( -name "*.toml" -o -name "*.yaml" -o -name "*.yml" \) \
        ! -name ".lock" ! -name ".pause" ! -name ".cancel" ! -name ".done" \
        -printf '%T+ %p\n' 2>/dev/null | sort | awk '{print $2}'
}

list_pending_jobs_by_priority() {
    find "${QUEUE_DIR}" -maxdepth 1 -type f \( -name "*.toml" -o -name "*.yaml" -o -name "*.yml" \) \
        ! -name ".lock" ! -name ".pause" ! -name ".cancel" ! -name ".done" \
        -printf '%f\n' 2>/dev/null | while read -r file; do
        local priority
        priority=$(parse_config_value "${QUEUE_DIR}/${file}" "priority" 2>/dev/null || echo "0")
        echo "${priority}:${file}"
    done | sort -rn | cut -d: -f2-
}

enqueue_job() {
    local config_file="$1"
    local job_id
    job_id=$(get_job_id "${config_file}")
    log_info "Job enqueued: ${job_id}"
}

get_running_job_count() {
    local count
    count=$(sqlite3 "${LOG_DIR}/training.db" \
        "SELECT COUNT(*) FROM runs WHERE status IN ('PREPARING', 'TRAINING');" 2>/dev/null || echo "0")
    echo "${count}"
}

is_queue_paused() {
    [[ -f "${QUEUE_DIR}/.pause" ]]
}

is_job_cancelled() {
    [[ -f "${QUEUE_DIR}/.cancel" ]]
}