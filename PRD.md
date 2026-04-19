# Product Requirements Document

**Autonomous GPU-Accelerated LoRA Training Pipeline — Containerized Flux.1 LoRA Fine-Tuning Orchestrator**

| Field | Value |
|-------|-------|
| Version | 1.0 |
| Date | April 2026 |
| Author | Robert Pangrazio |
| Classification | Internal Engineering |
| Status | Draft |

## Table of Contents

1. Executive Summary
2. Problem Statement
3. Goals and Objectives
4. Target Users and Personas
5. System Architecture Overview
6. Functional Requirements
6.1 Job Submission and Queue Management
6.2 Training Execution
6.3 Dataset Management
6.4 Control-File Mechanisms
6.5 Logging and Auditability
6.6 GPU and Resource Management
7. Non-Functional Requirements
8. Configuration Schema
9. Dockerfile Specification
10. Orchestrator Design
11. Testing and Validation Plan
12. Deployment and Operations
13. Milestones and Timeline
14. Risks and Mitigations
15. Open Questions
16. Appendix

## 1. Executive Summary

This document specifies the product requirements for an **Autonomous GPU-Accelerated LoRA Training Pipeline** — a fully containerized Docker-based system for running Low-Rank Adaptation (LoRA) fine-tuning jobs on Black Forest Labs' Flux.1 (Flux.dev) generative image model. The pipeline is designed to operate without human intervention after job submission, executing the complete training lifecycle from dataset ingestion through trained adapter output.

The system targets deployment on a dedicated 72-core host ("Adler") equipped with an NVIDIA Tesla P40 GPU (24 GB VRAM), operating 24/7 as a local training appliance. All operations are containerized via Docker with NVIDIA Container Toolkit GPU passthrough, ensuring environment isolation and deployment portability.

### Key Value Propositions

- **Full Autonomy:** Zero human intervention from job submission to trained adapter output. File-based queue and control mechanisms enable hands-off operation.
- **Deterministic Reproducibility:** Identical inputs (config + dataset + base model + seed) produce bit-for-bit identical outputs. All parameters captured and snapshotted per run.
- **Production-Grade Auditability:** Every training run logged to a structured SQLite database with full parameter snapshots, timestamps, resource utilization metrics, and outcome status.
- **Local-First, Air-Gap Compatible:** No network access required during training. No telemetry, no external dependencies at runtime.

## 2. Problem Statement

Current LoRA training workflows for Flux.1 models present several operational challenges that this pipeline is designed to address:

**Manual Setup and Monitoring:** Existing training workflows require significant manual intervention — configuring environments, launching training scripts, monitoring GPU utilization, and manually collecting outputs. This creates a bottleneck when running multiple sequential training experiments.

**Lack of Reproducibility:** Ad-hoc training runs executed with inconsistent environments, unversioned configurations, and uncontrolled random seeds produce results that cannot be reliably reproduced or compared. There is no systematic mechanism to snapshot the full parameter state of a given run.

**No Centralized Auditability:** Training history is scattered across terminal logs, file timestamps, and operator memory. There is no structured audit trail linking a trained adapter to the exact configuration, dataset, and environment that produced it.

**Suboptimal GPU Utilization:** Without automated scheduling and queue management, the Tesla P40 GPU sits idle between manual runs. There is no mechanism to automatically pick up the next job when a run completes or fails.

**Inadequacy of Existing Solutions:** Cloud-based training services (Replicate, RunPod) introduce latency, cost, and data-sovereignty concerns. GUI-based local tools (Kohya-ss GUI) require interactive operation and do not support headless, autonomous execution. Neither approach meets the requirements for a local-first, air-gapped, fully autonomous training appliance.

## 3. Goals and Objectives

| ID | Goal | Description |
|----|------|-------------|
| G1 | Full Autonomy | End-to-end LoRA training — from dataset ingestion to trained adapter output — with zero human intervention after initial job submission. The orchestrator handles queue management, execution, error recovery, and output collection autonomously. |
| G2 | Deterministic Reproducibility | Identical inputs (configuration file + dataset + base model weights + random seed) must always produce bit-for-bit identical output adapters. All sources of non-determinism (random seeds, CUDA operations, data loading order) are controlled and documented. |
| G3 | Production-Grade Auditability | Every training run is logged to a structured SQLite database capturing: job ID, configuration hash (SHA-256), full parameter snapshot, start/end timestamps, exit code, GPU utilization summary, and output file paths. Logs are queryable without interactive container access. |
| G4 | Efficient GPU Utilization | Automated FIFO job queue with optional priority scheduling maximizes Tesla P40 throughput. GPU idle time between jobs is minimized to the orchestrator polling interval (default 30s). |
| G5 | Resilient Operation | Graceful handling of training process crashes, out-of-memory (OOM) conditions, GPU driver resets, and container restarts. Automatic retry with configurable backoff. Notification on terminal failure states. |

