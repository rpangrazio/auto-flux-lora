#!/usr/bin/env bash
# ============================================
# Queue Manager Helper
# Flux.1 LoRA Training Pipeline
# ============================================

QUEUE_DIR="${PIPELINE_QUEUE_DIR:-/data/queue}"

list_pending_jobs() {
    find "${QUEUE_DIR}" -maxdepth 1 -type f \( -name "*.toml" -o -name "*.yaml" -o -name "*.yml" \) \
        ! -name ".lock" ! -name ".pause" ! -name ".cancel" ! -name ".done" \
        ! -name ".failed" \
        -printf '%T+ %p\n' 2>/dev/null | sort | awk '{print $2}'
}

list_pending_jobs_by_priority() {
    local temp_file="/tmp/priority_jobs_$$.tmp"
    rm -f "${temp_file}"
    find "${QUEUE_DIR}" -maxdepth 1 -type f \( -name "*.toml" -o -name "*.yaml" -o -name "*.yml" \) \
        ! -name ".lock" ! -name ".pause" ! -name ".cancel" ! -name ".done" ! -name ".failed" \
        -print 2>/dev/null | while read -r file; do
        local file_basename
        file_basename=$(basename "${file}")
        local priority
        priority=$(parse_config_value_from_file "${file}" "priority" 2>/dev/null || echo "0")
        echo "${priority}:${file_basename}:${file}"
    done | sort -rn | cut -d: -f3-
    rm -f "${temp_file}"
}

parse_config_value_from_file() {
    local config_file="$1"
    local key="$2"
    if [[ ! -f "${config_file}" ]]; then
        echo ""
        return 1
    fi
    local value=""
    if [[ "${config_file}" == *.toml ]]; then
        value=$(grep -E "^${key}\s*=" "${config_file}" | sed 's/^[^=]*=[ ]*//' | tr -d '"' | tr -d "'" | xargs)
    elif [[ "${config_file}" == *.yaml || "${config_file}" == *.yml ]]; then
        value=$(grep -E "^\s*${key}\s*:" "${config_file}" | sed 's/^[^:]*:[ ]*//' | xargs)
    fi
    echo "${value}"
}

enqueue_job() {
    local config_file="$1"
    local job_id
    job_id=$(get_job_id_from_file "${config_file}")
    log_info "Job enqueued: ${job_id}"
}

get_job_id_from_file() {
    local config_file="$1"
    local job_id
    job_id=$(parse_config_value_from_file "${config_file}" "job_id")
    if [[ -z "${job_id}" ]]; then
        job_id=$(basename "${config_file}" | sed 's/\.[^.]*$//')
    fi
    echo "${job_id}"
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

get_queue_stats() {
    local total pending running completed failed
    total=$(sqlite3 "${LOG_DIR}/training.db" "SELECT COUNT(*) FROM runs;" 2>/dev/null || echo "0")
    pending=$(sqlite3 "${LOG_DIR}/training.db" "SELECT COUNT(*) FROM runs WHERE status='QUEUED';" 2>/dev/null || echo "0")
    running=$(sqlite3 "${LOG_DIR}/training.db" "SELECT COUNT(*) FROM runs WHERE status IN ('PREPARING', 'TRAINING');" 2>/dev/null || echo "0")
    completed=$(sqlite3 "${LOG_DIR}/training.db" "SELECT COUNT(*) FROM runs WHERE status='DONE';" 2>/dev/null || echo "0")
    failed=$(sqlite3 "${LOG_DIR}/training.db" "SELECT COUNT(*) FROM runs WHERE status='FAILED';" 2>/dev/null || echo "0")
    echo "{\"total\":${total},\"pending\":${pending},\"running\":${running},\"completed\":${completed},\"failed\":${failed}}"
}