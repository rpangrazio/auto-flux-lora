#!/usr/bin/env bash
# ============================================
# Stress Test: Stale Lock Recovery
# ============================================

set -euo pipefail

QUEUE_DIR="/tmp/test_queue"
mkdir -p "${QUEUE_DIR}"

echo "999999:1234567890" > "${QUEUE_DIR}/.lock"

PIPELINE_QUEUE_DIR="${QUEUE_DIR}"
source /opt/pipeline/helpers/control_files.sh

is_lock_stale 300 && echo "PASS: stale lock detected" || echo "FAIL: lock not detected as stale"

rm -rf "${QUEUE_DIR}"
echo "Stale lock recovery test completed"