## 4. Target Users and Personas

### 4.1 Primary: ML Engineering Practitioner

An engineering practitioner running local Flux.1 LoRA fine-tuning for character consistency, style transfer, and concept injection in generative art workflows. This user submits training jobs via configuration files, reviews results through output adapters and sample images, and queries training history through SQLite. They are comfortable with terminal-based workflows and expect reproducible, auditable results.

**Key expectations:**
- Submit a job by dropping a config file into a directory — nothing more.
- Return hours later to find the trained adapter, sample images, and a full log waiting in the output directory.
- Compare training runs across parameter variations using structured log queries.

### 4.2 Secondary: DevOps / MLOps Engineer

An infrastructure engineer managing containerized ML training workloads across one or more GPU hosts. This user is responsible for container deployment, volume management, monitoring, and upgrades. They expect standard Docker/OCI conventions, health checks, structured logs, and a clean upgrade path.

**Key expectations:**
- Deploy and upgrade via `docker compose` with tagged image versions.
- Monitor operational status via log files and SQLite queries — no interactive shell required.
- Integrate with existing backup, monitoring, and alerting infrastructure.

### Assumed Knowledge

Both personas are assumed to have working familiarity with: Docker and container lifecycle management, NVIDIA GPU tooling (nvidia-docker, CUDA toolkit), LoRA training concepts (rank, alpha, learning rate schedules), and Flux.1 model architecture fundamentals.

## 5. System Architecture Overview

The pipeline is composed of four primary subsystems running within a single Docker container with GPU passthrough:

### 5.1 Runtime Environment

| Component | Specification |
|-----------|---------------|
| Container Runtime | Docker Engine 24.x+ with NVIDIA Container Toolkit (nvidia-docker2) for GPU passthrough |
| Base Image | nvidia/cuda:12.4.1-runtime-ubuntu22.04 |
| Python Runtime | Python 3.10+ with pip-managed dependencies |
| Training Backend | ai-toolkit or kohya-ss sd-scripts adapted for Flux.1 LoRA training (see Section 15, Open Questions) |
| Target GPU | NVIDIA Tesla P40, 24 GB VRAM, CUDA Compute Capability 6.1 |
| Host System | "Adler" — 72-core CPU, dedicated 24/7 training host |

### 5.2 Orchestrator

A Bash-based orchestrator script (`orchestrator.sh`) serves as the container entrypoint and primary control loop. It manages the job lifecycle through file-based control mechanisms (`.done`, `.pause`, `.lock`, `.cancel`), polls the queue directory for new jobs, and integrates with SQLite for structured logging. The orchestrator runs as a single-loop process with signal handling for graceful shutdown.

### 5.3 Logging Subsystem

Dual-layer logging combines a **SQLite database** for structured, queryable run metadata with **plaintext log files** for real-time stdout/stderr capture. The SQLite database operates in WAL (Write-Ahead Logging) mode for concurrent read access during active training.

### 5.4 Storage Layout

All persistent state resides on a single bind-mounted volume (`/data`) organized into the following directory structure:

| Path | Purpose | Persistence |
|------|---------|-------------|
| /data/datasets/ | Training datasets — image files with matching `.txt` caption files | Permanent |
| /data/configs/ | Per-job TOML/YAML configuration files (reference copies) | Permanent |
| /data/output/ | Trained LoRA adapters (`.safetensors`), checkpoints, sample images | Permanent |
| /data/logs/ | SQLite database (`training.db`) + per-job plaintext log files | Permanent |
| /data/queue/ | Job queue directory — incoming config files for processing | Transient |

## 6. Functional Requirements

