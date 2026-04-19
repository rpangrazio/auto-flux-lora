#!/usr/bin/env bash
# ============================================
# Storage Setup Script
# ============================================

set -euo pipefail

DATA_DIR="${1:-/srv/lora-pipeline/data}"

echo "Setting up LoRA training pipeline storage at: ${DATA_DIR}"

mkdir -p "${DATA_DIR}"/{datasets,configs,output,logs,queue}

chmod 755 "${DATA_DIR}"
chmod 755 "${DATA_DIR}"/datasets
chmod 755 "${DATA_DIR}"/configs
chmod 755 "${DATA_DIR}"/output
chmod 755 "${DATA_DIR}"/logs
chmod 755 "${DATA_DIR}"/queue

echo "Directory structure created:"
echo "  ${DATA_DIR}/datasets/  - Training datasets"
echo "  ${DATA_DIR}/configs/   - Job configuration files"
echo "  ${DATA_DIR}/output/    - Trained adapter outputs"
echo "  ${DATA_DIR}/logs/      - SQLite database and log files"
echo "  ${DATA_DIR}/queue/     - Job queue directory"

echo "Storage setup complete"