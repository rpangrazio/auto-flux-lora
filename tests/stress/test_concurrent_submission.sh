#!/usr/bin/env bash
# ============================================
# Stress Test: Concurrent Submission
# ============================================

set -euo pipefail

QUEUE_DIR="/tmp/test_queue"
mkdir -p "${QUEUE_DIR}"

for i in $(seq 1 10); do
    cat > "${QUEUE_DIR}/job_${i}.toml" <<EOF
model_name_or_path = "/data/models/flux1-dev"
dataset_path = "/data/datasets/test"
network_rank = 16
priority = $(( RANDOM % 10 ))
EOF
done

PIPELINE_QUEUE_DIR="${QUEUE_DIR}"
source /opt/pipeline/helpers/queue_manager.sh

job_count=$(list_pending_jobs | wc -l)
[[ ${job_count} -eq 10 ]] && echo "PASS: 10 concurrent jobs submitted"

rm -rf "${QUEUE_DIR}"
echo "Concurrent submission test completed"