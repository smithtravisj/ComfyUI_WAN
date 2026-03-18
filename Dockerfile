# ComfyUI WAN 2.2 Serverless Docker Image
# Optimized for RunPod serverless deployment
# Build from Mac with: docker buildx build --platform linux/amd64 ...

# Explicitly specify target platform for Mac builds
# Using NVIDIA CUDA base image (publicly available) instead of RunPod image
FROM --platform=linux/amd64 nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

# Build arguments for metadata
ARG BUILDTIME
ARG VERSION
ARG REVISION

# Labels for image metadata
LABEL org.opencontainers.image.title="ComfyUI WAN 2.2 Serverless"
LABEL org.opencontainers.image.description="ComfyUI WAN 2.2 optimized for RunPod serverless with network volume support"
LABEL org.opencontainers.image.created="${BUILDTIME}"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.revision="${REVISION}"
LABEL org.opencontainers.image.vendor="ComfyUI WAN"
LABEL org.opencontainers.image.licenses="GPL-3.0"

# Set platform explicitly (critical for Mac builds)
ARG TARGETPLATFORM=linux/amd64
ENV TARGETPLATFORM=${TARGETPLATFORM}

# System dependencies (Layer 1 - rarely changes)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-venv \
    python3.11-dev \
    python3-pip \
    git \
    git-lfs \
    curl \
    wget \
    ffmpeg \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libglib2.0-0 \
    && git lfs install \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.11 /usr/bin/python3 \
    && ln -sf /usr/bin/python3.11 /usr/bin/python

# Set working directory
WORKDIR /comfyui

# Copy ComfyUI code (Layer 2 - changes frequently)
# Note: .dockerignore should exclude venv, models, output, temp, __pycache__
COPY . /comfyui/

# Install minimal Python dependencies for handler only
# Main venv is on network volume
# Use --platform flag to ensure x86_64 wheels on Mac builds
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir \
    runpod==1.7.3 \
    boto3==1.34.34 \
    aiofiles==23.2.1 \
    || (echo "Fallback: Installing without platform-specific wheels" && \
        pip install --no-cache-dir --prefer-binary \
        runpod \
        boto3 \
        aiofiles)

# Create necessary directories
RUN mkdir -p \
    /comfyui/output \
    /comfyui/temp \
    /comfyui/input \
    /workspace

# Copy serverless handler files
COPY serverless/handler.py /comfyui/handler.py
COPY serverless/warmup.py /comfyui/warmup.py

# GPU optimization environment variables
ENV CUDA_MODULE_LOADING=LAZY \
    PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Verify architecture during build (catches Mac build issues early)
RUN python -c "import platform; \
    arch = platform.machine(); \
    print(f'Build architecture: {arch}'); \
    assert arch == 'x86_64', f'ERROR: Wrong architecture {arch}, expected x86_64 for RunPod compatibility'"

# Verify Python dependencies
RUN python -c "import runpod; import boto3; import aiofiles; print('✓ Handler dependencies verified')"

# Health check (optional - useful for debugging)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import sys; sys.exit(0)" || exit 1

# Expose port (not used in serverless but good practice)
EXPOSE 8188

# Set the handler as the entry point
CMD ["python", "-u", "handler.py"]
