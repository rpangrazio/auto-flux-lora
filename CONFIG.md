# Configuration Reference

**Version:** 1.0.0

This document describes all configuration parameters for the Flux.1 LoRA Training Pipeline.

---

## Configuration File Format

Configuration files use TOML format (`.toml`) or YAML format (`.yaml`/`.yml`). Place job configurations in the queue directory (`/data/queue/`).

---

## Job Section

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `job_id` | string | filename | Unique job identifier (auto-generated from filename if not set) |
| `priority` | integer | 0 | Job priority (higher values processed first) |
| `retry_on_oom` | boolean | true | Automatically retry with halved batch size on CUDA OOM |
| `max_retries` | integer | 2 | Maximum number of retry attempts on OOM |
| `notification_webhook` | string | (none) | HTTP endpoint for completion/failure notifications |

### Example

```toml
[job]
job_id = "my-training-run"
priority = 10
retry_on_oom = true
max_retries = 3
notification_webhook = "http://192.168.1.100:8080/hooks/training"
```

---

## Model Section

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `model_name_or_path` | string | required | Path to pretrained Flux.1 model or HuggingFace model identifier |
| `output_dir` | string | /data/output/ | Base output directory for trained adapters |
| `output_name` | string | (job_id) | Name for output adapter files |

### Example

```toml
[model]
model_name_or_path = "/data/models/flux1-dev"
output_dir = "/data/output"
output_name = "my-lora-adapter"
```

---

## Dataset Section

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dataset_path` | string | required | Path to training dataset directory |
| `caption_extension` | string | .txt | File extension for caption/text files |
| `recursive` | boolean | false | Recursively scan subdirectories for images |

### Dataset Directory Structure

```
dataset_path/
├── image001.jpg
├── image001.txt    # caption file
├── image002.png
├── image002.txt
└── subfolder/
    └── image003.jpg
    └── image003.txt
