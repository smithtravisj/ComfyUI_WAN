# Local Testing Guide for ComfyUI WAN 2.2 Serverless

Complete guide for testing the serverless implementation locally before deploying to RunPod.

---

## Prerequisites

### Required Software

1. **Docker Desktop** with GPU support
   - Mac: Docker Desktop 4.25+ with Rosetta 2 emulation
   - Linux: Docker Engine 20.10+ with `nvidia-docker2`
   - Windows: Docker Desktop with WSL2 backend

2. **NVIDIA GPU** (for full testing)
   - 24GB+ VRAM (RTX 4090, A100, etc.)
   - CUDA 12.1+ drivers
   - For testing without GPU: Use CPU mode (slow)

3. **Python 3.11+** (for test scripts)
   ```bash
   python3 --version  # Should be 3.11 or higher
   ```

4. **Git** and **Git LFS** (for cloning models)
   ```bash
   git lfs install
   ```

### System Requirements

- **Disk Space**: 100GB+ for models and workspace
- **RAM**: 16GB+ system RAM
- **Network**: Fast internet for model downloads (~65GB)

---

## Setup Process

### Step 1: Initialize Network Volume Simulation

Since we're testing locally, we'll create a local workspace directory that simulates the RunPod network volume.

```bash
# Create local workspace directory
mkdir -p workspace

# Set workspace path
export WORKSPACE_PATH="$(pwd)/workspace"
echo "WORKSPACE_PATH=$WORKSPACE_PATH"
```

**Important**: This workspace will be ~80GB after initialization. Ensure you have sufficient disk space.

### Step 2: Run Network Volume Initialization

The initialization script will download models and set up the environment. This takes **30-40 minutes**.

```bash
# Make sure you're in the ComfyUI_WAN directory
cd /path/to/ComfyUI_WAN

# Run initialization script with local workspace
WORKSPACE=/Users/travissmith/Projects/ComfyUI_WAN/workspace \
COMFYUI_DIR=$(pwd) \
bash serverless/init_network_volume.sh
```

**What this does**:
- Creates directory structure in `workspace/`
- Downloads ~65GB of models to `workspace/models/`
- Installs Python venv at `workspace/venv/`
- Installs 18 custom nodes
- Creates `.initialized` marker file

**Expected output**:
```
======================================================================
ComfyUI WAN 2.2 Network Volume Initialization
======================================================================

Network volume: /Users/travissmith/Projects/ComfyUI_WAN/workspace
Available space: 150GB
Estimated time: 30-40 minutes

...

✓ Initialization Complete!
Total time: 35m 24s
Space used: 78GB
```

### Step 3: Configure Environment Variables

Create a `.env` file for local testing:

```bash
cd serverless
cp .env.example .env
```

Edit `.env` with your values:

```bash
# Required: Local workspace path
WORKSPACE_PATH=/Users/travissmith/Projects/ComfyUI_WAN/workspace

# Optional: S3/R2 for output uploads (can skip for local testing)
R2_ENDPOINT=https://YOUR_ACCOUNT.r2.cloudflarestorage.com
R2_ACCESS_KEY=your_access_key
R2_SECRET_KEY=your_secret_key
R2_BUCKET=comfyui-outputs

# Feature toggles
WARMUP_MODELS=true
CLEANUP_OUTPUTS=false  # Keep outputs locally for testing
```

---

## Testing Methods

### Method 1: Docker Compose (Recommended)

Best for full integration testing with GPU support.

#### Build and Start

```bash
cd serverless

# Build the image
docker compose -f docker-compose.test.yml build

# Start the container
docker compose -f docker-compose.test.yml up -d

# View logs
docker compose -f docker-compose.test.yml logs -f
```

#### Run Test Workflows

```bash
# Minimal validation (tests VAE + text encoder only)
python test_handler.py --local --workflow examples/minimal_validation.json

# Simple T2V (full generation, ~90-120s)
python test_handler.py --local --workflow examples/t2v_simple.json

# Lightning T2V (4-step, ~30-40s)
python test_handler.py --local --workflow examples/t2v_lightning.json
```

#### Monitor Container

```bash
# Container logs
docker compose -f docker-compose.test.yml logs -f comfyui-serverless

# GPU usage
docker exec comfyui-test nvidia-smi

# Container shell
docker exec -it comfyui-test bash
```

#### Stop Container

```bash
docker compose -f docker-compose.test.yml down
```

