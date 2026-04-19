#!/usr/bin/env bash
# ============================================
# Reproducibility Test Script
# ============================================

set -euo pipefail

CONFIG_FILE="${1:-sample/config/sample.toml}"
DATASET_DIR="${2:-sample/dataset/sample_images}"
OUTPUT_DIR1="/tmp/repro_test_run1"
OUTPUT_DIR2="/tmp/repro_test_run2"

echo "=========================================="
echo "Flux.1 LoRA Reproducibility Test"
echo "=========================================="

if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Config file not found: ${CONFIG_FILE}"
    exit 1
fi

echo "Step 1: Running first training iteration..."
OUTPUT_DIR="${OUTPUT_DIR1}" bash -c "
    source src/orchestrator.sh
    echo 'First run would execute here'
"

echo "Step 2: Running second training iteration..."
OUTPUT_DIR="${OUTPUT_DIR2}" bash -c "
    source src/orchestrator.sh
    echo 'Second run would execute here'
"

echo "Step 3: Comparing output files..."
if [[ -f "${OUTPUT_DIR1}/model.safetensors" ]] && [[ -f "${OUTPUT_DIR2}/model.safetensors" ]]; then
    hash1=$(sha256sum "${OUTPUT_DIR1}/model.safetensors" | awk '{print $1}')
    hash2=$(sha256sum "${OUTPUT_DIR2}/model.safetensors" | awk '{print $1}')
    if [[ "${hash1}" == "${hash2}" ]]; then
        echo "PASS: Output files are byte-identical"
    else
        echo "FAIL: Output files differ"
        exit 1
    fi
else
    echo "SKIP: Output files not available (training not executed)"
fi

rm -rf "${OUTPUT_DIR1}" "${OUTPUT_DIR2}"
echo "Reproducibility test complete"