### 6.1 Job Submission and Queue Management

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-01 | Jobs shall be submitted by placing a configuration file (TOML or YAML format) into the `/data/queue/` directory. No other submission mechanism is required. | Must |
| FR-02 | The orchestrator shall poll the queue directory at a configurable interval (default: 30 seconds) for new configuration files. | Must |
| FR-03 | Jobs shall be processed in FIFO order by file modification timestamp. An optional `priority` field in the configuration file overrides FIFO ordering (higher priority value = processed first). | Must |
| FR-04 | The maximum number of concurrently executing jobs shall be configurable via environment variable (default: 1 for single-GPU hosts). | Must |

### 6.2 Training Execution

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-05 | Each training job shall execute in an isolated subprocess with full environment capture (environment variables, Python package versions, CUDA version, GPU driver version) logged at startup. | Must |
| FR-06 | The pipeline shall support Flux.1 LoRA training with the following configurable parameters: network rank, network alpha, learning rate, optimizer type, learning rate scheduler, batch size, maximum epochs, training resolution, and network dimensions. | Must |
| FR-07 | Automatic mixed-precision mode selection (fp16 or bf16) shall be performed based on GPU capability detection at container startup. Tesla P40 (Compute 6.1) shall default to fp16; Ampere+ GPUs shall default to bf16. | Must |
| FR-08 | Training checkpoints shall be saved at configurable step intervals. Optional best-model selection by validation loss retains only the checkpoint with lowest recorded loss. | Must |
| FR-09 | Sample images shall be generated at configurable step intervals during training using user-defined prompts, enabling visual progress monitoring without interactive access. | Should |

### 6.3 Dataset Management

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-10 | The pipeline shall auto-detect dataset format: a directory of image files (PNG, JPG, WEBP) with matching `.txt` caption files sharing the same base filename. | Must |
| FR-11 | A pre-flight validation step shall verify: all images have corresponding caption files, image dimensions meet minimum resolution thresholds, image files are valid/uncorrupted, and the dataset meets a configurable minimum size (default: 3 images). | Must |
| FR-12 | Optional automatic image preprocessing shall support: resize to target resolution, center-crop, and aspect-ratio-preserving bucketing to minimize padding waste during training. | Should |

### 6.4 Control-File Mechanisms

The orchestrator uses sentinel files in the working directory to manage job lifecycle without requiring interactive access to the running container:

| ID | File | Behavior | Priority |
|----|------|----------|----------|
| FR-13 | `.pause` | When detected, the orchestrator suspends job processing. The currently running job completes normally, but no new jobs are dequeued until the `.pause` file is removed. | Must |
| FR-14 | `.cancel` | The currently running training job receives a graceful SIGTERM signal. If the process does not exit within a configurable timeout (default: 60s), SIGKILL is sent. Partial outputs are preserved. | Must |
| FR-15 | `.done` | Written by the orchestrator upon successful job completion. Contains summary metadata: job ID, duration, output path, final loss value, and exit code. | Must |
| FR-16 | `.lock` | Prevents concurrent orchestrator instances on the same volume. Written at startup with PID and timestamp. Stale lock detection triggers after a configurable heartbeat timeout (default: 300s). | Must |

### 6.5 Logging and Auditability

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-17 | Every training run shall be logged to the SQLite database with the following fields: job ID (UUID v4), configuration hash (SHA-256 of normalized config), all training parameters (as JSON blob), start timestamp, end timestamp, exit code, GPU utilization summary (avg/max VRAM, avg/max GPU%), and output file paths. | Must |
| FR-18 | Real-time stdout and stderr from each training process shall be captured to per-job plaintext log files at `/data/logs/{job_id}.log`. | Must |
| FR-19 | A full copy of the configuration file shall be saved alongside the output adapter in the job output directory, ensuring complete reproducibility without access to the original queue file. | Must |
| FR-20 | Optional notification on job completion or failure via one or more channels: stdout message, email (SMTP), or HTTP POST webhook. Channel and endpoint are configurable per-job. | Should |

### 6.6 GPU and Resource Management

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-21 | At container startup, the orchestrator shall detect and report all available NVIDIA GPUs: device name, VRAM capacity, CUDA compute capability, driver version, and CUDA toolkit version. This information is logged to both stdout and the SQLite database. | Must |
| FR-22 | VRAM utilization shall be monitored at configurable intervals (default: 10s) during training. If utilization exceeds a configurable OOM-avoidance threshold (default: 95%), a warning is logged. | Should |
| FR-23 | When a training job fails due to CUDA OOM and `retry_on_oom` is enabled, the orchestrator shall automatically reduce the batch size by half and retry the job, up to `max_retries` attempts. | Should |
| FR-24 | GPU core temperature shall be monitored during training. If temperature exceeds a configurable thermal warning threshold (default: 85°C), a warning is logged. If temperature exceeds the critical threshold (default: 90°C), the current job is paused until temperature drops below the warning threshold. | Could |

