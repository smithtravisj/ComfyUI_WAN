# RunPod Volume Initialization Commands

Quick reference for initializing your RunPod network volume with ComfyUI WAN 2.2.

## Prerequisites

- ✅ RunPod network volume created (100GB+)
- ✅ Code pushed to GitHub (smithtravisj/ComfyUI_WAN)

---

## Step 1: Start GPU Pod

1. Go to RunPod Console → **GPU Pods**
2. Click **Deploy** → **GPU Cloud**
3. Configure:
   - **GPU**: RTX 4090, A5000, or A6000 (cheapest available)
   - **Container Image**: `runpod/pytorch:2.1.0-py3.10-cuda12.1.0-devel-ubuntu22.04`
   - **Volume**: Attach your network volume to `/workspace`
   - **Expose Ports**: 22 (SSH)
4. Click **Deploy**
5. Wait for pod to start (~30 seconds)

---

## Step 2: Connect to Pod Terminal

Click **Connect** → **Start Web Terminal**

---

## Step 3: Run Initialization (Copy & Paste)

```bash
# Navigate to workspace
cd /workspace

# Clone your repository
git clone https://github.com/smithtravisj/ComfyUI_WAN.git

# Navigate into repository
cd ComfyUI_WAN

# Make initialization script executable
chmod +x serverless/init_network_volume.sh

# Run initialization (30-40 minutes)
bash serverless/init_network_volume.sh
```

---

## What Happens During Initialization

### Phase 1: Directory Structure (~5 seconds)
```
/workspace/
├── models/
│   ├── unet/
│   ├── text_encoders/
│   ├── vae/
│   └── loras/
├── venv/
├── output/
└── temp/
```

### Phase 2: Python Environment (~5 minutes)
- Creates virtual environment at `/workspace/venv`
- Installs PyTorch 2.4.0 + CUDA 12.1
- Installs all ComfyUI dependencies
- Installs serverless handler dependencies

### Phase 3: Model Downloads (~20-30 minutes, ~65GB)
Downloads from Hugging Face:
- **UNET Models (Q8_0)**: 4 models × ~12GB = ~48GB
  - Wan2.2-T2V-A14B-HighNoise-Q8_0.gguf
  - Wan2.2-T2V-A14B-LowNoise-Q8_0.gguf
  - Wan2.2-I2V-A14B-HighNoise-Q8_0.gguf
  - Wan2.2-I2V-A14B-LowNoise-Q8_0.gguf
- **Text Encoder**: umt5-xxl-encoder-Q5_K_S.gguf (~4GB)
- **VAE**: wan_2.1_vae.safetensors (~242MB)
- **LoRAs**: 8 Lightning LoRA files (~8GB total)
- **Upscalers**: 2 upscale models (~200MB)

### Phase 4: Custom Nodes (~3-5 minutes)
Clones and installs dependencies for 18 custom nodes:
- ComfyUI-Manager (node management)
- ComfyUI-GGUF (GGUF model support)
- ComfyUI-WanVideoWrapper (Wan 2.2 integration)
- ComfyUI-VideoHelperSuite (video processing)
- ComfyUI-KJNodes (utilities)
- ComfyUI-Impact-Pack (image processing)
- And 12 more...

### Phase 5: Verification (~10 seconds)
- Checks all critical models exist
- Validates Python environment
- Reports disk usage
- Creates `.initialized` marker file

---

## Expected Output

```
========================================================================
ComfyUI WAN 2.2 Network Volume Initialization
========================================================================

ℹ Network volume: /workspace
ℹ Available space: 100GB
ℹ Estimated time: 30-40 minutes

========================================================================
Phase 1: Creating Directory Structure
========================================================================

✓ Created: /workspace/models
✓ Created: /workspace/models/unet
✓ Created: /workspace/models/text_encoders
...

========================================================================
Phase 2: Installing Python Virtual Environment
========================================================================

ℹ Creating virtual environment at /workspace/venv
✓ Virtual environment created
✓ Virtual environment activated
...

========================================================================
Phase 3: Downloading Models (~65GB, 15-20 minutes)
========================================================================

ℹ Running model download script from /workspace/ComfyUI_WAN...
 • downloading umt5-xxl-encoder-Q5_K_S.gguf
████████████████████████████████████████ 100%
 • downloading wan_2.1_vae.safetensors
████████████████████████████████████████ 100%
...

========================================================================
Phase 4: Custom Nodes Installation
========================================================================

✓ Custom nodes installed by WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh
ℹ Total custom nodes installed: 18

========================================================================
Phase 5: Verifying Installation
========================================================================

✓ Found: wan_2.1_vae.safetensors (242M)
✓ Found: umt5-xxl-encoder-Q5_K_S.gguf (4.0G)
✓ Found 4 UNET model(s)
✓ Found 8 LoRA file(s)
✓ Python venv: Python 3.11.x
ℹ Total network volume usage: 68G

========================================================================
Initialization Complete!
========================================================================

✓ Network volume ready for serverless deployment
✓ Total time: 32m 15s
✓ Space used: 68G

ℹ Next steps:
  1. Stop this RunPod pod (network volume persists)
  2. Build Docker image: cd serverless && ./build.sh latest --github
  3. Create serverless endpoint with network volume attached
  4. Test with example workflow
```

