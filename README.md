# Flux.1 LoRA Training Pipeline

Autonomous GPU-accelerated LoRA fine-tuning orchestrator for Flux.1 models.

This repository provides a containerized, file-driven pipeline that runs LoRA fine-tuning jobs autonomously from job submission through trained adapter output. It is designed for local, air-gapped operation on a single GPU host (e.g., NVIDIA Tesla P40) using Docker + NVIDIA Container Toolkit.

Key capabilities

- Fully autonomous job queue (file-based) with control files for pause/cancel/lock
- Deterministic reproducibility when given identical inputs (config, dataset, base model, seed)
- Structured SQLite audit log + per-job plaintext logs
- GPU detection and auto mixed-precision (fp16/bf16) selection
- OOM recovery with automatic batch-size reduction and retry
- Healthcheck and stale-lock recovery for robust unattended operation

Requirements

- Docker Engine 24.x+
- NVIDIA drivers 535+ and NVIDIA Container Toolkit (nvidia-docker)
- Host with sufficient CPU/RAM and at least one CUDA-compatible GPU (24 GB VRAM recommended for Flux.1)

Quick start (developer/local)

1. Build the container image (optional if using a published image):

```bash
docker build -t lora-pipeline:1.0.0 .
```

2. Prepare persistent storage on the host (example):

```bash
mkdir -p /srv/lora-pipeline/data/{queue,output,logs,datasets,configs}
chown -R $(id -u):$(id -g) /srv/lora-pipeline/data
```

3. Configure environment and deploy the container stack (recommended via docker-compose):

```bash
export PIPELINE_QUEUE_DIR=/srv/lora-pipeline/data/queue
export PIPELINE_OUTPUT_DIR=/srv/lora-pipeline/data/output
export PIPELINE_LOG_DIR=/srv/lora-pipeline/data/logs

docker compose up -d
```

4. Submit a job by copying a TOML (or YAML) config into the queue directory:

```bash
cp sample/config/example_training.toml /srv/lora-pipeline/data/queue/
```

The orchestrator polls the queue and will pick up jobs automatically. Typical lifecycle: QUEUED → PREPARING → TRAINING → COMPLETING → DONE.

Configuration example

A representative TOML configuration is provided in `sample/config/example_training.toml`. Key sections include `[job]`, `[model]`, `[dataset]`, `[training]`, and `[output]`.

Control files (sentinels)

- `.lock` — prevents concurrent orchestrator instances (heartbeat-updated)
- `.pause` — suspend dequeueing of new jobs (current job completes)
- `.cancel` — request graceful termination of the currently running job
- `.done` — written by the orchestrator on successful job completion with summary metadata

Usage & verification

- Follow real-time logs: `docker logs -f lora-pipeline`
- Query recent runs (example):

```bash
sqlite3 /srv/lora-pipeline/data/logs/training.db "SELECT job_id,status,duration_s FROM runs ORDER BY start_time DESC LIMIT 10;"
```

- Container health: `docker inspect --format='{{.State.Health.Status}}' lora-pipeline`

Testing

Unit and integration test shells are available under `tests/`.

```bash
# Unit tests
bash tests/unit/test_config_parser.sh
bash tests/unit/test_dataset_preflight.sh

# Integration/E2E smoke
bash tests/integration/test_e2e_smoke.sh
```

Environment variables (common)

- `PIPELINE_QUEUE_DIR` (default `/data/queue`)
- `PIPELINE_OUTPUT_DIR` (default `/data/output`)
- `PIPELINE_LOG_DIR` (default `/data/logs`)
- `PIPELINE_POLL_INTERVAL` (default `30` seconds)
- `PIPELINE_MAX_CONCURRENT` (default `1`)
- `NVIDIA_VISIBLE_DEVICES` (default `all`)
- `CUBLAS_WORKSPACE_CONFIG` (should be set for deterministic CUDA behavior, e.g., `:4096:8`)

Storage layout

- `/data/datasets/` — datasets (images + captions)
- `/data/configs/` — reference configuration copies
- `/data/output/` — trained adapters (`.safetensors`), checkpoints, sample images
- `/data/logs/` — SQLite DB (`training.db`) + per-job logs
- `/data/queue/` — incoming job configuration files

Operational notes

- Pre-download base Flux.1 model weights to `/data/models/` for air-gap operation.
- Ensure host has appropriate GPU drivers and the NVIDIA Container Toolkit installed before running.
- Use `PIPELINE_MAX_CONCURRENT=1` for single-GPU hosts; raising concurrency requires careful resource planning.

Project status (2026-06-06)

- Core orchestrator, queueing, logging, and basic resilience logic implemented.
- Some PRD items require additional verification slices (see `PLAN.md`).
- Documentation updated (README + docs/usage.md).

Docs and references

- `PRD.md` — Product Requirements Document (authoritative requirements)
- `PLAN.md` — Implementation plan and queued tasks
- `CHANGELOG.md` — Project changelog and verification notes
- `docs/usage.md` — Detailed usage guide and troubleshooting (this repo)

Last updated: 2026-06-06 12:18 CDT (OpenClaw Assistant)

Documentation status: README.md, CHANGELOG.md, and docs/usage.md were reviewed and synchronized on 2026-06-06 12:18 CDT.