## 7. Non-Functional Requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NFR-01 | Reproducibility | Given an identical configuration file, dataset, base model weights, and random seed, the pipeline must produce bit-for-bit identical `.safetensors` output files. Deterministic seeding is enforced across Python, NumPy, PyTorch, and CUDA. CUBLAS workspace configuration is set to deterministic mode. |
| NFR-02 | Portability | The pipeline must run on any Linux host (x86_64) with Docker Engine 24.x+, NVIDIA drivers 535+, and any CUDA 12.x-compatible GPU with ≥16 GB VRAM. No host-side dependencies beyond Docker and NVIDIA drivers are required. |
| NFR-03 | Startup Time | Container cold-start to first training step shall complete in under 120 seconds, excluding base model download time. This includes: container initialization, GPU detection, queue polling, config parsing, dataset validation, and training backend startup. |
| NFR-04 | Fault Tolerance | The orchestrator must survive and recover from: training process crash (non-zero exit), CUDA OOM, GPU driver reset/recovery, and container restart (via Docker restart policy). State is reconstructed from the filesystem and SQLite database on recovery. |
| NFR-05 | Security | No outbound network access is required during training. The container operates in air-gap compatible mode. No telemetry, analytics, or external data transmission of any kind. Model weights, datasets, and outputs remain on the local filesystem. |
| NFR-06 | Observability | All operational state must be queryable via SQLite and log file inspection without requiring interactive access (shell, exec) to the running container. Standard `docker logs` output provides real-time orchestrator status. |

## 8. Configuration Schema

Each training job is defined by a TOML or YAML configuration file. The following table documents all supported parameters, their types, default values, and descriptions:

### 8.1 Required Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| model_name_or_path | string | required | Path to the base Flux.1 model weights directory or Hugging Face model identifier. Must be pre-downloaded for air-gap operation. |
| dataset_path | string | required | Path to the training dataset directory containing image files and matching `.txt` caption files. |

### 8.2 Training Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| output_dir | string | /data/output/{job_id} | Directory for trained adapter output, checkpoints, and sample images. |
| network_rank | int | 32 | LoRA decomposition rank. Higher values increase adapter capacity and VRAM usage. Common values: 16, 32, 64, 128. |
| network_alpha | float | 16.0 | LoRA scaling factor (alpha). Effective scaling = alpha / rank. Typically set to rank or rank/2. |
| learning_rate | float | 1e-4 | Peak learning rate for the optimizer. Flux.1 LoRA training typically uses values in the range 1e-5 to 5e-4. |
| optimizer | string | "adamw8bit" | Optimizer type. Supported: `adamw`, `adamw8bit`, `adafactor`, `prodigy`, `lion8bit`. |
| lr_scheduler | string | "cosine" | Learning rate scheduler. Supported: `cosine`, `constant`, `constant_with_warmup`, `linear`, `polynomial`. |
| batch_size | int | 1 | Training batch size per GPU. Limited by VRAM capacity. Tesla P40 (24 GB) typically supports batch size 1–2 for Flux.1 at 1024px. |
| max_train_epochs | int | 20 | Maximum number of training epochs. Training may terminate earlier if early stopping is configured. |
| resolution | int | 1024 | Training resolution in pixels (square). Flux.1 native resolution is 1024. Lower values reduce VRAM usage. |
| mixed_precision | string | "bf16" | Mixed-precision training mode. `bf16` preferred for Ampere+; auto-detected to `fp16` on Pascal GPUs (Tesla P40). |
| seed | int | 42 | Random seed for deterministic training. Controls Python, NumPy, PyTorch, and CUDA RNG initialization. |
| gradient_checkpointing | bool | true | Enable gradient checkpointing to reduce VRAM usage at the cost of ~20% slower training. Strongly recommended for Tesla P40. |

