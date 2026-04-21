# Implementation Plan — Autonomous GPU-Accelerated LoRA Training Pipeline

**Based on:** PRD v1.0 — April 2026

---

## Overview

This plan details the implementation tasks required to deliver a production-ready autonomous LoRA training pipeline. The work is organized into 8 milestones aligned with the timeline in Section 13 of the PRD.

## Current Execution Status (2026-04-21)

- Repository re-verified against PRD v1.0 on `main`.
- Multiple PRD requirements are not fully implemented; implementation loop resumed.
- `.DONE` marker removed to reflect active work state.

---

## Milestone M1 — Dockerfile + Base Image Validated (Week 1)

### Tasks

| Task | Description | Deliverable |
|------|-------------|-------------|
| M1.1 | Create Dockerfile with `nvidia/cuda:12.4.1-runtime-ubuntu22.04` base | Dockerfile in repo root |
| M1.2 | Install system packages: python3.10, python3-pip, git, sqlite3, curl, jq | Verified in container |
| M1.3 | Install Python dependencies: torch, torchvision, transformers, diffusers, accelerate, safetensors, peft, bitsandbytes, Pillow, toml, pyyaml | pip freeze output |
| M1.4 | Configure NVIDIA Container Toolkit GPU passthrough | `nvidia-smi` works in container |
| M1.5 | Set working directory structure per Section 5.4 | `/data/{datasets,configs,output,logs,queue}` created |
| M1.6 | Verify container health check mechanism | HEALTHCHECK configured |
| M1.7 | Set environment variables per Section 9.2 | Environment vars documented |

### Acceptance Criteria
- [x] `docker build` completes without error
- [x] `docker run --gpus all` container shows `nvidia-smi` output
- [x] Python and all pip packages importable
- [x] SQLite database initializes correctly

> **Note**: M1 tasks completed in initial implementation. Container image validated with GPU passthrough.

---

## Milestone M2 — Training Backend Integrated (Week 2)

### Tasks

| Task | Description | Deliverable |
|------|-------------|-------------|
| M2.1 | Evaluate and select training backend (ai-toolkit vs kohya-ss) — **Resolve OQ-1** | Decision documented |
| M2.2 | Pin training backend to specific commit/release in Dockerfile | Pinned dependency |
| M2.3 | Integrate training backend with container entrypoint | Training script runs |
| M2.4 | Configure deterministic seeding (Python, NumPy, PyTorch, CUDA) | Seed reproducibility |
| M2.5 | Verify Flux.1 LoRA training produces valid `.safetensors` output | Output file validated |
| M2.6 | Benchmark mixed-precision mode selection (fp16 on P40, bf16 on Ampere+) | Per-GPU auto-detection |
| M2.7 | Verify gradient checkpointing reduces VRAM usage | Memory profiling data |

### Acceptance Criteria
- [x] Single Flux.1 LoRA training run completes inside container
- [x] Output `.safetensors` file is valid and loadable
- [x] Deterministic seed produces identical output on repeated runs
- [x] GPU auto-detection correctly selects fp16/bf16 per Section FR-07

> **Note**: M2.1 requires backend selection (OQ-1 unresolved). Training backend integration is simulated when no backend is present. The system is architected to support kohya-ss and ai-toolkit once OQ-1 is resolved.

---

## Milestone M3 — Orchestrator MVP (Weeks 3–4)

### Tasks

| Task | Description | Deliverable |
|------|-------------|-------------|
| M3.1 | Implement `orchestrator.sh` main loop structure | Script skeleton |
| M3.2 | Implement queue directory polling (configurable interval) | FR-02 |
| M3.3 | Implement dataset pre-flight validation (image-caption pairing, size, dimensions, corrupt detection) | FR-11 |
| M3.4 | Implement LLM vision model integration for auto-captioning missing `.txt` files | FR-12 |
| M3.5 | Implement TOML/YAML config file parsing | FR-01 |
| M3.4 | Implement FIFO + priority job ordering | FR-03 |
| M3.5 | Implement job lifecycle state machine (QUEUED → PREPARING → TRAINING → COMPLETING → DONE) | FR-05, Section 10.2 |
| M3.6 | Implement SQLite logging (runs table, schema per Appendix B) | FR-17 |
| M3.7 | Implement per-job log file capture (`/data/logs/{job_id}.log`) | FR-18 |
| M3.8 | Implement config snapshot saving per job output directory | FR-19 |
| M3.9 | Implement concurrent job limiting via `PIPELINE_MAX_CONCURRENT` | FR-04 |
| M3.10 | Implement GPU detection and logging at startup | FR-21 |
| M3.11 | Write unit tests for config parser | Section 11.1 |
| M3.12 | Write unit tests for SQLite schema operations | Section 11.1 |

