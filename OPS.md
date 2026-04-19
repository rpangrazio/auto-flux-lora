# Operations Runbook

**Version:** 1.0.0

This document provides operational guidance for deploying and maintaining the Flux.1 LoRA Training Pipeline.

---

## Deployment

### Prerequisites

- Docker Engine 24.x+
- NVIDIA drivers 535+
- NVIDIA Container Toolkit (nvidia-docker2)
- NVIDIA Tesla P40 or equivalent GPU (24GB VRAM minimum)
- CUDA 12.x

### Quick Deployment

```bash
# 1. Build container image
docker build -t lora-pipeline:1.0.0 .

# 2. Setup storage directories
./scripts/setup_storage.sh /srv/lora-pipeline/data

# 3. Start orchestrator
docker compose up -d

# 4. Verify health
docker inspect --format='{{.State.Health.Status}}' lora-pipeline
```

### Docker Compose Configuration

```yaml
version: '3.8'
services:
  lora-pipeline:
    image: lora-pipeline:1.0.0
    container_name: lora-pipeline
    runtime: nvidia
    environment:
      - NVIDIA_VISIBLE_DEVICES=all
      - PIPELINE_POLL_INTERVAL=30
      - PIPELINE_MAX_CONCURRENT=1
      - GPU_TEMP_WARN=85
      - GPU_TEMP_CRIT=90
    volumes:
      - /srv/lora-pipeline/data:/data
    healthcheck:
      test: ["CMD", "/opt/pipeline/healthcheck.sh"]
      interval: 60s
      timeout: 10s
      retries: 3
    restart: unless-stopped
```

---

## Monitoring

### Real-Time Logs

```bash
# Follow orchestrator logs
docker logs -f lora-pipeline

# Follow specific job log
docker exec lora-pipeline tail -f /data/logs/{job_id}.log
```

### Job Status Queries

```bash
# Query SQLite database directly
docker exec lora-pipeline sqlite3 /data/logs/training.db \
  "SELECT job_id, status, duration_s, retry_count FROM runs ORDER BY start_time DESC LIMIT 10;"

# Count jobs by status
docker exec lora-pipeline sqlite3 /data/logs/training.db \
  "SELECT status, COUNT(*) FROM runs GROUP BY status;"

# Get job events
docker exec lora-pipeline sqlite3 /data/logs/training.db \
  "SELECT * FROM events WHERE job_id='{job_id}' ORDER BY timestamp;"
```

### GPU Monitoring

```bash
# Check GPU status inside container
docker exec lora-pipeline nvidia-smi

# Check GPU within orchestrator logs
grep "GPU detected" /srv/lora-pipeline/data/logs/orchestrator.log

# Monitor VRAM usage during training
watch -n 5 'nvidia-smi --query-gpu=memory.used,memory.total --format=csv'
```

### Container Health

```bash
# Check health status
docker inspect --format='{{.State.Health.Status}}' lora-pipeline

# Check health details
docker inspect --format='{{.State.Health.Log}}' lora-pipeline
```

---

## Queue Management

### Submit a Job

```bash
# Copy config to queue directory
cp my_config.toml /srv/lora-pipeline/data/queue/

# Job automatically detected within poll_interval (default 30s)
```

### List Pending Jobs

```bash
# List all job config files
ls -la /srv/lora-pipeline/data/queue/*.toml

# Check job order by priority
docker exec lora-pipeline bash -c 'source /opt/pipeline/helpers/queue_manager.sh && list_pending_jobs_by_priority'
```

### Cancel a Job

```bash
# Create cancel sentinel
touch /srv/lora-pipeline/data/queue/.cancel

# Orchestrator will gracefully shutdown
# Restart container to resume operations
docker compose restart
```

### Pause Queue Processing

```bash
# Pause - orchestrator waits but completes current job
touch /srv/lora-pipeline/data/queue/.pause

# Resume
rm /srv/lora-pipeline/data/queue/.pause
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check NVIDIA runtime
docker info | grep nvidia

# Verify NVIDIA drivers
nvidia-smi

# Test GPU passthrough
docker run --rm --gpus all nvidia/cuda:12.4.1-runtime-ubuntu22.04 nvidia-smi
```

### Job Stuck in PREPARING/TRAINING

```bash
# Check lock file
cat /srv/lora-pipeline/data/queue/.lock

# Check if orchestrator process is running
docker exec lora-pipeline ps aux | grep orchestrator

# Check job logs
docker exec lora-pipeline cat /data/logs/{job_id}.log

# Manual recovery: remove stale lock
rm /srv/lora-pipeline/data/queue/.lock
docker restart lora-pipeline
```

### GPU Temperature Issues