### 8.3 Output and Monitoring Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| save_every_n_steps | int | 500 | Save a training checkpoint every N steps. Set to 0 to disable intermediate checkpoints. |
| sample_every_n_steps | int | 250 | Generate sample images every N steps using the prompts defined in `sample_prompts`. Set to 0 to disable. |
| sample_prompts | list[str] | optional | List of text prompts used for sample image generation during training. If omitted, sample generation is disabled. |

### 8.4 Orchestrator Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| priority | int | 0 | Job priority for queue ordering. Higher values are processed first. Equal-priority jobs are processed FIFO. |
| retry_on_oom | bool | true | If the job fails with CUDA OOM, automatically retry with halved batch size. |
| max_retries | int | 2 | Maximum number of OOM retry attempts before marking the job as FAILED. |
| notification_webhook | string | optional | HTTP POST endpoint for job completion/failure notifications. Payload includes job ID, status, duration, and output path. |

## 9. Dockerfile Specification

The container image encapsulates the complete training environment. The Dockerfile follows a multi-stage-aware single-stage build optimized for layer caching and minimal image size.

### 9.1 Image Specification

| Layer | Details |
|-------|---------|
| Base Image | nvidia/cuda:12.4.1-runtime-ubuntu22.04 |
| System Packages | python3.10, python3-pip, git, sqlite3, curl, jq |
| Python Dependencies | torch, torchvision, transformers, diffusers, accelerate, safetensors, peft, bitsandbytes, Pillow, toml, pyyaml |
| Training Backend | ai-toolkit (pinned commit hash) or kohya sd-scripts (pinned release tag) |
| Orchestrator | orchestrator.sh + helper scripts copied to /opt/pipeline/ |
| ENTRYPOINT | ["/opt/pipeline/orchestrator.sh"] |
| VOLUME | /data — bind-mounted host directory for all persistent state |

### 9.2 Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| PIPELINE_QUEUE_DIR | /data/queue | Queue directory path |
| PIPELINE_OUTPUT_DIR | /data/output | Output directory path |
| PIPELINE_LOG_DIR | /data/logs | Log directory path |
| PIPELINE_POLL_INTERVAL | 30 | Queue polling interval in seconds |
| PIPELINE_MAX_CONCURRENT | 1 | Maximum concurrent training jobs |
| NVIDIA_VISIBLE_DEVICES | all | GPU device visibility (NVIDIA Container Toolkit) |
| CUBLAS_WORKSPACE_CONFIG | :4096:8 | Deterministic CUBLAS workspace configuration |

### 9.3 Health Check

The container health check verifies orchestrator liveness by checking the heartbeat timestamp in the `.lock` file. If the heartbeat is stale beyond the configured timeout, Docker reports the container as unhealthy.

```
HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
  CMD /opt/pipeline/healthcheck.sh || exit 1
```

## 10. Orchestrator Design

### 10.1 Architecture

The orchestrator is implemented as a single-loop Bash script with modular function structure. It serves as the container's ENTRYPOINT and runs continuously, managing the full job lifecycle from queue polling through execution and completion logging.

### 10.2 Job Lifecycle States

Each job transitions through a defined set of states, tracked in both the SQLite database and the filesystem:

| State | Description | Transition To |
|-------|-------------|---------------|
| QUEUED | Configuration file detected in queue directory, awaiting processing. | PREPARING |
| PREPARING | Config parsed, dataset validated, environment captured, output directory created. | TRAINING, FAILED |
| TRAINING | Training subprocess is actively running. GPU utilization is monitored. | COMPLETING, FAILED, CANCELLED |
| COMPLETING | Training finished. Outputs are being collected, checksums computed, logs finalized. | DONE, FAILED |
| DONE | Job completed successfully. `.done` file written. Notification sent (if configured). | Terminal |
| FAILED | Job terminated with error. May trigger OOM retry if applicable. Notification sent. | QUEUED (retry), Terminal |
| CANCELLED | Job cancelled via `.cancel` control file. Partial outputs preserved. | Terminal |

### 10.3 Signal Handling

The orchestrator traps `SIGTERM` and `SIGINT` for graceful shutdown. Upon receiving either signal:

1. The orchestrator sets an internal shutdown flag preventing new jobs from starting.
2. If a training job is running, it receives `SIGTERM` with a configurable grace period (default: 60s).
3. After the grace period, `SIGKILL` is sent if the process has not exited.
4. The job is marked as `CANCELLED` in the database with partial output paths logged.
5. The `.lock` file is removed and the orchestrator exits cleanly.