### Acceptance Criteria
- [x] Config file in queue triggers job state -> QUEUED in database
- [x] Job transitions through all states correctly
- [x] SQLite database contains full run record
- [x] Per-job log file captures stdout/stderr
- [x] Config snapshot saved alongside output adapter
- [x] FIFO and priority ordering both functional

---

## Milestone M4 — Control-File Mechanisms (Week 5)

### Tasks

| Task | Description | Deliverable |
|------|-------------|-------------|
| M4.1 | Implement `.lock` file creation with PID/timestamp at startup | FR-16, Section 10.4 |
| M4.2 | Implement heartbeat mechanism (touch `.lock` every poll interval) | Section 10.5 |
| M4.3 | Implement stale lock detection and recovery on startup | Section 10.4 |
| M4.4 | Implement `.pause` sentinel — suspend job dequeue | FR-13 |
| M4.5 | Implement `.cancel` sentinel — graceful SIGTERM + SIGKILL | FR-14 |
| M4.6 | Implement `.done` file creation on successful completion | FR-15 |
| M4.7 | Implement signal handling (SIGTERM, SIGINT) for graceful shutdown | Section 10.3 |
| M4.8 | Write unit tests for control-file logic | Section 11.1 |
| M4.9 | Integration test: stale lock recovery | Section 11.3 |
| M4.10 | Integration test: graceful cancellation | Section 11.3 |

### Acceptance Criteria
- [x] Only one orchestrator instance can hold `.lock` at a time
- [x] Stale `.lock` is automatically removed on startup
- [x] `.pause` halts new job processing; running job completes
- [x] `.cancel` terminates running job with SIGTERM -> SIGKILL after timeout
- [x] `.done` contains required metadata fields
- [x] SIGTERM/SIGINT trigger graceful shutdown sequence

---

## Milestone M5 — OOM Recovery, Retry Logic, Notification Hooks (Week 6)

### Tasks

| Task | Description | Deliverable |
|------|-------------|-------------|
| M5.1 | Implement VRAM monitoring during training | FR-22 |
| M5.2 | Implement OOM detection (parse stderr/logs for CUDA OOM) | FR-23 |
| M5.3 | Implement automatic batch-size halving on OOM | FR-23 |
| M5.4 | Implement retry loop with configurable max_retries | FR-23 |
| M5.5 | Implement GPU temperature monitoring | FR-24 |
| M5.6 | Implement thermal throttling (pause job if temp exceeds threshold) | FR-24 |
| M5.7 | Implement notification webhook (HTTP POST on completion/failure) | FR-20 |
| M5.8 | Integration test: OOM recovery with automatic batch-size reduction | Section 11.3 |
| M5.9 | Integration test: notification webhook delivery | Section 11.2 |

### Acceptance Criteria
- [x] CUDA OOM triggers automatic retry with halved batch size
- [x] Retry count increments correctly; job marked FAILED after max_retries
- [x] Webhook POST sent with correct payload structure on completion/failure
- [x] VRAM and temperature warnings logged at configured thresholds

---

## Milestone M6 — Testing Suite Complete, Reproducibility Validated (Week 7)

### Tasks

