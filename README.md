# Auto-Flux LoRA Implementation

Auto-Flux LoRA (Adaptive Flux Low-Rank Adaptation) is a framework for efficient LoRA fine-tuning of large generative models using flux-aware adaptation techniques. It focuses on low-VRAM, reproducible training runs and local, containerized operation for air-gapped and on-prem workflows.

Key goals:
- Autonomous, file-queued LoRA training with deterministic reproducibility.
- Minimal VRAM footprint through targeted low-rank updates and gradient checkpointing.
- Per-run auditability via SQLite run metadata and per-job logs.

---

## Quick Start
These quick steps get a working local single-node containerized environment. For full operational details see `docs/usage.md`.

Prerequisites
- Linux x86_64 host with Docker Engine 24.x+ and NVIDIA Container Toolkit (nvidia-docker)
- NVIDIA drivers 535+ and a CUDA 12.x capable GPU (≥16 GB VRAM recommended)
- Python 3.9+ for local dev tasks

Build the container image (optional if using a published image):

```bash
docker build -t lora-pipeline:1.0.0 .
```

Create persistent storage and start via Docker Compose:

```bash
mkdir -p /srv/lora-pipeline/data/{queue,output,logs,datasets,configs}
chown -R $(id -u):$(id -g) /srv/lora-pipeline/data

# Start stack (expects docker-compose.yml in repo root)
docker compose up -d
```

Submit a job by copying a TOML/YAML config file into the queue directory:

```bash
cp sample/config/example_training.toml /srv/lora-pipeline/data/queue/
```

Run modes
- dev: local development/testing (use virtualenv/conda; run train scripts directly)
- sim: compose-driven, containerized run for E2E smoke tests
- prod: single-node container with host-mounted `/data` volume and restart policy

---

## Installation (developer)
For development and local experiments, follow these steps:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
# editable install for local code changes
pip install -e .
```

Use `accelerate launch` for multi-GPU or mixed-precision training when available.

---

## Usage examples
Basic inference test (after producing an adapter):

```bash
python scripts/inference_test.py --model_path ./adapters/best_adapter --base_model_name <base-model-path-or-id>
```

Start a single app locally (development):

```bash
cd apps/<service>
pip install -r requirements.txt
python -m <service>.main
```

Full containerized integration (recommended for deterministic runs):

```bash
docker compose up --build
# follow logs
docker logs -f lora-pipeline
```

Health & status
- View orchestrator logs: `docker logs -f lora-pipeline`
- Query recent runs: `sqlite3 /srv/lora-pipeline/data/logs/training.db "SELECT job_id,status,duration_s FROM runs ORDER BY start_time DESC LIMIT 10;"`

---

## Documentation
See the `docs/` folder for:
- `docs/usage.md` — complete operational guide and examples
- `PRD.md` — product requirements (design and acceptance tests)
- `PLAN.md` — implementation backlog and verification tasks

---

## Contributing
- Follow the plan in `PLAN.md` and ensure PRD acceptance tests pass before merging.
- Write tests for any new functional behavior and add documentation updates for user-visible changes.

---

## License & Attribution
See `LICENSE` (if present) or consult repository owner for licensing details.

*Last updated: 2026-06-08 (OpenClaw Assistant)*