### 10.4 Stale Lock Recovery

On startup, if a `.lock` file exists, the orchestrator checks the heartbeat timestamp. If the heartbeat is older than the configured timeout (default: 300 seconds), the lock is considered stale — it is removed and a new lock is acquired. A stale lock event is logged to the database as a warning.

### 10.5 Heartbeat Mechanism

The orchestrator updates the `.lock` file's modification timestamp every polling cycle (default: 30s) using `touch`. This serves as a liveness heartbeat for both stale lock detection and the Docker health check.

## 11. Testing and Validation Plan

### 11.1 Unit Tests

- **Config Parser:** Validate TOML and YAML parsing, type coercion, default value injection, required field enforcement, and invalid value rejection.
- **Dataset Pre-Flight:** Verify image-caption pairing logic, minimum size enforcement, corrupt image detection, and supported format filtering.
- **SQLite Schema:** Validate schema creation, record insertion, query operations, WAL mode configuration, and migration handling.
- **Control-File Logic:** Test detection and handling of each sentinel file type in isolation.

### 11.2 Integration Tests

- **End-to-End Smoke Test:** Execute a complete training run with a minimal 5-image dataset, reduced epochs (2), and low resolution (512px) to verify the full pipeline from job submission to adapter output.
- **Queue Processing:** Submit 3 sequential jobs and verify FIFO processing order, correct state transitions, and per-job isolation.
- **Priority Override:** Submit jobs with varying priority values and verify high-priority jobs are processed first.
- **Notification Delivery:** Verify webhook POST is sent on job completion and failure with correct payload structure.

### 11.3 Stress and Resilience Tests

- **OOM Recovery:** Configure a job with batch_size large enough to trigger CUDA OOM. Verify automatic batch-size reduction and successful retry.
- **Concurrent Submission:** Rapidly submit 10+ jobs while a job is running. Verify queue integrity and correct processing order.
- **Stale Lock Recovery:** Simulate an unclean shutdown (leave stale `.lock` file) and verify automatic recovery on restart.
- **Container Restart:** Issue `docker restart` during active training. Verify orchestrator recovery and correct status of the interrupted job.

### 11.4 Reproducibility Validation

**Critical Test:** Execute two identical training runs (same config, dataset, seed, and base model) on the same hardware. Compare output `.safetensors` files byte-for-byte. Files must be identical. Any divergence indicates a non-determinism bug that must be investigated and resolved before v1.0 release.

## 12. Deployment and Operations

### 12.1 Deployment

The pipeline is deployed via `docker compose` with a single service definition. All persistent state resides on the bind-mounted `/data` volume, enabling container replacement without data loss.

```
docker compose up -d
```

Initial setup requires:
- NVIDIA drivers (535+) and NVIDIA Container Toolkit installed on the host.
- Flux.1 base model weights pre-downloaded to `/data/models/`.
- Directory structure created: `/data/{datasets,configs,output,logs,queue}`.

### 12.2 Monitoring

Operational monitoring is performed without interactive container access:

- **Real-time status:** `docker logs -f lora-pipeline`
- **Job history:** `sqlite3 /data/logs/training.db "SELECT job_id, status, duration_s FROM runs ORDER BY start_time DESC LIMIT 10;"`
- **Active job:** Check for existence and contents of `/data/queue/.lock`
- **Container health:** `docker inspect --format='{{.State.Health.Status}}' lora-pipeline`

### 12.3 Backup Strategy

- **Trained adapters:** Periodic `rsync` of `/data/output/` to backup storage.
- **Training logs:** Periodic `rsync` of `/data/logs/` including the SQLite database.
- **Configurations:** Backed up alongside outputs (config snapshots are saved per-job by FR-19).
- **Datasets:** Assumed to be managed externally; not included in automated backup.

### 12.4 Upgrade Path

Container images are versioned with semantic version tags (e.g., `lora-pipeline:1.0.0`). Upgrades follow a standard pull-and-replace workflow:

```
docker compose pull
docker compose up -d
```

The `/data` volume persists across container replacements. SQLite schema migrations are applied automatically on startup when the database version is older than the container version.

## 13. Milestones and Timeline

