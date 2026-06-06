# Changelog

All notable changes to the Flux.1 LoRA Training Pipeline will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - 2026-06-06

### Added
- `docs/usage.md` with detailed operational and job submission instructions, environment variables, and troubleshooting guidance.
- `README.md` refreshed with accurate quickstart and configuration instructions.

### Changed
- Corrected documentation to match repository layout and single-node containerized deployment (Docker + NVIDIA Container Toolkit).
- Updated environment variable names and defaults for clarity.

### Fixed
- Clarified control-file semantics and job lifecycle.

## [1.0.0] - 2026-04-19

### Added
- Complete autonomous GPU-accelerated LoRA training pipeline for Flux.1
- Docker container with NVIDIA CUDA 12.4.1 base image
- File-based job queue with TOML/YAML configuration support
- FIFO and priority-based job ordering
- Job lifecycle state machine (QUEUED → PREPARING → TRAINING → COMPLETING → DONE)
- SQLite database for structured run metadata and metrics logging
- Per-job log file capture (`/data/logs/{job_id}.log`)
- Config snapshot saving per job output directory
- Concurrent job limiting via `PIPELINE_MAX_CONCURRENT`
- GPU detection and auto-precision selection (fp16 on Pascal, bf16 on Ampere+)
- Control file mechanisms:
  - `.lock` - prevents concurrent orchestrator instances
  - `.pause` - suspends job dequeue
  - `.cancel` - graceful job termination
  - `.done` - completion metadata
- Heartbeat mechanism with stale lock detection and recovery
- OOM detection with automatic batch-size halving and retry
- GPU temperature monitoring and thermal throttling
- Notification webhook support (HTTP POST on completion/failure)
- Deterministic training with seeded RNG across Python, NumPy, PyTorch, and CUDA
- Gradient checkpointing for VRAM optimization
- Comprehensive documentation:
  - README.md - overview, architecture, and quick start
  - CONFIG.md - complete configuration reference
  - OPS.md - operational runbook for deployment and maintenance
  - PRD.md - product requirements document
  - PLAN.md - implementation plan

### Known Limitations
- Training backend (kohya-ss or ai-toolkit) must be mounted separately for actual training
- Container image tagging and registry push require external docker CLI
- GitHub release creation requires gh CLI authentication
