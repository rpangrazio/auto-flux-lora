# Changelog

All notable changes to the Auto-Flux LoRA project are recorded here.

The format follows "Keep a Changelog" and the project uses semantic versioning where applicable.

## [Unreleased] - 2026-06-08

### Added
- Expanded operational `docs/usage.md` with containerized quick-start, job submission guide, environment variables, and basic troubleshooting.
- Improved `README.md` with clearer quick-start, developer install steps, and run-mode descriptions.

### Changed
- Clarified defaults for environment variables and queue/poll behavior.
- Consolidated documentation references into `docs/`.

### Fixed
- Documentation typos and examples updated to match repository layout.

## [1.0.0] - 2026-04-19

### Added
- Initial autonomous GPU-accelerated LoRA training pipeline for Flux.1 with containerized orchestrator.
- File-based job queue, TOML/YAML job definitions, and SQLite run metadata logging.
- Per-job log capture and config snapshot persistence.
- Control-file lifecycle semantics (`.lock`, `.pause`, `.cancel`, `.done`).
- Deterministic training seeding across Python/NumPy/PyTorch/CUDA and CUBLAS workspace configuration.

### Known Limitations
- Training backend (kohya-ss or ai-toolkit) is required and not shipped in the container image; mount or provide at runtime.
- Multi-host orchestration is out-of-scope for v1.0.

*Documentation updated: 2026-06-08 (OpenClaw Assistant)*
