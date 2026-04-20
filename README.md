# Flux.1 LoRA Training Pipeline

**Autonomous GPU-Accelerated LoRA Fine-Tuning for Flux.1**

A production-ready, containerized training orchestrator for Flux.1 LoRA fine-tuning. Runs fully autonomous from job submission to trained adapter output with deterministic reproducibility, structured SQLite logging, and file-based queue management.

## Features

- **Fully Autonomous**: File-based queue and control mechanisms require zero human intervention after job submission
- **Deterministic Reproducibility**: Identical inputs produce bit-for-bit identical outputs; all parameters snapshotted per run
- **Production Auditability**: Structured SQLite database with full parameter snapshots, timestamps, and resource metrics
- **GPU Auto-Detection**: Automatic mixed-precision selection (fp16 on Pascal, bf16 on Ampere+)
- **Resilient Operation**: OOM recovery with automatic batch-size reduction, graceful shutdown, stale lock detection
- **Air-Gap Compatible**: No network access required during training

## Architecture

```
auto-flux-lora/
├── Dockerfile              # Container image definition
├── docker-compose.yml     # Deployment configuration
├── src/
│   ├── orchestrator.sh    # Main entry point and control loop
│   ├── healthcheck.sh     # Docker health check
│   └── helpers/
│       ├── config_parser.sh   # TOML/YAML parsing
│       ├── queue_manager.sh    # Job queue operations
│       ├── db_manager.sh       # SQLite operations
│       ├── gpu_monitor.sh      # GPU detection and monitoring
│       ├── control_files.sh    # Sentinel file handling
│       └── utils.sh            # Shared utilities
├── tests/
│   ├── unit/              # Unit tests
│   ├── integration/       # Integration tests
│   └── stress/            # Stress tests
├── scripts/               # Utility scripts
├── sample/config/         # Sample configurations
└── docs/diagrams/         # Architecture diagrams
```

## Quick Start

### 1. Build Container

```bash
docker build -t lora-pipeline:1.0.0 .
```

### 2. Configure Storage

```bash
./scripts/setup_storage.sh /srv/lora-pipeline/data
```

### 3. Deploy

```bash
docker compose up -d
```

### 4. Submit a Job

```bash
cp my_training_config.toml /srv/lora-pipeline/data/queue/
```

The orchestrator polls the queue every 30 seconds. When a job is detected, it transitions through states: `QUEUED` → `PREPARING` → `TRAINING` → `COMPLETING` → `DONE`.

## Configuration

```toml
[job]
priority = 0
retry_on_oom = true
max_retries = 2

[model]
model_name_or_path = "/data/models/flux1-dev"
output_dir = "/data/output/"

[dataset]
dataset_path = "/data/datasets/my_dataset"

[training]
network_rank = 32
network_alpha = 16.0
learning_rate = 1e-4
optimizer = "adamw8bit"
lr_scheduler = "cosine"
batch_size = 1
max_train_epochs = 20
resolution = 1024
mixed_precision = "auto"
seed = 42
gradient_checkpointing = true

[output]
save_every_n_steps = 500
sample_every_n_steps = 250
sample_prompts = [
    "a photo of a person",
    "a portrait of a person"
]
```

## Control Files

| File | Purpose |
|------|---------|
| `.pause` | Suspend job dequeue (running job completes) |
| `.cancel` | Graceful SIGTERM → SIGKILL on running job |
| `.lock` | Prevents concurrent orchestrator instances |
| `.done` | Written on successful completion |

## Monitoring

```bash
# Real-time logs
docker logs -f lora-pipeline

# Job history
sqlite3 /srv/lora-pipeline/data/logs/training.db \
  "SELECT job_id, status, duration_s FROM runs ORDER BY start_time DESC LIMIT 10;"

# Container health
docker inspect --format='{{.State.Health.Status}}' lora-pipeline
```

## Testing

```bash
# Unit tests
bash tests/unit/test_config_parser.sh
bash tests/unit/test_dataset_preflight.sh
bash tests/unit/test_sqlite_schema.sh
bash tests/unit/test_control_files.sh

# Integration tests
bash tests/integration/test_e2e_smoke.sh
bash tests/integration/test_queue_processing.sh
bash tests/integration/test_priority_override.sh

# Stress tests
bash tests/stress/test_oom_recovery.sh
bash tests/stress/test_stale_lock_recovery.sh
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PIPELINE_QUEUE_DIR` | `/data/queue` | Queue directory |
| `PIPELINE_OUTPUT_DIR` | `/data/output` | Output directory |
| `PIPELINE_LOG_DIR` | `/data/logs` | Log directory |
| `PIPELINE_POLL_INTERVAL` | `30` | Queue polling interval (seconds) |
| `PIPELINE_MAX_CONCURRENT` | `1` | Max concurrent jobs |
| `NVIDIA_VISIBLE_DEVICES` | `all` | GPU visibility |
| `CUBLAS_WORKSPACE_CONFIG` | `:4096:8` | Deterministic mode |

## Storage Layout

| Path | Purpose |
|------|---------|
| `/data/datasets/` | Training datasets (images + captions) |
| `/data/configs/` | Reference configuration copies |
| `/data/output/` | Trained adapters (.safetensors), checkpoints |
| `/data/logs/` | SQLite database + plaintext logs |
| `/data/queue/` | Incoming job configuration files |

## Project Status

**Complete** — All PRD requirements satisfied and verified against PRD v1.0 (April 2026).
**Verified** — PRD verification complete (2026-04-19), all 24 functional requirements, 6 non-functional requirements, Dockerfile spec, orchestrator design, and SQLite schema verified as SATISFIED.
**Execution State** — Plan reviewed on 2026-04-20 with no remaining tasks; `.DONE` created at repository root.

All features from v1.0 release are implemented:
- Environment capture at startup
- GPU compute capability-based precision selection
- Dataset validation with caption pairing and corrupt image detection
- Image preprocessing with resize, crop, and bucketing
- Training subprocess isolation with `exec`
- VRAM monitoring during training
- Sample image generation with Flux.1-dev pipeline

## Requirements

- Docker Engine 24.x+
- NVIDIA drivers 535+
- NVIDIA Container Toolkit (nvidia-docker2)
- NVIDIA Tesla P40 or equivalent GPU (24GB VRAM recommended)
- CUDA 12.x

## Project Info

- **Version**: 1.0.0
- **Based on**: PRD v1.0 — April 2026
- **Target GPU**: NVIDIA Tesla P40 (24GB, Compute 6.1)
