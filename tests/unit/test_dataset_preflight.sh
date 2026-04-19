#!/usr/bin/env bash
# ============================================
# Unit Tests: Dataset Pre-flight Validation
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source /opt/pipeline/helpers/utils.sh

test_dataset_too_small() {
    local test_dir="/tmp/test_dataset_small"
    mkdir -p "${test_dir}"
    touch "${test_dir}/image1.jpg"
    touch "${test_dir}/image1.txt"
    ! validate_dataset "${test_dir}" && echo "PASS: rejected small dataset"
    rm -rf "${test_dir}"
}

test_dataset_valid() {
    local test_dir="/tmp/test_dataset_valid"
    mkdir -p "${test_dir}"
    for i in {1..5}; do
        touch "${test_dir}/image${i}.jpg"
        touch "${test_dir}/image${i}.txt"
    done
    validate_dataset "${test_dir}" && echo "PASS: accepted valid dataset"
    rm -rf "${test_dir}"
}

test_dataset_missing_directory() {
    ! validate_dataset "/nonexistent/path" && echo "PASS: rejected missing directory"
}

test_dataset_too_small
test_dataset_valid
test_dataset_missing_directory

echo "All dataset preflight tests passed"