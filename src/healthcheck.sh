#!/usr/bin/env bash
# ============================================
# Healthcheck Script
# Flux.1 LoRA Training Pipeline
# ============================================

set -euo pipefail

LOCK_FILE="${PIPELINE_QUEUE_DIR:-/data/queue}/.lock"
TIMEOUT="${HEARTBEAT_TIMEOUT:-300}"

if [[ ! -f "${LOCK_FILE}" ]]; then
    echo "ERROR: No lock file found"
    exit 1
fi

lock_content=$(cat "${LOCK_FILE}" 2>/dev/null || echo "")
if [[ -z "${lock_content}" ]]; then
    echo "ERROR: Lock file is empty"
    exit 1
fi

lock_timestamp=$(echo "${lock_content}" | cut -d: -f2)
current_time=$(date +%s)
age=$(( current_time - lock_timestamp ))

if (( age > TIMEOUT )); then
    echo "ERROR: Stale lock (age: ${age}s > timeout: ${TIMEOUT}s)"
    exit 1
fi

echo "OK: Orchestrator healthy (lock age: ${age}s)"
exit 0