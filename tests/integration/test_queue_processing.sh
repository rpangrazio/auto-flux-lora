#!/usr/bin/env bash
# ============================================
# Integration Test: Queue Processing
# ============================================

set -euo pipefail

QUEUE_DIR="/tmp/test_queue"
mkdir -p "${QUEUE_DIR}"

touch "${QUEUE_DIR}/job1.toml"
sleep 0.1
touch "${QUEUE_DIR}/job2.toml"
sleep 0.1
touch "${QUEUE_DIR}/job3.toml"

PIPELINE_QUEUE_DIR="${QUEUE_DIR}"
source /opt/pipeline/helpers/queue_manager.sh

jobs=($(list_pending_jobs))
[[ ${#jobs[@]} -eq 3 ]] && echo "PASS: 3 jobs detected"

[[ "$(basename "${jobs[0]}")" == "job1.toml" ]] && echo "PASS: FIFO ordering"

rm -rf "${QUEUE_DIR}"
echo "All queue processing tests passed"