### Method 2: Direct Docker Run

For simpler testing without Docker Compose.

```bash
# Build image
docker build -t comfyui-wan-serverless:test -f Dockerfile .

# Run container
docker run --gpus all \
  -v $(pwd)/workspace:/workspace \
  -v $(pwd)/serverless/handler.py:/comfyui/handler.py \
  -e WARMUP_MODELS=true \
  -e CACHE_TYPE=RAM_PRESSURE \
  -e CACHE_RAM=16.0 \
  --name comfyui-test \
  comfyui-wan-serverless:test
```

### Method 3: Native Python (No Docker)

For development and debugging without containerization.

**Prerequisites**:
- ComfyUI dependencies installed
- CUDA environment configured
- Workspace initialized

```bash
# Activate workspace venv
source workspace/venv/bin/activate

# Install handler dependencies
pip install runpod==1.7.3 boto3==1.34.34 aiofiles==23.2.1

# Set environment
export MODELS_DIR=$(pwd)/workspace/models
export OUTPUT_DIR=$(pwd)/workspace/output
export VENV_PATH=$(pwd)/workspace/venv

# Run handler directly
cd serverless
python test_handler.py --local --workflow examples/minimal_validation.json
```

---

## Test Scenarios

### Test 1: Cold Start Performance

Verify cold start times meet target (< 65s).

```bash
# Stop container to simulate cold start
docker compose -f docker-compose.test.yml down

# Start and monitor startup time
time docker compose -f docker-compose.test.yml up -d

# Check logs for initialization timing
docker compose -f docker-compose.test.yml logs comfyui-serverless | grep "complete"
```

**Expected**:
- Container startup: ~8s
- Venv activation: ~3s
- ComfyUI init: ~12s
- Custom nodes: ~15s
- Warmup (VAE + T5): ~18s
- **Total**: ~56s ✓

### Test 2: Warm Start Performance

Verify warm start times meet target (< 30s).

```bash
# Container already running
# Run minimal workflow
time python test_handler.py --local --workflow examples/minimal_validation.json
```

**Expected**:
- Workflow validation: ~2s
- Model loading (cached): ~3s
- Execution: ~8s
- **Total**: ~13s ✓

### Test 3: VRAM Usage

Monitor VRAM usage stays within limits (< 22GB peak).

```bash
# Terminal 1: Monitor GPU
watch -n 1 'docker exec comfyui-test nvidia-smi'

# Terminal 2: Run heavy workflow
python test_handler.py --local --workflow examples/t2v_simple.json
```

**Expected VRAM**:
- After warmup: ~4GB (VAE + T5)
- During generation: ~18-20GB (UNET loaded)
- Peak: < 22GB ✓

### Test 4: Memory Leak Detection

Run multiple sequential requests to detect memory leaks.

```bash
# Run 10 consecutive requests
for i in {1..10}; do
  echo "=== Request $i ==="
  python test_handler.py --local --workflow examples/t2v_lightning.json
  sleep 5
done

# Check memory growth
docker stats comfyui-test --no-stream
```

**Expected**:
- Memory usage should stabilize
- No continuous growth
- RAM_PRESSURE cache should prevent leaks ✓

### Test 5: Output Handling

Verify outputs are generated and optionally uploaded.

```bash
# Run workflow
python test_handler.py --local --workflow examples/t2v_simple.json

# Check local outputs
ls -lh workspace/output/

# If S3/R2 configured, verify upload
# (Check test output for URLs)
```

**Expected**:
- MP4 files in `workspace/output/`
- If S3 configured: URLs in test output
- File sizes: 5-20MB per video ✓

---

## Debugging

### Issue: Container Won't Start

**Symptoms**: Container exits immediately after starting

**Check**:
```bash
# View container logs
docker compose -f docker-compose.test.yml logs

# Common issues:
# - GPU not available
# - Workspace not mounted
# - Invalid environment variables
```

**Solutions**:
```bash
# Verify GPU access
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi

# Check workspace exists
ls workspace/.initialized  # Should exist

# Validate environment
docker compose -f docker-compose.test.yml config
```

### Issue: Models Not Found

**Symptoms**: "Model file not found" errors

**Check**:
```bash
# Verify models downloaded
ls -lh workspace/models/unet/
ls -lh workspace/models/text_encoders/
ls -lh workspace/models/vae/

# Check initialization marker
cat workspace/.initialized
```