| ID | Description | Target | Key Deliverables |
|----|-------------|--------|------------------|
| M1 | Dockerfile + base image validated with GPU passthrough | Week 1 | Working container with `nvidia-smi` output, Python + CUDA verified |
| M2 | Training backend integrated, single manual run succeeds | Week 2 | Successful Flux.1 LoRA training run inside container, output `.safetensors` validated |
| M3 | Orchestrator MVP: queue polling, job execution, SQLite logging | Weeks 3–4 | File-based queue processing, job lifecycle state machine, structured logging to SQLite |
| M4 | Control-file mechanisms (`.pause`, `.cancel`, `.lock`, `.done`) | Week 5 | All sentinel files operational, stale lock detection, graceful cancellation |
| M5 | OOM recovery, retry logic, notification hooks | Week 6 | Automatic batch-size reduction, retry mechanism, webhook notifications |
| M6 | Testing suite complete, reproducibility validated | Week 7 | Unit, integration, stress, and reproducibility tests passing. Bit-identical output confirmed. |
| M7 | Documentation, v1.0 release | Week 8 | README, configuration reference, operational runbook, tagged container image release |

## 14. Risks and Mitigations

| ID | Severity | Risk | Mitigation |
|----|----------|------|------------|
| R1 | High | Tesla P40 lacks native bf16 support | GPU capability auto-detection (FR-07) falls back to fp16 mixed precision on Pascal-architecture GPUs. Default `mixed_precision` config value is overridden at runtime when bf16 is unsupported. |
| R2 | High | Flux.1 model exceeds 24 GB VRAM with certain configurations | Gradient checkpointing enabled by default (`gradient_checkpointing: true`). OOM retry logic (FR-23) automatically halves batch size. Configuration validation warns when estimated VRAM exceeds 90% of detected capacity. |
| R3 | Medium | SQLite write contention under rapid logging | SQLite WAL (Write-Ahead Logging) mode enabled at database creation. Log writes are batched at configurable intervals (default: 5s) rather than per-line. Read operations are non-blocking under WAL mode. |
| R4 | Medium | Stale `.lock` file after unclean container shutdown | Heartbeat-based stale lock detection (Section 10.4) with configurable timeout (default: 300s). Docker health check monitors heartbeat freshness. Docker restart policy (`unless-stopped`) ensures automatic recovery. |
| R5 | Medium | Training backend (ai-toolkit / kohya) introduces breaking changes | Training backend is pinned to a specific commit hash or release tag in the Dockerfile. Updates are deliberate and tested before promotion to a new container image version. |
| R6 | Low | Filesystem corruption on unclean host shutdown | SQLite WAL mode provides crash recovery. Training checkpoints provide recovery points for interrupted jobs. Ext4/XFS journaling on host filesystem provides block-level protection. |

## 15. Open Questions

| ID | Question | Context & Next Steps |
|----|----------|---------------------|
| OQ-1 | ai-toolkit vs. kohya sd-scripts as training backend | Evaluate both frameworks for Flux.1 LoRA compatibility, training quality, maintenance cadence, and community support. Decision required before M2 (Week 2). Key criteria: Flux.1 native support, API stability, and deterministic training support. |
| OQ-2 | Optimal default rank/alpha for Flux.1 LoRA | Current defaults (rank=32, alpha=16) are inherited from SDXL conventions. Flux.1's transformer architecture may benefit from different values. Benchmark rank 32/16 vs. 64/32 vs. 128/64 on a standard test dataset. Decision required before M7 (v1.0 release). |
| OQ-3 | SDXL-style bucketing compatibility with Flux.1 | Flux.1 uses a flow-matching architecture distinct from SDXL's latent diffusion. Investigate whether aspect-ratio bucketing (common in SDXL training) is compatible with Flux.1's resolution handling or requires adaptation. Decision required before M3. |
| OQ-4 | Multi-GPU support for future hosts | Current design targets single-GPU operation. Assess feasibility and priority of multi-GPU support (data parallelism or model parallelism) for future hosts with multiple GPUs. Deferred to v2.0 roadmap. |
| OQ-5 | Prodigy optimizer effectiveness for Flux.1 LoRA | The Prodigy optimizer offers learning-rate-free training. Evaluate whether it produces competitive results on Flux.1 compared to AdamW8bit with manual LR scheduling. Benchmark during M2–M3. |

## 16. Appendix

### A. Sample TOML Configuration