```

---

## Training Section

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `network_rank` | integer | 32 | LoRA rank dimension (higher = more capacity, more VRAM) |
| `network_alpha` | float | rank/2 | LoRA alpha scaling parameter |
| `learning_rate` | float | 1e-4 | Training learning rate |
| `optimizer` | string | adamw8bit | Optimizer type (adamw8bit, adamw, sgd, prodigy) |
| `lr_scheduler` | string | cosine | Learning rate scheduler (cosine, constant, polynomial) |
| `batch_size` | integer | 1 | Training batch size per GPU |
| `max_train_epochs` | integer | 20 | Maximum training epochs |
| `resolution` | integer | 1024 | Training resolution (image size) |
| `mixed_precision` | string | auto | Mixed precision mode (auto, fp16, bf16, no) |
| `seed` | integer | 42 | Random seed for reproducibility |
| `gradient_checkpointing` | boolean | true | Enable gradient checkpointing to reduce VRAM usage |
| `max_grad_norm` | float | 1.0 | Gradient clipping norm |
| `weight_decay` | float | 0.01 | Weight decay strength |
| `warmup_steps` | integer | 100 | Learning rate warmup steps |
| `network_module` | string | locon | LoRA network module type (locon, lokr, loha, ia3) |

### Precision Selection

The `mixed_precision` parameter supports automatic detection based on GPU:

| GPU Architecture | Compute Capability | Selected Precision |
|-----------------|-------------------|-------------------|
| NVIDIA Ampere+ (A100, H100, RTX 30/40) | 8.0+ | bf16 |
| NVIDIA Volta (V100) | 7.0 | fp16 |
| NVIDIA Pascal (P40, P100) | 6.0-6.x | fp16 |

Set `mixed_precision = "auto"` for automatic selection.

### Optimizer Options

| Optimizer | Description | VRAM Benefit |
|-----------|-------------|--------------|
| `adamw8bit` | 8-bit AdamW (recommended) | Significant |
| `adamw` | Standard AdamW | Moderate |
| `sgd` | Stochastic Gradient Descent | Low |
| `prodigy` | Prodigy adaptive optimizer | Moderate |

---

## Output Section

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `save_every_n_steps` | integer | 500 | Save checkpoint every N steps |
| `save_at_end` | boolean | true | Save final adapter on completion |
| `sample_every_n_steps` | integer | 250 | Generate sample images every N steps |
| `sample_prompts` | array | [] | Text prompts for sample generation |
| `output_format` | string | safetensors | Output file format (safetensors, ckpt) |

### Example

```toml
[output]
save_every_n_steps = 500
sample_every_n_steps = 250
sample_prompts = [
    "a photo of a person in a garden",
    "a portrait of a person, studio lighting"
]
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PIPELINE_DIR` | /opt/pipeline | Installation directory for pipeline scripts |
| `PIPELINE_QUEUE_DIR` | /data/queue | Queue directory for job configs |
| `PIPELINE_OUTPUT_DIR` | /data/output | Output directory for trained adapters |
| `PIPELINE_LOG_DIR` | /data/logs | Log directory (contains SQLite DB) |
| `PIPELINE_DATASET_DIR` | /data/datasets | Default datasets directory |
| `PIPELINE_CONFIG_DIR` | /data/configs | Config snapshots directory |
| `PIPELINE_POLL_INTERVAL` | 30 | Queue polling interval (seconds) |
| `PIPELINE_MAX_CONCURRENT` | 1 | Maximum concurrent jobs |
| `PIPELINE_MAX_RETRIES` | 2 | Maximum OOM retry attempts |
| `GPU_TEMP_WARN` | 85 | GPU temperature warning threshold (Celsius) |
| `GPU_TEMP_CRIT` | 90 | GPU temperature critical threshold (Celsius) |
| `NVIDIA_VISIBLE_DEVICES` | all | GPU visibility (all, 0, 1, etc.) |
| `CUBLAS_WORKSPACE_CONFIG` | :4096:8 | Deterministic CUDA workspace |
| `PYTHONHASHSEED` | 42 | Python hash seed for reproducibility |

---

## Control Files

| File | Location | Purpose |
|------|----------|---------|
| `.lock` | queue/ | Prevents concurrent orchestrator instances (PID:timestamp format) |
| `.pause` | queue/ | Suspends job dequeue (orchestrator waits for removal) |
| `.cancel` | queue/ | Triggers graceful shutdown (SIGTERM handling) |
| `.done` | output/{job_id}/ | Written on successful completion |
| `.failed` | output/{job_id}/ | Written on job failure |

---

## SQLite Database Schema

Database: `/data/logs/training.db`

### runs table

| Column | Type | Description |
|--------|------|-------------|
| job_id | TEXT | Primary key |
| config_hash | TEXT | SHA256 of config file |
| config_json | TEXT | Full config content |
| status | TEXT | QUEUED/PREPARING/TRAINING/DONE/FAILED |
| priority | INTEGER | Job priority |
| start_time | TEXT | ISO timestamp |
| end_time | TEXT | ISO timestamp |
| duration_s | REAL | Duration in seconds |
| exit_code | INTEGER | Process exit code |
| error_message | TEXT | Error description |
| output_path | TEXT | Path to output adapter |
| output_hash | TEXT | SHA256 of output file |
| retry_count | INTEGER | Number of OOM retries |
| batch_size_used | INTEGER | Final batch size |
| gpu_name | TEXT | GPU model name |
| gpu_vram_mb | INTEGER | Total VRAM in MB |
| avg_gpu_util | REAL | Average GPU utilization % |
| max_gpu_util | REAL | Maximum GPU utilization % |
| avg_vram_mb | REAL | Average VRAM usage MB |
| max_vram_mb | REAL | Maximum VRAM usage MB |

### metrics table

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key |
| job_id | TEXT | Foreign key to runs |
| step | INTEGER | Training step |
| epoch | REAL | Epoch number |
| loss | REAL | Training loss |
| learning_rate | REAL | Current LR |
| grad_norm | REAL | Gradient norm |
| vram_mb | REAL | VRAM usage |
| gpu_temp_c | REAL | GPU temperature |
| timestamp | TEXT | ISO timestamp |

### events table

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Primary key |
| job_id | TEXT | Foreign key to runs |
| event_type | TEXT | Event category |
| message | TEXT | Event description |
| timestamp | TEXT | ISO timestamp |

---

## Validation Rules

### Required Fields
- `model_name_or_path` - Must exist if training is to run
- `dataset_path` - Must be a readable directory with at least 3 images

### Value Constraints
- `network_rank`: 1-1024
- `network_alpha`: > 0
- `learning_rate`: > 0
- `batch_size`: >= 1
- `max_train_epochs`: >= 1
- `resolution`: 256-2048 (power of 2)
- `seed`: >= 0

### Automatic Corrections
- `network_alpha` defaults to `network_rank / 2` if not specified
- `mixed_precision = "auto"` triggers GPU capability detection