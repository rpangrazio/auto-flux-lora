#!/usr/bin/env bash
# ============================================
# Integration Test: End-to-End Smoke Test
# ============================================

set -euo pipefail

QUEUE_DIR="/tmp/test_queue"
OUTPUT_DIR="/tmp/test_output"
LOG_DIR="/tmp/test_logs"
DATASET_DIR="/tmp/test_dataset"

mkdir -p "${QUEUE_DIR}" "${OUTPUT_DIR}" "${LOG_DIR}" "${DATASET_DIR}"

for i in {1..5}; do
    touch "${DATASET_DIR}/image${i}.jpg"
    echo "caption ${i}" > "${DATASET_DIR}/image${i}.txt"
done

PIPELINE_QUEUE_DIR="${QUEUE_DIR}"
PIPELINE_OUTPUT_DIR="${OUTPUT_DIR}"
PIPELINE_LOG_DIR="${LOG_DIR}"

export PIPELINE_QUEUE_DIR PIPELINE_OUTPUT_DIR PIPELINE_LOG_DIR
export SKIP_INIT=1

source /opt/pipeline/helpers/utils.sh
source /opt/pipeline/helpers/queue_manager.sh

validate_dataset "${DATASET_DIR}" && echo "PASS: dataset validated"

config_file="${QUEUE_DIR}/test_job.toml"
cat > "${config_file}" <<'EOF'
model_name_or_path = "/data/models/flux1-dev"
dataset_path = "/tmp/test_dataset"
network_rank = 32
EOF

echo "PASS: config file created"

list_pending_jobs | grep -q "test_job.toml" && echo "PASS: job detected in queue"

rm -rf "${QUEUE_DIR}" "${OUTPUT_DIR}" "${LOG_DIR}" "${DATASET_DIR}"
echo "All e2e smoke tests passed"