# ============================================
# Flux.1 LoRA Training Pipeline — Dockerfile
# Base: nvidia/cuda:12.4.1-runtime-ubuntu22.04
# ============================================

FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore \
    CUDA_VERSION=12.4 \
    CUDA_PKG_VERSION=12-4 \
    # Training pipeline environment variables
    PIPELINE_QUEUE_DIR=/data/queue \
    PIPELINE_OUTPUT_DIR=/data/output \
    PIPELINE_LOG_DIR=/data/logs \
    PIPELINE_POLL_INTERVAL=30 \
    PIPELINE_MAX_CONCURRENT=1 \
    # Deterministic CUDA settings
    CUBLAS_WORKSPACE_CONFIG=:4096:8 \
    PYTHONHASHSEED=42 \
    # NVIDIA Container Toolkit settings
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.10 \
    python3-pip \
    python3.10-venv \
    git \
    sqlite3 \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

RUN curl -s https://bootstrap.pypa.io/get-pip.py | python3.10 && \
    ln -sf /usr/bin/python3.10 /usr/bin/python3 && \
    ln -sf /usr/bin/python3.10 /usr/bin/python

RUN python3 -m pip install --no-cache-dir \
    torch==2.2.0 \
    torchvision==0.17.0 \
    transformers==4.39.0 \
    diffusers==0.27.0 \
    accelerate==0.27.0 \
    safetensors==0.4.2 \
    peft==0.10.0 \
    bitsandbytes==0.43.0 \
    Pillow==10.2.0 \
    toml==0.10.2 \
    pyyaml==6.0.1 \
    numpy==1.26.4 \
    sentencepiece==0.1.99 \
    protobuf==3.20.3

WORKDIR /data

RUN mkdir -p /data/datasets \
             /data/configs \
             /data/output \
             /data/logs \
             /data/queue

COPY src/orchestrator.sh /opt/pipeline/orchestrator.sh
COPY src/healthcheck.sh /opt/pipeline/healthcheck.sh
COPY src/helpers/*.sh /opt/pipeline/helpers/

RUN chmod +x /opt/pipeline/orchestrator.sh \
              /opt/pipeline/healthcheck.sh \
              /opt/pipeline/helpers/*.sh

ENV PATH="/opt/pipeline:${PATH}"

HEALTHCHECK --interval=60s --timeout=10s --retries=3 \
    CMD /opt/pipeline/healthcheck.sh || exit 1

ENTRYPOINT ["/opt/pipeline/orchestrator.sh"]