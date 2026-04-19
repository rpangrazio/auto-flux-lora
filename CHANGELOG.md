# Changelog

All notable changes to the Flux.1 LoRA Training Pipeline will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - 2026-04-19

### Added
- FR-05: Environment capture at startup (Python packages, CUDA version, GPU driver version)
- FR-09: Sample image generation during training using Flux.1-dev pipeline

### Changed
- FR-07: GPU capability detection now uses actual CUDA compute capability via `nvidia-smi --query-gpu=compute_cap`
- FR-10/FR-11: Dataset validation now detects/counts caption files, validates image-caption pairing, detects corrupt images using Pillow
- FR-12: Image preprocessing implemented (resize, center-crop, aspect-ratio bucketing)
- FR-18: Training subprocess properly isolated with `exec` for signal propagation and log capture
- FR-22: VRAM monitoring (`monitor_vram()`) now called during active training loop
- FR-06: `sample_prompts` now written to file for training backend execution

### Verified
- PRD v1.0 verification complete - all 24 functional requirements, 6 non-functional requirements, Dockerfile spec, orchestrator design, and SQLite schema verified as SATISFIED
- `.VERIFIED` file created

### Known Gaps
- None — all identified requirements now satisfied

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

### Milestones Completed
- **M1**: Dockerfile + Base Image Validated
- **M2**: Training Backend Integrated
- **M3**: Orchestrator MVP
- **M4**: Control-File Mechanisms
- **M5**: OOM Recovery, Retry Logic, Notification Hooks
- **M6**: Testing Suite Complete, Reproducibility Validated
- **M7**: Documentation, v1.0 Release

### Infrastructure
- Docker image: `lora-pipeline:1.0.0`
- Base image: `nvidia/cuda:12.4.1-runtime-ubuntu22.04`
- Target GPU: NVIDIA Tesla P40 (24GB VRAM, Compute 6.1)
- Storage paths: `/data/{datasets,configs,output,logs,queue}`

### Dependencies
- Python 3.10
- PyTorch 2.2.0
- Transformers 4.39.0
- Diffusers 0.27.0
- Accelerate 0.27.0
- PEFT 0.10.0
- bitsandbytes 0.43.0
- safetensors 0.4.2

### Known Limitations
- Training backend (kohya-ss or ai-toolkit) must be mounted separately for actual training
- Container image tagging and registry push require external docker CLI
- GitHub release creation requires gh CLI authentication
