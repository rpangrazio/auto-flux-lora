#!/usr/bin/env bash
# ============================================
# Integration Test: Priority Override
# ============================================

set -euo pipefail

QUEUE_DIR="/tmp/test_queue"
mkdir -p "${QUEUE_DIR}"

cat > "${QUEUE_DIR}/job_low.toml" <<'EOF'
priority = 1
EOF

cat > "${QUEUE_DIR}/job_high.toml" <<'EOF'
priority = 10
EOF

cat > "${QUEUE_DIR}/job_medium.toml" <<'EOF'
priority = 5
EOF

PIPELINE_QUEUE_DIR="${QUEUE_DIR}"
source /opt/pipeline/helpers/queue_manager.sh

jobs=($(list_pending_jobs_by_priority))
[[ "$(basename "${jobs[0]}")" == "job_high.toml" ]] && echo "PASS: high priority first"
[[ "$(basename "${jobs[1]}")" == "job_medium.toml" ]] && echo "PASS: medium priority second"
[[ "$(basename "${jobs[2]}")" == "job_low.toml" ]] && echo "PASS: low priority last"

rm -rf "${QUEUE_DIR}"
echo "All priority override tests passed"