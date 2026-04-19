#!/usr/bin/env bash
# ============================================
# Config Parser Helper
# Flux.1 LoRA Training Pipeline
# ============================================

parse_config_value() {
    local config_file="$1"
    local key="$2"
    local fallback="${3:-}"
    if [[ ! -f "${config_file}" ]]; then
        echo "${fallback}"
        return 1
    fi
    local value
    if [[ "${config_file}" == *.toml ]]; then
        value=$(grep -E "^${key}\s*=" "${config_file}" | sed 's/^[^=]*=[ ]*//' | tr -d '"' | tr -d "'" | xargs)
    elif [[ "${config_file}" == *.yaml || "${config_file}" == *.yml ]]; then
        value=$(grep -E "^\s*${key}\s*:" "${config_file}" | sed 's/^[^:]*:[ ]*//' | xargs)
    fi
    echo "${value:-${fallback}}"
}

parse_config_section() {
    local config_file="$1"
    local section="$2"
    if [[ "${config_file}" == *.toml ]]; then
        awk -v section="${section}" '
            /^\[/ {
                gsub(/^\[|\]$/, "", $0)
                current=$0
            }
            current == section && /^[^#]/ && /=/{ print }
        ' "${config_file}"
    fi
}

validate_config_required() {
    local config_file="$1"
    local required_fields=("model_name_or_path" "dataset_path")
    for field in "${required_fields[@]}"; do
        local value
        value=$(parse_config_value "${config_file}" "${field}")
        if [[ -z "${value}" ]]; then
            log_error "Missing required field: ${field}"
            return 1
        fi
    done
    return 0
}

get_job_id() {
    local config_file="$1"
    local job_id
    job_id=$(parse_config_value "${config_file}" "job_id")
    if [[ -z "${job_id}" ]]; then
        job_id=$(basename "${config_file}" | sed 's/\.[^.]*$//')
    fi
    echo "${job_id}"
}

compute_config_hash() {
    local config_file="$1"
    sha256sum "${config_file}" | awk '{print $1}'
}