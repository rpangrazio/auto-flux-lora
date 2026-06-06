# Flux.1 LoRA Training Pipeline — Usage Guide

This usage guide explains how to install, configure, and operate the autonomous Flux.1 LoRA training pipeline provided by this repository. It mirrors the quick-start in README.md and provides additional operational details useful for system administrators and QA engineers.

## Quick Start (local, single-node)

1. Build the container image:

```bash
docker build -t lora-pipeline:1.0.0 .
```

2. Create the required storage directories and set permissions:

```bash
mkdir -p /srv/lora-pipeline/data/{queue,output,logs,datasets,configs}
chown -R $(id -u):$(id -g) /srv/lora-pipeline/data
```

3. Configure environment and start the stack:

```bash
export PIPELINE_QUEUE_DIR=/srv/lora-pipeline/data/queue
export PIPELINE_OUTPUT_DIR=/srv/lora-pipeline/data/output
export PIPELINE_LOG_DIR=/srv/lora-pipeline/data/logs

docker compose up -d
```

4. Submit a job by copying a TOML job file into the queue directory:

```bash
cp sample/config/example_training.toml /srv/lora-pipeline/data/queue/
```

Job lifecycle: `QUEUED` → `PREPARING` → `TRAINING` → `COMPLETING` → `DONE`.

## Configuration

The job configuration format is TOML. See `sample/config/example_training.toml` for all supported keys. Key sections include:

- `[job]`: priority, retries
- `[model]`: path to base model, output directory
- `[dataset]`: dataset path and validation options
- `[training]`: learning rate, batch size, precision
- `[output]`: save/sample intervals

## Environment Variables

Set these either in systemd/docker-compose environment or export them in your session:

- `PIPELINE_QUEUE_DIR` (default `/data/queue`)
- `PIPELINE_OUTPUT_DIR` (default `/data/output`)
- `PIPELINE_LOG_DIR` (default `/data/logs`)
- `PIPELINE_POLL_INTERVAL` (default `30`)
- `PIPELINE_MAX_CONCURRENT` (default `1`)

## Monitoring & Health

- Follow logs: `docker logs -f lora-pipeline`
- Check last 10 completed runs: `sqlite3 $PIPELINE_LOG_DIR/training.db "SELECT job_id,status,duration_s FROM runs ORDER BY start_time DESC LIMIT 10;"`
- Container health probe: `docker inspect --format='{{.State.Health.Status}}' lora-pipeline`

## Troubleshooting

1. OOM during training: Collector reduces batch size automatically and retries. Check job log in `$PIPELINE_LOG_DIR/{job_id}.log`.
2. Stale lock `.lock` present: ensure no orchestrator instances are running, then remove the lock file. The orchestrator has stale-lock recovery logic but manual intervention may be required in edge cases.
3. Control files: `.pause` suspends dequeueing; `.cancel` instructs graceful shutdown of running job.

## Testing

Run unit and integration tests via the included shell scripts in `tests/unit` and `tests/integration` respectively.

```bash
bash tests/unit/test_config_parser.sh
bash tests/integration/test_e2e_smoke.sh
```

## Security & Best Practices

- Mount external training backends read-only where possible.
- Keep datasets and model weights on high-performance NVMe-backed storage.
- Use GPU isolation (`NVIDIA_VISIBLE_DEVICES`) to control resource allocation.

## Advanced

- Use the sample scripts in `scripts/` to rotate logs and archive completed runs.
- To run multiple concurrent jobs, set `PIPELINE_MAX_CONCURRENT` and ensure the host has sufficient VRAM and CPU resources.

## Support

Open issues in the repository with `bug` or `support` labels and include `training.db` run metadata when applicable.