```bash
# Check current temperature
nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader

# Lower temperature thresholds (edit docker-compose.yml)
environment:
  - GPU_TEMP_WARN=80
  - GPU_TEMP_CRIT=85

# Ensure adequate cooling
#  - Check fans are working
#  - Verify airflow
#  - Consider undervolting GPU
```

### Out of Memory (OOM) Errors

```bash
# Check if job is retrying with reduced batch size
docker exec lora-pipeline sqlite3 /data/logs/training.db \
  "SELECT job_id, retry_count, batch_size_used FROM runs WHERE status='FAILED';"

# Reduce default batch_size in config
# Enable gradient_checkpointing
# Lower resolution
```

### Database Corruption

```bash
# Backup database
cp /srv/lora-pipeline/data/logs/training.db /srv/lora-pipeline/data/logs/training.db.backup

# Check integrity
docker exec lora-pipeline sqlite3 /data/logs/training.db "PRAGMA integrity_check;"

# If corrupted, may need to reset (last resort)
# docker exec lora-pipeline rm /data/logs/training.db
# Container will recreate on restart
```

---

## Backup and Recovery

### Backup

```bash
# Backup entire data directory
tar -czf lora-pipeline-backup-$(date +%Y%m%d).tar.gz /srv/lora-pipeline/data/

# Backup database specifically
cp /srv/lora-pipeline/data/logs/training.db ./training.db.backup

# Backup configuration snapshots
cp -r /srv/lora-pipeline/data/configs ./configs.backup
```

### Recovery

```bash
# Stop container
docker compose down

# Restore from backup
tar -xzf lora-pipeline-backup-YYYYMMDD.tar.gz -C /

# Restart container
docker compose up -d
```

---

## Upgrades

### Upgrade Container Image

```bash
# Pull new image (when available)
docker pull lora-pipeline:1.0.1

# Update compose file
sed -i 's/lora-pipeline:1.0.0/lora-pipeline:1.0.1/' docker-compose.yml

# Rolling upgrade (zero downtime if using multiple replicas)
docker compose up -d --no-deps --build lora-pipeline
```

### Backup Before Upgrade

```bash
# Always backup before upgrade
./scripts/setup_storage.sh /srv/lora-pipeline/data  # idempotent
tar -czf pre-upgrade-backup.tar.gz /srv/lora-pipeline/data/
```

---

## Performance Tuning

### VRAM Optimization

```toml
# In job config
gradient_checkpointing = true
mixed_precision = "auto"  # or "bf16" on Ampere+
batch_size = 1  # reduce if OOM
resolution = 512  # lower if VRAM constrained
network_rank = 16  # reduce for lower VRAM
```

### Throughput Optimization

```toml
# For faster training on ample VRAM
batch_size = 2  # if VRAM allows
gradient_checkpointing = false  # trades VRAM for speed
save_every_n_steps = 1000  # less frequent saves
sample_every_n_steps = 500  # less frequent sampling
```

### Priority Queue Tuning

```bash
# For higher throughput
export PIPELINE_POLL_INTERVAL=10  # faster polling, more CPU usage

# For priority processing
# Set high priority in job config
priority = 100
```

---

## Security Considerations

### Air-Gap Operation

The pipeline is designed for air-gap operation:
- No external network required during training
- All dependencies bundled in container image
- Webhook notifications are optional and can be disabled

### Filesystem Permissions

```bash
# Ensure proper permissions
chown -R 1000:1000 /srv/lora-pipeline/data
chmod -R 755 /srv/lora-pipeline/data
chmod 700 /srv/lora-pipeline/data/queue  # only orchestrator needs write access
```

---

## Health Check Tuning

```yaml
# In docker-compose.yml
healthcheck:
  test: ["CMD", "/opt/pipeline/healthcheck.sh"]
  interval: 60s      # adjust based on workload
  timeout: 10s        # should be less than poll_interval
  retries: 3          # 3 failures = unhealthy
  start_period: 120s  # allow time for initialization
```

### Health Check Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| HEARTBEAT_TIMEOUT | 300 | Lock file max age before considered stale |
| PIPELINE_POLL_INTERVAL | 30 | Orchestrator polling frequency |
| HEALTHCHECK interval | 60s | Docker health check frequency |

---

## Log Rotation

```bash
# Configure log rotation in /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}

# Restart Docker to apply
systemctl restart docker
```

### Manual Log Cleanup

```bash
# Archive old logs
find /srv/lora-pipeline/data/logs/ -name "*.log" -mtime +7 -exec gzip {} \;

# Remove archived logs older than 30 days
find /srv/lora-pipeline/data/logs/ -name "*.log.gz" -mtime +30 -delete
```