**Solutions**:
```bash
# Re-run initialization
rm workspace/.initialized
bash serverless/init_network_volume.sh

# Or manually download missing models
cd workspace/models/unet
huggingface-cli download Comfy-Org/WAN_2.2_UNET Wan2.2-T2V-A14B-HighNoise-Q8_0.gguf
```

### Issue: VRAM Out of Memory

**Symptoms**: "CUDA out of memory" errors

**Check**:
```bash
# Check available VRAM
docker exec comfyui-test nvidia-smi

# Verify model quantization (should be Q8_0, not FP16)
ls -lh workspace/models/unet/*.gguf
```

**Solutions**:
```bash
# Lower cache threshold
# Edit .env:
CACHE_RAM=14.0  # More aggressive cleanup

# Use Low Noise models (smaller)
# Edit workflow to use:
# Wan2.2-T2V-A14B-LowNoise-Q8_0.gguf

# Reduce resolution
# Edit workflow:
# "width": 640  (instead of 832)
# "height": 384  (instead of 480)
```

### Issue: Slow Generation Times

**Symptoms**: Generation takes > 2 minutes

**Check**:
```bash
# Verify GPU is being used
docker exec comfyui-test nvidia-smi

# Check CUDA configuration
docker exec comfyui-test python -c "import torch; print(torch.cuda.is_available())"
```

**Solutions**:
```bash
# Ensure warmup is enabled
# Edit .env:
WARMUP_MODELS=true

# Use Lightning LoRA for faster generation
# Use examples/t2v_lightning.json (4 steps instead of 25)

# Check for CPU fallback
docker compose -f docker-compose.test.yml logs | grep "CUDA"
```

### Issue: Handler Import Errors

**Symptoms**: "ModuleNotFoundError" in test script

**Check**:
```bash
# Verify handler.py exists
ls -l serverless/handler.py

# Check Python path
python -c "import sys; print(sys.path)"
```

**Solutions**:
```bash
# Install missing dependencies
pip install requests

# Or use test from serverless directory
cd serverless
python test_handler.py --local --workflow examples/minimal_validation.json
```

---

## Performance Benchmarks

Expected performance targets on RTX 4090:

| Scenario | Target | Acceptable | Notes |
|----------|--------|------------|-------|
| Cold Start | < 60s | < 90s | With warmup enabled |
| Warm Start | < 20s | < 30s | Cached models |
| T2V (25 steps) | < 90s | < 120s | After cold start |
| Lightning (4 steps) | < 30s | < 45s | After warm start |
| VRAM Peak | < 20GB | < 22GB | During generation |
| Memory Leak | 0% growth | < 5% per 10 requests | RAM_PRESSURE cache |

---

## Next Steps

Once local testing passes:

1. ✅ **Verify all test scenarios pass**
2. ✅ **Confirm performance meets targets**
3. ✅ **Test with your actual workflows**
4. → **Proceed to Phase 4**: Build and push Docker image
5. → **Proceed to Phase 5**: Initialize RunPod network volume
6. → **Proceed to Phase 6**: Deploy serverless endpoint
7. → **Proceed to Phase 7**: Production testing

---

## Cleanup

When done testing:

```bash
# Stop containers
docker compose -f docker-compose.test.yml down

# Remove images (optional)
docker rmi comfyui-wan-serverless:test

# Remove workspace (WARNING: deletes all models)
# rm -rf workspace/

# Keep workspace for future testing (recommended)
# Just remove outputs to save space:
rm -rf workspace/output/*
rm -rf workspace/temp/*
```

---

## Troubleshooting Checklist

Before asking for help, verify:

- [ ] Workspace initialized successfully (`.initialized` file exists)
- [ ] Models downloaded (check `workspace/models/` directories)
- [ ] GPU accessible in Docker (`nvidia-smi` works)
- [ ] Environment variables configured (`.env` file exists)
- [ ] Docker image builds without errors
- [ ] Handler dependencies installed
- [ ] Sufficient disk space (100GB+)
- [ ] Sufficient VRAM (24GB+)

---

## Support

- **Local Testing Issues**: See debugging section above
- **Model Issues**: Check `workspace/models/` contents
- **GPU Issues**: Verify nvidia-docker2 installation
- **Handler Issues**: Check `serverless/handler.py` logs
- **General Questions**: See main `serverless/README.md`

---

**Ready to test?** Start with Method 1 (Docker Compose) for the best experience!
