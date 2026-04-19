#!/usr/bin/env bash
# ============================================
# Unit Tests: Config Parser
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIPELINE_DIR="/opt/pipeline"

source "${PIPELINE_DIR}/helpers/config_parser.sh"
source "${PIPELINE_DIR}/helpers/utils.sh"

test_parse_toml_value() {
    local test_file="/tmp/test_config.toml"
    cat > "${test_file}" <<'EOF'
model_name_or_path = "/data/models/flux1-dev"
dataset_path = "/data/datasets/test"
network_rank = 32
learning_rate = 1e-4
EOF
    local value
    value=$(parse_config_value "${test_file}" "model_name_or_path")
    assertEquals "/data/models/flux1-dev" "${value}"
    rm -f "${test_file}"
}

test_parse_yaml_value() {
    local test_file="/tmp/test_config.yaml"
    cat > "${test_file}" <<'EOF'
model_name_or_path: "/data/models/flux1-dev"
dataset_path: "/data/datasets/test"
network_rank: 32
EOF
    local value
    value=$(parse_config_value "${test_file}" "network_rank")
    assertEquals "32" "${value}"
    rm -f "${test_file}"
}

test_fallback_value() {
    local value
    value=$(parse_config_value "/nonexistent.toml" "missing_key" "default_value")
    assertEquals "default_value" "${value}"
}

test_compute_config_hash() {
    local test_file="/tmp/hash_test.toml"
    echo "test_content" > "${test_file}"
    local hash
    hash=$(compute_config_hash "${test_file}")
    [[ -n "${hash}" ]]
    [[ ${#hash} -eq 64 ]]
    rm -f "${test_file}"
}

assertEquals() {
    local expected="$1"
    local actual="$2"
    if [[ "${expected}" != "${actual}" ]]; then
        echo "FAIL: expected='${expected}', actual='${actual}'"
        return 1
    fi
    echo "PASS"
    return 0
}

test_parse_toml_value
test_parse_yaml_value
test_fallback_value
test_compute_config_hash

echo "All config parser tests passed"