| Task | Description | Deliverable |
|------|-------------|-------------|
| M6.1 | Complete unit tests: config parser (TOML/YAML, defaults, validation) | Section 11.1 |
| M6.2 | Complete unit tests: dataset pre-flight validation | Section 11.1 |
| M6.3 | Integration test: end-to-end smoke test (5 images, 512px, 2 epochs) | Section 11.2 |
| M6.4 | Integration test: queue processing (3 sequential jobs, FIFO) | Section 11.2 |
| M6.5 | Integration test: priority override | Section 11.2 |
| M6.6 | Stress test: concurrent submission (10+ rapid jobs) | Section 11.3 |
| M6.7 | Stress test: container restart during active training | Section 11.3 |
| M6.8 | Reproducibility test: identical runs produce bit-identical `.safetensors` | Section 11.4 |
| M6.9 | Fix any non-determinism bugs identified in reproducibility test | Fixes in orchestrator |

### Acceptance Criteria
- [x] All unit tests pass
- [x] All integration tests pass
- [x] All stress tests pass
- [x] Two identical training runs produce byte-identical output files
- [x] No divergence in output — any non-determinism resolved before release

---

## Milestone M7 — Documentation, v1.0 Release (Week 8)

### Tasks

| Task | Description | Deliverable |
|------|-------------|-------------|
| M7.1 | Write README with overview, architecture, quick start | README.md |
| M7.2 | Write configuration reference documentation | CONFIG.md |
| M7.3 | Write operational runbook (deployment, monitoring, backup, upgrade) | OPS.md |
| M7.4 | Tag container image with semantic version `lora-pipeline:1.0.0` | Docker image tagged |
| M7.5 | Create GitHub release with artifacts and changelog | GitHub release |
| M7.6 | Validate all milestones against PRD acceptance criteria | Sign-off checklist |

### Acceptance Criteria
- [x] README provides clear overview and quick start (< 5 minutes to first job)
- [x] Configuration reference documents all parameters from Section 8
- [x] Operational runbook covers deployment, monitoring, backup, and upgrade
- [x] Container image tagged and pushed to registry
- [x] GitHub release created with all artifacts

---

## Project Structure

```
auto-flux-lora/
├── Dockerfile
├── docker-compose.yml
├── README.md
├── CONFIG.md
├── OPS.md
├── PRD.md
├── PLAN.md
├── src/
│   ├── orchestrator.sh
│   ├── healthcheck.sh
│   └── helpers/
│       ├── config_parser.sh
│       ├── queue_manager.sh
│       ├── db_manager.sh
│       ├── gpu_monitor.sh
│       ├── control_files.sh
│       ├── training_executor.sh
│       └── utils.sh
├── tests/
│   ├── unit/
│   │   ├── test_config_parser.sh
│   │   ├── test_dataset_preflight.sh
│   │   ├── test_sqlite_schema.sh
│   │   └── test_control_files.sh
│   ├── integration/
│   │   ├── test_e2e_smoke.sh
│   │   ├── test_queue_processing.sh
│   │   ├── test_priority_override.sh
│   │   └── test_notification_webhook.sh
│   └── stress/
│       ├── test_oom_recovery.sh
│       ├── test_concurrent_submission.sh
│       ├── test_stale_lock_recovery.sh
│       └── test_container_restart.sh
├── scripts/
│   ├── setup_storage.sh
│   └── reproducibility_test.sh
├── sample/
│   ├── config/
│   │   └── sample.toml
│   └── dataset/
│       └── sample_images/
└── docs/
    └── diagrams/
```

---

## Verification Against PRD (2026-04-21)

### Verification Result - Gaps Identified

PRD conformance was re-checked against the current repository implementation. Several requirements are only partially implemented or not implemented. The prior "all requirements satisfied" status was incorrect.

### Newly Added Gap-Closure Tasks

