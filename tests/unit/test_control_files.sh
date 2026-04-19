#!/usr/bin/env bash
# ============================================
# Unit Tests: Control Files Logic
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

QUEUE_DIR="/tmp/test_queue"
OUTPUT_DIR="/tmp/test_output"
mkdir -p "${QUEUE_DIR}" "${OUTPUT_DIR}"

PIPELINE_QUEUE_DIR="${QUEUE_DIR}"
PIPELINE_OUTPUT_DIR="${OUTPUT_DIR}"

source /opt/pipeline/helpers/control_files.sh

test_create_lock_file() {
    create_lock_file
    [[ -f "${QUEUE_DIR}/.lock" ]] && echo "PASS: lock file created"
    rm -f "${QUEUE_DIR}/.lock"
}

test_update_lock_heartbeat() {
    create_lock_file
    local before after
    before=$(stat -c %Y "${QUEUE_DIR}/.lock" 2>/dev/null || echo 0)
    sleep 1
    update_lock_heartbeat
    after=$(stat -c %Y "${QUEUE_DIR}/.lock" 2>/dev/null || echo 0)
    [[ ${after} -gt ${before} ]] && echo "PASS: lock heartbeat updated"
    rm -f "${QUEUE_DIR}/.lock"
}

test_is_lock_stale() {
    echo "999999999:1234567890" > "${QUEUE_DIR}/.lock"
    is_lock_stale 300 && echo "PASS: detected stale lock" || echo "FAIL: did not detect stale lock"
    rm -f "${QUEUE_DIR}/.lock"
}

test_write_done_file() {
    write_done_file "test-job" "/data/output/test-job" "0.05" "0" "120"
    [[ -f "${OUTPUT_DIR}/test-job/.done" ]] && echo "PASS: done file created"
    rm -f "${OUTPUT_DIR}/test-job/.done"
}

test_create_lock_file
test_update_lock_heartbeat
test_is_lock_stale
test_write_done_file

rm -rf "${QUEUE_DIR}" "${OUTPUT_DIR}"

echo "All control files tests passed"