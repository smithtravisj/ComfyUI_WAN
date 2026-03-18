# ComfyUI WAN 2.2 RunPod Serverless - Implementation Design

**Date**: 2026-03-16
**Version**: 1.0
**Author**: Claude Code Analysis
**Status**: Design Phase - Ready for Implementation

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Architecture Overview](#architecture-overview)
3. [Component Design](#component-design)
4. [File Specifications](#file-specifications)
5. [Deployment Strategy](#deployment-strategy)
6. [Testing Plan](#testing-plan)
7. [Cost Analysis](#cost-analysis)
8. [Risk Management](#risk-management)

---

## Executive Summary

### Objective

Convert the existing ComfyUI WAN 2.2 persistent pod installation to a RunPod serverless architecture optimized for burst workloads (1-10 requests/day).

### Target Specifications

| Metric | Target | Current (Persistent) |
|--------|--------|---------------------|
| Cold Start | 50-65 seconds | N/A (always running) |
| Warm Start | 15-25 seconds | Instant |
| Monthly Cost (10 req/day) | $20-30 | $360 |
| Idle Cost | $0/hour | $0.50/hour |
| Storage | 100GB network volume | Pod disk |
| GPU | RTX 4090 (24GB) | Same |

### Key Benefits

- ✅ **92% cost reduction** for burst workloads
- ✅ **Zero idle cost** with minWorkers=0
- ✅ **Auto-scaling** from 0 to 3 workers
- ✅ **S3 integration** for scalable output storage
- ✅ **Persistent models** via network volume (no re-downloads)

---

## Architecture Overview

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      RunPod Serverless Endpoint                  │
│                                                                   │
│  ┌──────────────┐            ┌───────────────────────────────┐  │
│  │ Docker Image │            │    Network Volume (100GB)     │  │
│  │   (~3GB)     │◄───mount───│      /workspace               │  │
│  │              │            │                               │  │
│  │ • ComfyUI    │            │  ├─ models/ (65GB)           │  │
│  │ • Handler    │            │  │  ├─ unet/ (57GB GGUF)     │  │
│  │ • Warmup     │            │  │  ├─ text_encoders/ (3.8GB)│  │
│  │ • Runtime    │            │  │  ├─ vae/ (242MB)          │  │
│  └──────────────┘            │  │  └─ loras/ (4GB)          │  │
│         │                     │  ├─ venv/ (8GB)             │  │
│         ▼                     │  ├─ custom_nodes/ (2GB)     │  │
│  ┌──────────────────────┐    │  └─ output/ (temp)          │  │
│  │   handler.py         │    └───────────────────────────────┘  │
│  │                      │                                        │
│  │ 1. Receive workflow  │    ┌───────────────────────────────┐  │
│  │ 2. Validate          │    │   Cloudflare R2 / AWS S3      │  │
│  │ 3. Execute           │───▶│   • Video outputs             │  │
│  │ 4. Upload to S3      │    │   • Image outputs             │  │
│  │ 5. Return URLs       │    │   • Public CDN URLs           │  │
│  └──────────────────────┘    └───────────────────────────────┘  │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Component Interaction Flow

```
┌─────────┐      ┌──────────┐      ┌─────────────┐      ┌────────┐
│ Client  │─────▶│ RunPod   │─────▶│  Handler    │─────▶│ S3/R2  │
│ Request │ POST │ Endpoint │ JSON │  Execution  │Upload│Storage │
└─────────┘      └──────────┘      └─────────────┘      └────────┘
                                           │
                                           ▼
                                    ┌─────────────┐
                                    │ ComfyUI     │
                                    │ Executor    │
                                    │ (Async)     │
                                    └─────────────┘
                                           │
                                           ▼
                                    ┌─────────────┐
                                    │ Network     │
                                    │ Volume      │
                                    │ (Models)    │
                                    └─────────────┘
```

### Execution States

```
[COLD START]
    │
    ├─ Container startup (8s)
    ├─ Venv activation (3s)
    ├─ ComfyUI init (12s)
    ├─ Load custom nodes (15s)
    ├─ Warmup: VAE + T5 (18s)
    │
    ▼
[READY - Idle Timeout 30s]
    │
    ├─ Receive workflow
    ├─ Validate (2s)
    ├─ Load UNET (15s)
    ├─ Execute workflow (varies)
    ├─ Upload to S3 (3s)
    ├─ Return URLs
    │
    ▼
[WARM - Reuse executor]
    │
    └─ No idle requests for 30s ──▶ [SHUTDOWN]
```

---

## Component Design

### 1. Docker Image (`/Dockerfile`)

**Purpose**: Lightweight container with ComfyUI code and handler logic

**Design Principles**:
- Minimal layers for fast rebuilds
- Only handler dependencies (main venv on network volume)
- GPU optimization environment variables
- No model files (network volume only)

**Size Target**: 3GB (vs 10GB+ with embedded venv)

**Layer Structure**:
```dockerfile
Layer 1: Base image (runpod/pytorch:2.4.0-py3.11-cuda12.1.1)
Layer 2: System dependencies (git, ffmpeg, etc.) - 500MB
Layer 3: ComfyUI source code - 1.5GB
Layer 4: Handler dependencies (runpod, boto3) - 200MB
Layer 5: Handler scripts - 100KB
Total: ~2.7GB
```

**Environment Variables**:
- `CUDA_MODULE_LOADING=LAZY` - Reduce startup time
- `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` - Memory optimization
- `PYTHONUNBUFFERED=1` - Real-time logging

---

### 2. Network Volume Structure

**Mount Point**: `/workspace`

**Directory Layout**:
```
/workspace/
├── models/                          # 65GB - Model files
│   ├── unet/                        # 57GB - Diffusion models
│   │   ├── Wan2.2-I2V-A14B-HighNoise-Q8_0.gguf   (14GB)
│   │   ├── Wan2.2-I2V-A14B-LowNoise-Q8_0.gguf    (14GB)
│   │   ├── Wan2.2-T2V-A14B-HighNoise-Q8_0.gguf   (14GB)
│   │   └── Wan2.2-T2V-A14B-LowNoise-Q8_0.gguf    (14GB)
│   ├── text_encoders/               # 3.8GB - Text encoders
│   │   └── umt5-xxl-encoder-Q5_K_S.gguf
│   ├── vae/                         # 242MB - VAE models
│   │   └── wan_2.1_vae.safetensors
│   ├── loras/                       # 4GB - LoRA adaptations
│   │   ├── Wan2.2-Lightning_T2V-A14B-4steps-lora_HIGH_fp16.safetensors
│   │   ├── Wan2.2-Lightning_T2V-A14B-4steps-lora_LOW_fp16.safetensors
│   │   ├── Wan2.2-Lightning_I2V-A14B-4steps-lora_HIGH_fp16.safetensors
│   │   ├── Wan2.2-Lightning_I2V-A14B-4steps-lora_LOW_fp16.safetensors
│   │   ├── Wan2.2-Lightning_T2V-v1.1-A14B-4steps-lora_HIGH_fp16.safetensors
│   │   ├── Wan2.2-Lightning_T2V-v1.1-A14B-4steps-lora_LOW_fp16.safetensors
│   │   ├── Wan2.1_T2V_14B_FusionX_LoRA.safetensors
│   │   └── Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors
│   └── upscale_models/              # 26MB - Upscalers
│       ├── 4x-ClearRealityV1.pth
│       └── RealESRGAN_x4plus_anime_6B.pth
├── venv/                            # 8GB - Python environment
│   ├── bin/
│   ├── lib/
│   └── pyvenv.cfg
├── custom_nodes/                    # ~2GB - Custom nodes
│   ├── ComfyUI-WanVideoWrapper/
│   ├── ComfyUI-GGUF/
│   ├── ComfyUI-VideoHelperSuite/
│   └── ... (15+ other nodes)
├── output/                          # Temporary storage
├── temp/                            # Processing temp files
└── .initialized                     # Setup completion marker
```

**Rationale for Network Volume**:
- **Persistence**: Models survive container restarts
- **Reusability**: Shared across multiple workers
- **Cost**: $10/month vs re-downloading 65GB per deployment
- **Speed**: SSD network storage faster than downloading

---

### 3. Handler Implementation (`/serverless/handler.py`)

**Architecture**: Async event-driven handler

**Core Functions**:

#### 3.1 Initialization (`init_comfyui()`)
```python
def init_comfyui():
    """One-time initialization on cold start"""
    # 1. Create minimal PromptServer (no web server)
    # 2. Initialize custom nodes asynchronously
    # 3. Create PromptExecutor with RAM_PRESSURE cache
    # 4. Return global executor instance
```

**Execution Time**: ~30 seconds on cold start, 0s on warm start

#### 3.2 Workflow Validation (`validate_workflow()`)
```python
async def validate_workflow(prompt: Dict) -> tuple[bool, Optional[str]]:
    """Validate workflow before execution"""
    # 1. Iterate through all nodes
    # 2. Validate inputs using execution.validate_inputs()
    # 3. Return (success, error_message)
```

**Validation Checks**:
- Node type exists in registry
- Required inputs provided
- Input types match expected types
- No circular dependencies

#### 3.3 Workflow Execution (`execute_workflow()`)
```python
async def execute_workflow(prompt, prompt_id, executor, server):
    """Execute ComfyUI workflow without queue system"""
    # 1. Validate workflow
    # 2. Call executor.execute_async() directly (bypass queue!)
    # 3. Check executor.success status
    # 4. Return results or error
```

**Key Difference from Standard ComfyUI**:
- ❌ NO `PromptQueue.put()` (thread-based queue)
- ✅ Direct `execute_async()` call (immediate execution)
- ⏱️ Saves 2-3 seconds per request

#### 3.4 Output Handling (`find_output_files()`)
```python
def find_output_files(prompt_id: str) -> List[Path]:
    """Find generated output files for this prompt"""
    # 1. Scan /workspace/output for recent files
    # 2. Filter by modification time (last 5 minutes)
    # 3. Support: mp4, avi, mov, webm, png, jpg, jpeg, webp
    # 4. Sort by most recent first
```

**File Discovery Strategy**:
- Time-based (not prompt_id-based for compatibility)
- Handles multiple output formats
- Robust to workflow variations

#### 3.5 S3 Upload (`upload_to_s3()`)
```python
def upload_to_s3(file_path: Path, prompt_id: str) -> Optional[str]:
    """Upload file to S3/R2 and return public URL"""
    # 1. Generate S3 key: {prompt_id}/{filename}
    # 2. Upload with correct Content-Type
    # 3. Return public URL (custom domain or endpoint URL)
    # 4. Handle errors gracefully (retry logic)
```

**S3 Configuration**:
- Supports Cloudflare R2 and AWS S3
- Custom domain support via `R2_PUBLIC_URL`
- Automatic Content-Type detection
- 3 retry attempts with exponential backoff

#### 3.6 Main Handler (`handler_async()`)
```python
async def handler_async(job):
    """Main async handler function"""
    # 1. Parse workflow JSON
    # 2. Execute workflow
    # 3. Find output files
    # 4. Upload to S3
    # 5. Cleanup local files
    # 6. Return URLs + metadata
```

**Response Format**:
```json
{
  "success": true,
  "prompt_id": "job123_1234567890",
  "outputs": [
    {
      "filename": "video_001.mp4",
      "url": "https://cdn.example.com/job123_1234567890/video_001.mp4",
      "size": 52428800,
      "type": "video/mp4"
    }
  ],
  "duration": 45.2,
  "message": "Generated 1 outputs"
}
```

**Error Response**:
```json
{
  "error": "Validation failed for node 5: Invalid input type",
  "details": {...},
  "duration": 2.1
}
```

---

### 4. Warmup Script (`/serverless/warmup.py`)

**Purpose**: Reduce cold start latency by preloading common models

**Strategy**: Preload models used in 100% of workflows

**Models to Preload**:
1. **VAE** (242MB) - Required for all image/video generation
2. **T5 Text Encoder** (3.8GB) - Required for all text-conditioned generation

**Models NOT Preloaded**:
- **UNET** (14GB each) - Workflow-specific (T2V vs I2V, High vs Low noise)
- **LoRAs** (585MB each) - Optional, user-selectable

**VRAM Allocation**:
- Warmup: 4GB (VAE + T5)
- Available for UNET: 20GB (24GB total - 4GB warmup)
- Peak execution: 18-20GB

**Impact**:
```
Cold start without warmup:
  Container (8s) + Init (27s) + First gen (60s) = 95s

Cold start with warmup:
  Container (8s) + Init (27s) + Warmup (18s) + First gen (20s) = 73s

Reduction: 22 seconds (23% improvement)
```

**Toggle**: `WARMUP_MODELS=true` (default enabled)

---

### 5. Network Volume Init Script (`/serverless/init_network_volume.sh`)

**Purpose**: One-time setup of network volume with all dependencies

**Execution Context**: RunPod GPU Pod with network volume attached

**Steps**:

1. **Verify Environment**
   ```bash
   # Check network volume is mounted
   # Check ComfyUI repo exists or clone it
   # Verify internet connectivity
   ```

2. **Configure Installation**
   ```bash
   export VENV_DIR="/workspace/venv"
   export MODEL_VERSION="Q8_0"
   export TORCH_VERSION="2.4.0"
   export CUDA_TAG="cu121"
   ```

3. **Run Existing Install Script**
   ```bash
   # Reuse WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh
   # Redirect models to /workspace/models
   # Redirect venv to /workspace/venv
   bash WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh
   ```

4. **Verify Installation**
   ```bash
   # Check all 4 UNET models downloaded
   # Check text encoder present
   # Check VAE present
   # Check venv functional
   ```

5. **Create Marker File**
   ```bash
   # Write .initialized with timestamp
   # Prevents accidental re-initialization
   ```

**Execution Time**: 30-40 minutes (depends on network speed)

**Storage Usage**:
- Models: 65GB
- Venv: 8GB
- Custom nodes: 2GB
- Total: ~75GB (leaves 25GB buffer)

---

## File Specifications

### File Structure

```
/ComfyUI_WAN/
├── Dockerfile                                 # NEW - Container definition
├── serverless/                                # NEW - Serverless components
│   ├── handler.py                            # NEW - Main handler logic
│   ├── warmup.py                             # NEW - Model preloading
│   ├── init_network_volume.sh                # NEW - Volume setup
│   ├── build.sh                              # NEW - Build automation
│   ├── runpod_template.json                  # NEW - Endpoint config
│   ├── docker-compose.test.yml               # NEW - Local testing
│   ├── test_handler.py                       # NEW - Unit tests
│   ├── logger.py                             # NEW - Structured logging
│   └── .env.example                          # NEW - Env var template
├── WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh       # EXISTING - Reused for init
├── main.py                                    # EXISTING - Reference only
├── server.py                                  # EXISTING - Reference only
├── execution.py                               # EXISTING - Used by handler
└── nodes.py                                   # EXISTING - Used by handler
```

### Detailed File Specifications

#### `/Dockerfile` (NEW - 50 lines)

**Base Image**: `runpod/pytorch:2.4.0-py3.11-cuda12.1.1-devel-ubuntu22.04`

**Key Sections**:
1. System dependencies (git, ffmpeg, etc.)
2. ComfyUI code copy
3. Handler dependencies (runpod, boto3, aiofiles)
4. Handler scripts copy
5. Environment variables
6. CMD instruction

**Build Time**: 5-8 minutes
**Image Size**: ~3GB

#### `/serverless/handler.py` (NEW - 400 lines)

**Imports**:
```python
import runpod
import asyncio
import json
import sys
import boto3
from pathlib import Path
import folder_paths
import execution
import nodes
import comfy.model_management
```

**Key Classes**: None (functional design)

**Key Functions**:
- `init_s3_client()` - 20 lines
- `init_comfyui()` - 40 lines
- `validate_workflow()` - 30 lines
- `execute_workflow()` - 50 lines
- `find_output_files()` - 30 lines
- `upload_to_s3()` - 40 lines
- `cleanup_outputs()` - 20 lines
- `handler_async()` - 80 lines
- `handler()` - 5 lines (sync wrapper)
- `__main__` block - 30 lines

**Error Handling**: Try-except at each level with structured error responses

#### `/serverless/warmup.py` (NEW - 80 lines)

**Purpose**: Optional model preloading

**Functions**:
- `warmup_models()` - Main async function

**Models Loaded**:
- VAE via `VAELoader().load_vae()`
- T5 via `DualCLIPLoader().load_clip()`

**VRAM Reporting**: Shows usage after warmup

#### `/serverless/init_network_volume.sh` (NEW - 150 lines)

**Usage**: `bash init_network_volume.sh`

**Sections**:
1. Configuration (env vars)
2. Directory creation
3. ComfyUI cloning
4. Install script execution
5. Model verification
6. Marker file creation

**Idempotency**: Checks `.initialized` marker, skips if exists

#### `/serverless/build.sh` (NEW - 30 lines)

**Usage**: `bash build.sh [tag]`

**Actions**:
1. Build Docker image with platform linux/amd64
2. Tag with version
3. Push to registry

**Variables**:
- `REGISTRY` - Docker registry URL
- `IMAGE_NAME` - Image name
- `TAG` - Version tag (default: latest)

#### `/serverless/runpod_template.json` (NEW - 80 lines)

**Format**: RunPod template JSON

**Key Fields**:
- `dockerImage` - Full image URL
- `gpuTypeId` - "NVIDIA RTX 4090"
- `minWorkers` - 0 (critical!)
- `maxWorkers` - 3
- `volumeMountPath` - "/workspace"
- `env` - Array of environment variables

---

## Deployment Strategy

### Phase 1: Preparation (Local)

1. **Create serverless directory**
   ```bash
   mkdir -p /Users/travissmith/Projects/ComfyUI_WAN/serverless
   ```

2. **Write all serverless files**
   - handler.py
   - warmup.py
   - init_network_volume.sh
   - build.sh
   - runpod_template.json
   - docker-compose.test.yml

3. **Create Dockerfile at project root**

4. **Test locally** (optional)
   ```bash
   cd serverless
   docker-compose -f docker-compose.test.yml up
   ```

### Phase 2: Network Volume Initialization

1. **Launch RunPod GPU Pod**
   - GPU: Any (RTX 3060 sufficient for init)
   - Attach network volume (100GB)
   - SSH access enabled

2. **Upload init script**
   ```bash
   scp serverless/init_network_volume.sh user@pod:/workspace/
   ```

3. **Run initialization**
   ```bash
   ssh user@pod
   cd /workspace
   bash init_network_volume.sh
   # Wait 30-40 minutes
   ```

4. **Verify completion**
   ```bash
   cat /workspace/.initialized
   ls -lh /workspace/models/unet/  # Should show 4 GGUF files
   ```

5. **Stop GPU Pod** (keep network volume)

### Phase 3: Docker Image Build

1. **Build image**
   ```bash
   cd /Users/travissmith/Projects/ComfyUI_WAN
   bash serverless/build.sh v1.0.0
   ```

2. **Verify image size**
   ```bash
   docker images | grep comfyui-wan-serverless
   # Should be ~3GB
   ```

3. **Push to registry**
   ```bash
   docker push your-registry/comfyui-wan-serverless:v1.0.0
   ```

### Phase 4: Serverless Endpoint Creation

1. **Access RunPod Dashboard**
   - Navigate to Serverless → Endpoints
   - Click "New Endpoint"

2. **Configure endpoint**
   - Name: `comfyui-wan-serverless`
   - Template: Upload `runpod_template.json`
   - Network Volume: Select initialized volume
   - Docker Image: `your-registry/comfyui-wan-serverless:v1.0.0`

3. **Set environment variables**
   ```
   R2_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com
   R2_ACCESS_KEY=<your-key>
   R2_SECRET_KEY=<your-secret>
   R2_BUCKET=comfyui-outputs
   R2_PUBLIC_URL=https://outputs.yourdomain.com
   WARMUP_MODELS=true
   CACHE_RAM=16.0
   ```

4. **Review scaling settings**
   - Min Workers: 0 ✅
   - Max Workers: 3
   - Idle Timeout: 30s
   - Execution Timeout: 900s

5. **Deploy endpoint**

### Phase 5: Testing

1. **Get endpoint details**
   ```bash
   export ENDPOINT_ID=<your-endpoint-id>
   export API_KEY=<your-api-key>
   ```

2. **Test cold start**
   ```bash
   curl -X POST https://api.runpod.ai/v2/$ENDPOINT_ID/run \
     -H "Authorization: Bearer $API_KEY" \
     -H "Content-Type: application/json" \
     -d @test_t2v_workflow.json
   ```

3. **Monitor logs**
   - Check RunPod dashboard logs
   - Verify cold start time < 65s
   - Check VRAM usage < 22GB

4. **Test warm start**
   ```bash
   # Send second request within 30 seconds
   curl -X POST https://api.runpod.ai/v2/$ENDPOINT_ID/run \
     -H "Authorization: Bearer $API_KEY" \
     -H "Content-Type: application/json" \
     -d @test_i2v_workflow.json
   ```

5. **Verify outputs**
   - Check S3 bucket for uploaded files
   - Verify public URLs are accessible
   - Confirm video/image quality

### Phase 6: Production Monitoring

1. **Set up monitoring**
   - RunPod dashboard metrics
   - S3 bucket analytics
   - Cost tracking

2. **Configure alerts**
   - Execution failures > 5%
   - Cold start > 90s
   - VRAM usage > 22GB
   - S3 upload failures

3. **Regular maintenance**
   - Monthly model updates
   - Docker image rebuilds
   - Network volume cleanup

---

## Testing Plan

### Local Testing (Docker Compose)

**Setup**:
```bash
cd serverless
docker-compose -f docker-compose.test.yml up
```

**Test Cases**:
1. Handler initialization
2. Workflow validation (valid + invalid)
3. Execution flow (T2V + I2V)
4. S3 upload (with mock credentials)
5. Error handling (missing models, invalid inputs)

### Integration Testing (Staging Endpoint)

**Cold Start Test**:
```bash
# Start with no active workers
# Send request
# Measure: Container → First response time
# Target: < 65 seconds
```

**Warm Start Test**:
```bash
# Send request within idle timeout window
# Measure: Request → Response time
# Target: < 30 seconds
```

**Memory Management Test**:
```bash
# Send 10 consecutive requests
# Monitor VRAM usage after each
# Verify: No memory leaks (stays < 22GB)
```

**Concurrent Request Test**:
```bash
# Send 5 requests simultaneously
# Verify: Auto-scales to maxWorkers
# Check: All complete successfully
```

**S3 Upload Test**:
```bash
# Execute workflow
# Verify: Files uploaded to correct S3 path
# Check: Public URLs accessible
# Confirm: Local files deleted
```

**Failure Recovery Test**:
```bash
# Send invalid workflow
# Verify: Proper error response
# Check: Handler recovers (next request succeeds)
```

### Load Testing (Production)

**Sustained Load Test**:
```bash
# Send 100 requests over 1 hour
# Monitor: Success rate, latency distribution
# Check: Cost tracking accuracy
```

**Burst Test**:
```bash
# Send 20 requests in 1 minute
# Verify: Auto-scaling response
# Check: Queue handling
```

**Cost Validation Test**:
```bash
# Run for 24 hours with idle periods
# Verify: Idle cost = $0
# Calculate: Cost per request
```

---

## Cost Analysis

### Cost Components

| Component | Unit Cost | Monthly Cost (10 req/day) |
|-----------|-----------|--------------------------|
| Network Volume (100GB SSD) | $0.10/GB/month | $10.00 |
| Compute (RTX 4090) | $0.60/hour | $15.00 (25 hours) |
| S3 Storage (1GB) | $0.023/GB/month | $0.02 |
| S3 Egress (20GB) | $0.09/GB | $1.80 |
| **Total** | | **$26.82** |

### Cost Comparison

| Scenario | Persistent Pod | Serverless | Savings |
|----------|---------------|------------|---------|
| 1 request/day | $360/month | $15/month | **95.8%** |
| 10 requests/day | $360/month | $27/month | **92.5%** |
| 50 requests/day | $360/month | $90/month | **75.0%** |
| 24/7 usage | $360/month | $432/month | **-20%** ❌ |

**Break-Even Point**: ~40 requests/day (6 hours/day)

### Optimization Opportunities

1. **Spot Instances**: 30-50% discount
   - Monthly cost: $27 → $18
   - Risk: Occasional interruptions

2. **Smaller GPU** (if Q5_K_S quantization):
   - RTX A5000 (24GB): $0.50/hour (vs $0.60)
   - Saves $2.50/month

3. **Reduce Network Volume**:
   - 50GB instead of 100GB
   - Saves $5/month
   - Risk: Less temp space

4. **Aggressive Output Cleanup**:
   - Delete from S3 after 7 days
   - Saves $0.50/month (marginal)

---

## Risk Management

### Risk 1: Cold Start > 90 seconds

**Probability**: Medium
**Impact**: High (user experience)

**Mitigation**:
- Enable `WARMUP_MODELS=true` (default)
- Verify network volume is SSD (check in dashboard)
- Use `CUDA_MODULE_LOADING=LAZY`
- Optimize Docker image layers

**Fallback**:
- Increase `idleTimeout` to 60s (keep workers warm longer)
- Set `minWorkers=1` (eliminate cold starts, increases cost)

### Risk 2: VRAM Out of Memory

**Probability**: Low
**Impact**: Critical (execution failure)

**Mitigation**:
- Use RAM_PRESSURE cache strategy
- Q8_0 quantization (vs FP16)
- Block swapping enabled in WanVideoWrapper
- Monitor VRAM usage via logs

**Fallback**:
- Switch to Q5_K_S quantization (saves 30% VRAM)
- Reduce `CACHE_RAM` from 16GB to 12GB
- Disable warmup (saves 4GB VRAM)

### Risk 3: S3 Upload Failures

**Probability**: Low
**Impact**: Medium (outputs not delivered)

**Mitigation**:
- Retry logic (3 attempts with exponential backoff)
- Pre-flight credential validation
- Fallback to local storage if S3 unavailable
- Monitor upload success rate

**Fallback**:
- Store outputs on network volume
- Return direct download links (temporary)
- Manual S3 upload batch job

### Risk 4: Network Volume Corruption

**Probability**: Very Low
**Impact**: Critical (complete failure)

**Mitigation**:
- `.initialized` marker file (detect incomplete setup)
- Model checksum validation
- Re-initialization script (automated recovery)
- Periodic backups to S3

**Fallback**:
- Keep backup of initialized volume snapshot
- Re-run `init_network_volume.sh` (30-40 min recovery)

### Risk 5: Cost Overrun

**Probability**: Medium
**Impact**: Medium (budget)

**Mitigation**:
- Set `maxWorkers=3` (hard limit)
- Monitor daily costs in RunPod dashboard
- Alert if daily cost > $2
- Auto-stop endpoint if monthly > $50

**Fallback**:
- Reduce `maxWorkers` to 1
- Increase `idleTimeout` (reduce churn)
- Switch to spot instances

### Risk 6: Model Loading Failures

**Probability**: Low
**Impact**: High (execution failure)

**Mitigation**:
- Verify all models exist during warmup
- Graceful degradation (skip warmup if models missing)
- Detailed error messages with model paths
- Health check endpoint

**Fallback**:
- Re-download missing models on-the-fly
- Provide model verification CLI tool
- Enable debug logging for troubleshooting

---

## Success Metrics

### Performance Metrics

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Cold Start Latency (P95) | < 65s | RunPod logs, timestamp analysis |
| Warm Start Latency (P95) | < 30s | RunPod logs, timestamp analysis |
| Execution Success Rate | > 98% | Failed jobs / Total jobs |
| S3 Upload Success Rate | > 99% | Failed uploads / Total uploads |
| Peak VRAM Usage | < 22GB | CUDA memory logs |

### Cost Metrics

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Monthly Cost (10 req/day) | < $30 | RunPod billing dashboard |
| Idle Cost | $0/hour | Verify minWorkers=0, no charges when idle |
| Cost Per Request | < $0.10 | Total monthly cost / request count |
| Network Volume Cost | $10/month | 100GB × $0.10/GB |

### Reliability Metrics

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Uptime | > 99.5% | Endpoint availability monitoring |
| Mean Time to Recovery | < 5 min | Incident response logs |
| Error Rate | < 2% | Failed requests / Total requests |

---

## Next Steps

1. ✅ **Design Complete** - This document
2. ⏳ **Implementation** - Create all serverless files
3. ⏳ **Local Testing** - Docker Compose validation
4. ⏳ **Network Volume Init** - Run initialization script
5. ⏳ **Docker Build** - Build and push image
6. ⏳ **Endpoint Creation** - Deploy to RunPod
7. ⏳ **Integration Testing** - Verify cold/warm starts
8. ⏳ **Production Deployment** - Enable endpoint
9. ⏳ **Monitoring Setup** - Configure alerts
10. ⏳ **Documentation** - User guide and API docs

---

## Appendix A: Example Workflows

### Text-to-Video (T2V) Workflow

```json
{
  "workflow": {
    "1": {
      "class_type": "WanTextEncoderLoader",
      "inputs": {
        "text_encoder": "umt5-xxl-encoder-Q5_K_S.gguf",
        "type": "gguf"
      }
    },
    "2": {
      "class_type": "CLIPTextEncode",
      "inputs": {
        "text": "A cat playing piano in a jazz club",
        "clip": ["1", 0]
      }
    },
    "3": {
      "class_type": "UnetLoaderGGUF",
      "inputs": {
        "unet_name": "Wan2.2-T2V-A14B-HighNoise-Q8_0.gguf"
      }
    },
    "4": {
      "class_type": "VAELoader",
      "inputs": {
        "vae_name": "wan_2.1_vae.safetensors"
      }
    },
    "5": {
      "class_type": "KSampler",
      "inputs": {
        "model": ["3", 0],
        "positive": ["2", 0],
        "steps": 50,
        "cfg": 7.0
      }
    },
    "6": {
      "class_type": "VAEDecode",
      "inputs": {
        "samples": ["5", 0],
        "vae": ["4", 0]
      }
    },
    "7": {
      "class_type": "SaveVideo",
      "inputs": {
        "images": ["6", 0],
        "filename_prefix": "wan_t2v"
      }
    }
  }
}
```

### Image-to-Video (I2V) Workflow

```json
{
  "workflow": {
    "1": {
      "class_type": "LoadImage",
      "inputs": {
        "image": "input_frame.png"
      }
    },
    "2": {
      "class_type": "WanTextEncoderLoader",
      "inputs": {
        "text_encoder": "umt5-xxl-encoder-Q5_K_S.gguf"
      }
    },
    "3": {
      "class_type": "UnetLoaderGGUF",
      "inputs": {
        "unet_name": "Wan2.2-I2V-A14B-LowNoise-Q8_0.gguf"
      }
    },
    "4": {
      "class_type": "VAEEncode",
      "inputs": {
        "pixels": ["1", 0],
        "vae": ["4", 0]
      }
    },
    "5": {
      "class_type": "KSampler",
      "inputs": {
        "model": ["3", 0],
        "latent_image": ["4", 0],
        "steps": 30
      }
    }
  }
}
```

---

## Appendix B: Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `R2_ENDPOINT` | Yes | None | Cloudflare R2 endpoint URL |
| `R2_ACCESS_KEY` | Yes | None | R2 access key ID |
| `R2_SECRET_KEY` | Yes | None | R2 secret access key |
| `R2_BUCKET` | Yes | `comfyui-outputs` | R2 bucket name |
| `R2_PUBLIC_URL` | No | None | Custom domain for public URLs |
| `CACHE_RAM` | No | `16.0` | RAM pressure threshold (GB) |
| `WARMUP_MODELS` | No | `true` | Enable model preloading |
| `CUDA_MODULE_LOADING` | No | `LAZY` | CUDA module loading strategy |
| `PYTORCH_CUDA_ALLOC_CONF` | No | `expandable_segments:True` | PyTorch memory config |

---

## Appendix C: Troubleshooting Commands

### Check Network Volume Mount
```bash
ls -la /workspace
cat /workspace/.initialized
```

### Verify Models Exist
```bash
ls -lh /workspace/models/unet/
ls -lh /workspace/models/text_encoders/
ls -lh /workspace/models/vae/
```

### Test Venv Activation
```bash
source /workspace/venv/bin/activate
python --version
pip list | grep torch
```

### Check VRAM Usage
```bash
nvidia-smi
```

### Test S3 Connection
```bash
aws s3 ls s3://$R2_BUCKET --endpoint-url=$R2_ENDPOINT
```

### View Handler Logs
```bash
# In RunPod dashboard: Logs tab
# Look for:
# - "ComfyUI initialized successfully"
# - "Handler ready, waiting for jobs..."
# - VRAM usage after warmup
```

---

**END OF DESIGN DOCUMENT**