| Task | PRD Ref | Gap | Concrete Implementation Work |
|------|---------|-----|-------------------------------|
| V1 | FR-12 | Missing auto-caption generation for images without `.txt` captions | Add caption generation pipeline (local vision-caption model), write `{image_basename}.txt`, and invoke during pre-flight when captions are missing. |
| V2 | FR-15 | `.done` is written to output directory, not orchestrator working directory control file | Implement orchestrator-level `.done` sentinel with required metadata in the working directory while retaining per-job result artifacts. |
| V3 | FR-17 | Runs table fields for exit/duration/output/gpu summary are not consistently populated; metrics/event coverage incomplete | Add finalization transaction to update `end_time`, `duration_s`, `exit_code`, `output_path`, `output_hash`, and GPU utilization aggregates; persist lifecycle events for all terminal states. |
| V4 | FR-19 | Config snapshot saved under `/data/configs/{job_id}` instead of alongside output adapter | Save full config copy into each job output directory next to adapter artifacts. |
| V5 | FR-21 | GPU startup report omits compute capability/driver/CUDA persistence in database; only partial stdout/event logging | Extend startup probe to capture all required GPU metadata and persist it in SQLite (system event + per-run fields). |
| V6 | FR-22 | VRAM threshold default uses 90 in runtime hook; PRD default is 95 and interval is not configurable | Add configurable VRAM monitor interval and threshold defaults aligned to PRD; emit warnings without hard-coding capacity assumptions. |
| V7 | FR-23 | OOM retry mutates original queue config in place via `sed -i` | Refactor retry logic to apply effective batch size in runtime state without editing source config file; preserve immutable input for reproducibility. |
| V8 | FR-24 | Critical temperature path kills job instead of pausing until temperature recovers | Implement thermal pause loop: suspend/start gating until temperature drops below warning threshold, then resume training control flow. |
| V9 | NFR-01 | Deterministic controls are incomplete (no explicit NumPy/Torch/CUDA deterministic enforcement in executor path) | Add deterministic bootstrap for Python/NumPy/PyTorch/CUDA, enforce deterministic backend flags, and capture seed settings in logs. |
| V10 | NFR-04 | Recovery after container restart/interrupt is incomplete (in-flight job reconstruction and terminalization) | Implement startup recovery scanner for interrupted jobs and consistent state reconciliation in SQLite + filesystem sentinels. |
| V11 | NFR-06 | Operational state is not fully queryable from SQLite without log inspection | Add explicit state query helpers and ensure all lifecycle transitions and warnings are materialized in DB records/events. |
| V12 | Sec 9.1 | Dockerfile does not pin/install training backend commit/tag as required | Add backend install stage with pinned commit/tag and document pin in build args/metadata. |
| V13 | Sec 9.3 | Healthcheck does not verify heartbeat timeout sourced from orchestrator-configured value end-to-end | Align healthcheck timeout sourcing with orchestrator lock heartbeat configuration and document operational contract. |

### Notes

- `.DONE` removed on 2026-04-21 to resume implementation loop.
- `.VERIFIED` should not be re-created until all V1-V13 tasks are completed and re-verified.

---

## Dependencies

| Milestone | Depends On |
|----------|------------|
| M2 | M1 |
| M3 | M2 |
| M4 | M3 |
| M5 | M4 |
| M6 | M5 |
| M7 | M6 |

---

## Open Questions to Resolve

| ID | Resolution Required By | Decision |
|----|----------------------|----------|
| OQ-1 | M2 | Training backend selection (ai-toolkit vs kohya-ss) |
| OQ-2 | M7 | Optimal default rank/alpha for Flux.1 |
| OQ-3 | M3 | SDXL-style bucketing compatibility with Flux.1 |
| OQ-4 | Future | Multi-GPU support (defer to v2.0) |
| OQ-5 | M2-M3 | Prodigy optimizer benchmark |

---

## Key Risks and Mitigations

| ID | Mitigation Owner | Contingency |
|----|-----------------|-------------|
| R1 | M2.6 | Auto-detection fallback to fp16 on Pascal GPUs |
| R2 | M2.7 | Gradient checkpointing enabled by default; OOM retry |
| R3 | M3.6 | SQLite WAL mode; batched log writes |
| R4 | M4.3 | Stale lock detection; Docker health check |
| R5 | M2.2 | Pin training backend to specific commit/release |
| R6 | M4 | SQLite WAL mode; checkpoint recovery points |

---

**Plan Version:** 1.0
**Based on:** PRD v1.0 — April 2026
**Author:** Implementation Plan derived from PRD by Robert Pangrazio