---

## Step 4: Verify Installation

After script completes, verify everything is in place:

```bash
# Check models directory size
du -sh /workspace/models
# Expected: ~65G

# List critical models
ls -lh /workspace/models/vae/wan_2.1_vae.safetensors
ls -lh /workspace/models/text_encoders/umt5-xxl-encoder-Q5_K_S.gguf
ls -lh /workspace/models/unet/*.gguf | wc -l
# Expected: 4 UNET models

# Check Python environment
source /workspace/venv/bin/activate
python --version
# Expected: Python 3.11.x

python -c "import torch; print(f'PyTorch: {torch.__version__}')"
# Expected: PyTorch: 2.4.0+cu121

# Check initialization marker
cat /workspace/.initialized
# Should show initialization details
```

---

## Step 5: Stop Pod

Once verification passes:

1. Exit the terminal
2. Go to RunPod Console
3. Click **Stop** on the GPU pod
4. **Keep the network volume** - it now contains all your models

**Important**: The network volume persists even after stopping the pod. You only pay for storage (~$10/month per 100GB), not GPU time.

---

## Troubleshooting

### Error: "Installation script not found"

**Cause**: Repository not cloned correctly or wrong directory

**Fix**:
```bash
cd /workspace
ls -la  # Should show ComfyUI_WAN directory
cd ComfyUI_WAN
ls -la  # Should show WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh
```

### Error: "Insufficient space on network volume"

**Cause**: Network volume too small

**Fix**:
- Minimum: 100GB
- Recommended: 150GB
- Resize volume in RunPod console if needed

### Error: Model downloads failing

**Cause**: Network issues or Hugging Face rate limiting

**Fix**:
- Wait a few minutes and re-run the script
- Script will skip already-downloaded files
- Check Hugging Face status: https://status.huggingface.co

### Error: Custom node installation failures

**Cause**: Some nodes may have dependency conflicts (non-critical)

**Fix**:
- Script continues on node failures
- Core nodes (GGUF, WanVideoWrapper) must succeed
- Optional nodes can be installed later via ComfyUI-Manager

---

## Costs

### Initialization Phase (One-Time)
- **GPU Pod**: RTX 4090 @ ~$0.34/hour × 0.5-0.7 hours = **$0.17-0.24**
- **Network Volume Storage**: ~70GB × ~$0.10/GB/month = **~$7/month** (ongoing)

### Serverless Deployment (After Initialization)
- **Cold Start**: ~8-12 seconds (with warmup optimization)
- **Per Request**: ~$0.34/hour × (execution time in hours)
  - Example: 30-second video generation = $0.34 × (30/3600) = **~$0.003**
- **Network Volume Storage**: **~$7/month** (same volume, reused)

---

## Next Steps

After initialization completes and you've stopped the GPU pod:

1. **Build Docker Image** (if not done already):
   - Use GitHub Actions (recommended) - see [QUICKSTART.md](QUICKSTART.md)
   - Or build locally - see [README.md](README.md)

2. **Deploy Serverless Endpoint**:
   - Follow [RUNPOD_DEPLOYMENT.md](RUNPOD_DEPLOYMENT.md) Phase 3
   - Use the initialized network volume
   - Configure endpoint with `runpod_template.json`

3. **Test Deployment**:
   - Run test workflow from `examples/t2v_simple.json`
   - Verify output videos are generated
   - Check S3 upload functionality

---

## Re-initialization

If you need to reinitialize the volume (e.g., after updates):

```bash
# Start GPU pod with same network volume attached
cd /workspace/ComfyUI_WAN

# Pull latest changes
git pull origin master

# Re-run initialization
bash serverless/init_network_volume.sh
```

The script will detect existing files and ask if you want to reinitialize. Answer:
- **`y`** to delete and re-download everything (full reset)
- **`n`** to keep existing files and exit (skip initialization)

---

**Status**: Ready for initialization
**Estimated Time**: 30-40 minutes
**Cost**: ~$0.20 (one-time)
