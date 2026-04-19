#!/usr/bin/env bash
# ============================================
# Database Manager Helper
# Flux.1 LoRA Training Pipeline
# ============================================

LOG_DIR="${PIPELINE_LOG_DIR:-/data/logs}"
DB_PATH="${LOG_DIR}/training.db"

init_database() {
    if [[ ! -f "${DB_PATH}" ]]; then
        log_info "Initializing database: ${DB_PATH}"
        sqlite3 "${DB_PATH}" "$(get_schema)"
        sqlite3 "${DB_PATH}" "PRAGMA journal_mode=WAL;"
        log_info "Database initialized with WAL mode"
    fi
}

get_schema() {
    cat <<'EOF'
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS runs (
    job_id          TEXT PRIMARY KEY,
    config_hash     TEXT NOT NULL,
    config_json     TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'QUEUED',
    priority        INTEGER DEFAULT 0,
    start_time      TEXT,
    end_time        TEXT,
    duration_s      REAL,
    exit_code       INTEGER,
    error_message   TEXT,
    output_path     TEXT,
    output_hash     TEXT,
    retry_count     INTEGER DEFAULT 0,
    batch_size_used INTEGER,
    gpu_name        TEXT,
    gpu_vram_mb     INTEGER,
    avg_gpu_util    REAL,
    max_gpu_util    REAL,
    avg_vram_mb     REAL,
    max_vram_mb     REAL,
    created_at      TEXT DEFAULT (datetime('now')),
    updated_at      TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS metrics (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          TEXT NOT NULL REFERENCES runs(job_id),
    step            INTEGER NOT NULL,
    epoch           REAL,
    loss            REAL,
    learning_rate   REAL,
    grad_norm       REAL,
    vram_mb         REAL,
    gpu_temp_c      REAL,
    timestamp       TEXT DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          TEXT REFERENCES runs(job_id),
    event_type      TEXT NOT NULL,
    message         TEXT NOT NULL,
    timestamp       TEXT DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_runs_status ON runs(status);
CREATE INDEX IF NOT EXISTS idx_runs_start_time ON runs(start_time);
CREATE INDEX IF NOT EXISTS idx_metrics_job_id ON metrics(job_id);
CREATE INDEX IF NOT EXISTS idx_metrics_step ON metrics(job_id, step);
CREATE INDEX IF NOT EXISTS idx_events_job_id ON events(job_id);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
EOF
}

insert_run() {
    local job_id="$1"
    local config_hash="$2"
    local config_json="$3"
    local priority="${4:-0}"
    sqlite3 "${DB_PATH}" \
        "INSERT INTO runs (job_id, config_hash, config_json, status, priority, start_time)
         VALUES ('${job_id}', '${config_hash}', '${config_json}', 'QUEUED', ${priority}, datetime('now'));"
}

transition_state() {
    local job_id="$1"
    local from_status="$2"
    local to_status="$3"
    sqlite3 "${DB_PATH}" \
        "UPDATE runs SET status='${to_status}', updated_at=datetime('now')
         WHERE job_id='${job_id}' AND status='${from_status}';"
    log_info "Job ${job_id}: ${from_status} -> ${to_status}"
}

log_event() {
    local event_type="$1"
    local message="$2"
    local job_id="${3:-}"
    if [[ -n "${job_id}" ]]; then
        sqlite3 "${DB_PATH}" \
            "INSERT INTO events (job_id, event_type, message) VALUES ('${job_id}', '${event_type}', '${message}');"
    else
        sqlite3 "${DB_PATH}" \
            "INSERT INTO events (event_type, message) VALUES ('${event_type}', '${message}');"
    fi
}

get_job_duration() {
    local job_id="$1"
    local duration
    duration=$(sqlite3 "${DB_PATH}" \
        "SELECT duration_s FROM runs WHERE job_id='${job_id}';" 2>/dev/null || echo "0")
    echo "${duration:-0}"
}