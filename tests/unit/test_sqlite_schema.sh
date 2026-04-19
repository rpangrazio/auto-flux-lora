#!/usr/bin/env bash
# ============================================
# Unit Tests: SQLite Schema Operations
# ============================================

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PATH="/tmp/test_training.db"

rm -f "${DB_PATH}"

init_database() {
    sqlite3 "${DB_PATH}" "$(cat <<'EOF'
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
CREATE INDEX IF NOT EXISTS idx_events_job_id ON events(job_id);
EOF
)"
}

test_insert_run() {
    init_database
    sqlite3 "${DB_PATH}" "INSERT INTO runs (job_id, config_hash, config_json) VALUES ('test-job-1', 'abc123', '{}');"
    local count
    count=$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM runs WHERE job_id='test-job-1';")
    [[ "${count}" -eq 1 ]] && echo "PASS: inserted run"
}

test_query_runs_by_status() {
    init_database
    sqlite3 "${DB_PATH}" "INSERT INTO runs (job_id, config_hash, config_json, status) VALUES ('test-job-2', 'def456', '{}', 'QUEUED');"
    local status
    status=$(sqlite3 "${DB_PATH}" "SELECT status FROM runs WHERE job_id='test-job-2';")
    [[ "${status}" == "QUEUED" ]] && echo "PASS: queried run by status"
}

test_insert_event() {
    init_database
    sqlite3 "${DB_PATH}" "INSERT INTO runs (job_id, config_hash, config_json) VALUES ('test-job-3', 'ghi789', '{}');"
    sqlite3 "${DB_PATH}" "INSERT INTO events (job_id, event_type, message) VALUES ('test-job-3', 'INFO', 'Test event');"
    local count
    count=$(sqlite3 "${DB_PATH}" "SELECT COUNT(*) FROM events WHERE job_id='test-job-3';")
    [[ "${count}" -eq 1 ]] && echo "PASS: inserted event"
}

test_insert_run
test_query_runs_by_status
test_insert_event

rm -f "${DB_PATH}"

echo "All SQLite schema tests passed"