```toml
# ============================================
# Flux.1 LoRA Training Configuration
# Job: Character consistency — "ohwx" token
# ============================================

[job]
priority = 0
retry_on_oom = true
max_retries = 2

[model]
model_name_or_path = "/data/models/flux1-dev"
output_dir = "/data/output/"

[dataset]
dataset_path = "/data/datasets/ohwx-character"

[training]
network_rank = 32
network_alpha = 16.0
learning_rate = 1e-4
optimizer = "adamw8bit"
lr_scheduler = "cosine"
batch_size = 1
max_train_epochs = 20
resolution = 1024
mixed_precision = "bf16"
seed = 42
gradient_checkpointing = true

[output]
save_every_n_steps = 500
sample_every_n_steps = 250
sample_prompts = [
    "a photo of ohwx person standing in a garden, natural lighting",
    "a portrait of ohwx person, studio lighting, neutral background",
    "ohwx person walking through a city street, candid photography"
]

[notification]
# notification_webhook = "http://192.168.1.100:8080/hooks/training"
```

### B. SQLite Schema

```sql
-- ============================================
-- Training Pipeline SQLite Schema v1.0
-- ============================================

-- Enable WAL mode for concurrent read access
PRAGMA journal_mode=WAL;

-- Primary training runs table
CREATE TABLE IF NOT EXISTS runs (
    job_id          TEXT PRIMARY KEY,       -- UUID v4
    config_hash     TEXT NOT NULL,          -- SHA-256 of normalized config
    config_json     TEXT NOT NULL,          -- Full config snapshot as JSON
    status          TEXT NOT NULL           -- QUEUED|PREPARING|TRAINING|
                        DEFAULT 'QUEUED',   -- COMPLETING|DONE|FAILED|CANCELLED
    priority        INTEGER DEFAULT 0,
    start_time      TEXT,                   -- ISO 8601 timestamp
    end_time        TEXT,                   -- ISO 8601 timestamp
    duration_s      REAL,                   -- Duration in seconds
    exit_code       INTEGER,
    error_message   TEXT,
    output_path     TEXT,                   -- Path to output .safetensors
    output_hash     TEXT,                   -- SHA-256 of output file
    retry_count     INTEGER DEFAULT 0,
    batch_size_used INTEGER,               -- Actual batch size (after OOM reduction)
    gpu_name        TEXT,
    gpu_vram_mb     INTEGER,
    avg_gpu_util    REAL,                   -- Average GPU utilization %
    max_gpu_util    REAL,                   -- Peak GPU utilization %
    avg_vram_mb     REAL,                   -- Average VRAM usage in MB
    max_vram_mb     REAL,                   -- Peak VRAM usage in MB
    created_at      TEXT DEFAULT (datetime('now')),
    updated_at      TEXT DEFAULT (datetime('now'))
);

-- Training metrics (loss, learning rate per step)
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

-- Orchestrator events (lifecycle, errors, warnings)
CREATE TABLE IF NOT EXISTS events (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    job_id          TEXT REFERENCES runs(job_id), -- NULL for system events
    event_type      TEXT NOT NULL,          -- INFO|WARNING|ERROR|SYSTEM
    message         TEXT NOT NULL,
    timestamp       TEXT DEFAULT (datetime('now'))
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_runs_status ON runs(status);
CREATE INDEX IF NOT EXISTS idx_runs_start_time ON runs(start_time);
CREATE INDEX IF NOT EXISTS idx_metrics_job_id ON metrics(job_id);
CREATE INDEX IF NOT EXISTS idx_metrics_step ON metrics(job_id, step);
CREATE INDEX IF NOT EXISTS idx_events_job_id ON events(job_id);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
```

### C. Sample docker-compose.yml

```yaml
# ============================================
# LoRA Training Pipeline — Docker Compose
# ============================================

version: "3.8"

services:
  lora-pipeline:
    image: lora-pipeline:1.0.0
    container_name: lora-pipeline
    restart: unless-stopped
    runtime: nvidia

    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=compute,utility
      - PIPELINE_POLL_INTERVAL=30
      - PIPELINE_MAX_CONCURRENT=1
      - CUBLAS_WORKSPACE_CONFIG=:4096:8

    volumes:
      - /srv/lora-pipeline/data:/data

    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

    healthcheck:
      test: ["/opt/pipeline/healthcheck.sh"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 120s

    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
```

---

**End of Document — PRD v1.0 — April 2026 — Robert Pangrazio**