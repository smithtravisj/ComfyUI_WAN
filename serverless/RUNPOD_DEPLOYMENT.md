# RunPod Serverless Deployment Guide
## ComfyUI WAN 2.2 Serverless on RunPod

**Prerequisites:**
- RunPod account with billing set up
- Docker Hub account (optional, for custom images)
- R2/S3 credentials (optional, for output storage)

---

## Phase 1: Network Volume Setup (One-time, ~40 minutes)

Network volumes persist models and dependencies across serverless invocations.

### Step 1: Create Network Volume

1. Log into [RunPod](https://www.runpod.io/)
2. Navigate to **Storage → Network Volumes**
3. Click **Create Network Volume**
4. Configure:
   - **Name**: `comfyui-wan-2-2-models`
   - **Size**: 100GB minimum (recommend 150GB for safety)
   - **Region**: Choose closest to your users
5. Click **Create**
6. Note the volume ID (needed later)

**Cost**: ~$10/month for 100GB persistent storage

### Step 2: Initialize Network Volume

You need a GPU pod to download models and install dependencies.

#### 2a. Start Temporary GPU Pod

1. Navigate to **Pods**
2. Click **Deploy** → **GPU Pod**
3. Configure:
   - **GPU**: Any GPU with 24GB+ VRAM (e.g., RTX 4090, A5000)
   - **Template**: PyTorch 2.4.0 or CUDA 12.1
   - **Network Volume**: Attach the volume you created
   - **Volume Path**: `/workspace`
4. Click **Deploy**

**Cost**: ~$0.50-1.00/hour (we'll delete this pod after setup)

#### 2b. Connect to Pod

1. Wait for pod to reach "Running" status
2. Click **Connect** → **Start Web Terminal** (or use SSH)

#### 2c. Clone Repository and Run Init Script

```bash
# Clone your repository (replace with your repo URL)
cd /workspace
git clone https://github.com/YOUR_USERNAME/ComfyUI_WAN.git
cd ComfyUI_WAN

# Make init script executable
chmod +x serverless/init_network_volume.sh

# Run initialization (this takes 30-40 minutes)
bash serverless/init_network_volume.sh
```

**What this script does:**
- Creates directory structure in `/workspace`
- Downloads all models (~65GB):
  - 4 UNET models (T2V/I2V, High/Low Noise)
  - Text encoder (UMT5-XXL)
  - VAE
  - Lightning LoRAs
- Creates Python 3.11 venv with PyTorch and ComfyUI
- Installs all custom nodes and dependencies
- Creates `.initialized` marker file

**Expected output:**
```
========================================================================
ComfyUI WAN 2.2 Network Volume Initialization
========================================================================

Phase 1: Creating Directory Structure
✓ Created: /workspace/models
✓ Created: /workspace/venv
...

Phase 2: Installing Python Virtual Environment
✓ Virtual environment created
✓ pip upgraded
✓ ComfyUI requirements installed
✓ Serverless dependencies installed

Phase 3: Downloading Models (~65GB, 15-20 minutes)
✓ Downloaded: Wan2.2-T2V-A14B-HighNoise-Q8_0.gguf (12.5GB)
✓ Downloaded: Wan2.2-T2V-A14B-LowNoise-Q8_0.gguf (12.5GB)
...

========================================================================
Initialization Complete!
========================================================================
```

#### 2d. Verify Installation

```bash
# Check workspace size
du -sh /workspace
# Should show ~70-80GB

# Verify critical files
ls -lh /workspace/models/unet/*.gguf
ls -lh /workspace/venv/bin/python

# Check .initialized marker
cat /workspace/.initialized
```

#### 2e. Stop and Delete the Pod

1. Go back to RunPod dashboard
2. Click **Stop** on your pod
3. Click **Terminate** to delete it
4. **Important**: The network volume persists! Models and venv remain.

---

## Phase 2: Docker Image Preparation

You have two options:

### Option A: Use Docker Hub (Recommended)

Push your Docker image to Docker Hub so RunPod can access it.

```bash
# On your Mac, tag and push the image
docker tag comfyui-wan-serverless:test YOUR_DOCKERHUB_USERNAME/comfyui-wan-serverless:latest
docker login
docker push YOUR_DOCKERHUB_USERNAME/comfyui-wan-serverless:latest
```

### Option B: Use RunPod's Build Service

Let RunPod build from your Dockerfile.

1. Push code to GitHub/GitLab
2. In RunPod template, specify your repo URL
3. RunPod will build on their infrastructure

---

## Phase 3: Serverless Endpoint Creation

### Step 1: Create Serverless Endpoint

1. Navigate to **Serverless → Endpoints**
2. Click **Create Endpoint**
3. Configure:

**Basic Settings:**
- **Name**: `comfyui-wan-2-2`
- **GPU**: Select GPU type (RTX 4090 recommended for price/performance)
- **Workers**: Start with 1, scale up based on demand

**Container Configuration:**
- **Container Image**:
  - Option A: `YOUR_DOCKERHUB_USERNAME/comfyui-wan-serverless:latest`
  - Option B: Build from your repo URL
- **Container Start Command**: Leave empty (uses CMD from Dockerfile)

**Network Volume:**
- **Volume**: Select `comfyui-wan-2-2-models`
- **Mount Path**: `/workspace`

**Environment Variables:**
```bash
# Paths
MODELS_DIR=/workspace/models
OUTPUT_DIR=/workspace/output
TEMP_DIR=/workspace/temp
VENV_PATH=/workspace/venv

# Cache configuration
CACHE_TYPE=RAM_PRESSURE
CACHE_RAM=16.0

# Features
WARMUP_MODELS=true
CLEANUP_OUTPUTS=true

# CUDA optimization
CUDA_MODULE_LOADING=LAZY
PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

# R2/S3 Storage (optional - add your credentials)
R2_ENDPOINT=https://YOUR_ACCOUNT.r2.cloudflarestorage.com
R2_ACCESS_KEY=your_access_key
R2_SECRET_KEY=your_secret_key
R2_BUCKET=comfyui-outputs
R2_PUBLIC_URL=https://pub-xxxxx.r2.dev
```

**Advanced Settings:**
- **Max Workers**: 10 (adjust based on your needs)
- **Idle Timeout**: 5 seconds (for burst workloads)
- **Execution Timeout**: 600 seconds (10 minutes for long videos)
- **GPU Memory**: 24GB minimum

4. Click **Create Endpoint**

### Step 2: Wait for Deployment

- Initial deployment takes 2-3 minutes
- RunPod will pull your Docker image
- First worker will spin up and run warmup

**Check Status:**
- Status should show "Ready"
- Workers: At least 1 active worker
- Requests: 0 (ready to receive)

---

## Phase 4: Testing Your Endpoint

### Get Your Endpoint Details

1. Click on your endpoint name
2. Copy the **Endpoint ID** (looks like: `abc123def456`)
3. Copy your **API Key** from Account Settings

### Test 1: Minimal Validation

Test that the handler can process a simple workflow.

```bash
cd /Users/travissmith/Projects/ComfyUI_WAN/serverless

# Set environment variables
export RUNPOD_ENDPOINT_ID="your_endpoint_id"
export RUNPOD_API_KEY="your_api_key"

# Run test with minimal workflow
python test_handler.py --remote \
  --endpoint "https://api.runpod.ai/v2/${RUNPOD_ENDPOINT_ID}/runsync" \
  --workflow examples/minimal_validation.json
```

**Expected output:**
```
======================================================================
Testing Remote RunPod Endpoint
======================================================================

Endpoint: https://api.runpod.ai/v2/abc123def456/runsync
Workflow nodes: 8
Timeout: 900s

Sending request...
✓ Job submitted: abc123-456def-789ghi

Polling for results...
⏳ Status: IN_QUEUE (0.5s)
⏳ Status: IN_PROGRESS (2.1s)
⏳ Status: IN_PROGRESS (5.3s)
✓ Job completed in 8.7s

Results:
  - Output videos: 1
  - S3 URLs: ["https://pub-xxxxx.r2.dev/outputs/abc123.mp4"]
  - Processing time: 7.2s
```

### Test 2: Text-to-Video Generation

Test a full T2V workflow.

```bash
python test_handler.py --remote \
  --endpoint "https://api.runpod.ai/v2/${RUNPOD_ENDPOINT_ID}/runsync" \
  --workflow examples/t2v_workflow.json
```

**Expected duration**: 30-90 seconds (depending on GPU and length)

### Test 3: Stress Test (Optional)

Test burst scaling with concurrent requests.

```bash
# Run 10 concurrent requests
for i in {1..10}; do
  python test_handler.py --remote \
    --endpoint "https://api.runpod.ai/v2/${RUNPOD_ENDPOINT_ID}/run" \
    --workflow examples/minimal_validation.json &
done
wait
```

**Expected behavior:**
- RunPod scales up workers automatically
- First few requests may queue briefly
- Subsequent requests process immediately
- Workers scale down after idle timeout

---

## Phase 5: Monitoring and Optimization

### View Logs

1. Go to your endpoint in RunPod dashboard
2. Click **Logs** tab
3. View real-time execution logs

**Key metrics to watch:**
- Cold start time: ~5-10 seconds
- Warm start time: <1 second (executor reuse)
- Processing time: Varies by workflow
- Memory usage: Should stay under GPU limit

### Cost Optimization

**Reduce Costs:**
- Use Spot Instances (50% cheaper, may be interrupted)
- Adjust idle timeout (5s aggressive, 60s conservative)
- Set max workers based on expected load
- Use smaller GPUs for shorter videos

**Estimated Costs:**
- RTX 4090: ~$0.00034/second = ~$1.22/hour
- 100 requests/day × 30s each = 50 minutes = ~$1.02/day
- Network volume: ~$10/month
- **Total**: ~$40-50/month for moderate usage

### Performance Tuning

**Fast Cold Starts:**
- Keep network volume in same region as endpoint
- Use `WARMUP_MODELS=true` (preloads models on worker start)
- Optimize Docker image size (current: 6.75GB)

**Fast Warm Starts:**
- Enable executor reuse (already configured)
- Use `RAM_PRESSURE` cache for aggressive memory management
- Set appropriate idle timeout

**Throughput:**
- Increase max workers for higher concurrency
- Use faster GPUs (A6000, A100) for shorter processing time
- Batch similar requests when possible

---

## Troubleshooting

### Issue: Workers not starting

**Symptoms**: Endpoint shows "0 workers" or "pending"

**Solutions:**
1. Check Docker image is accessible (public or credentials set)
2. Verify network volume is in same region
3. Check GPU availability in region (may need to switch)
4. Review logs for error messages

### Issue: Out of memory errors

**Symptoms**: `CUDA out of memory` in logs

**Solutions:**
1. Reduce `CACHE_RAM` value
2. Use GPU with more VRAM
3. Reduce batch size in workflows
4. Enable `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True`

### Issue: Slow cold starts (>30s)

**Symptoms**: First request takes very long

**Solutions:**
1. Enable `WARMUP_MODELS=true`
2. Reduce Docker image size
3. Keep network volume in same region
4. Use faster storage tier

### Issue: S3/R2 uploads failing

**Symptoms**: No output URLs in response

**Solutions:**
1. Verify R2 credentials are correct
2. Check bucket exists and is accessible
3. Ensure bucket CORS is configured
4. Test credentials with AWS CLI

### Issue: Workflows timing out

**Symptoms**: Requests fail after 10 minutes

**Solutions:**
1. Increase execution timeout in endpoint settings
2. Optimize workflow (reduce frames, lower resolution)
3. Use faster GPU
4. Check for infinite loops in custom nodes

---

## API Integration

Once deployed, integrate with your application:

### Python Example

```python
import requests
import time

ENDPOINT_URL = "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/runsync"
API_KEY = "your_api_key"

def generate_video(prompt: str, steps: int = 20) -> dict:
    """Generate video from text prompt"""

    # Load your workflow template
    with open("examples/t2v_workflow.json") as f:
        workflow = json.load(f)

    # Customize workflow with parameters
    workflow["6"]["inputs"]["text"] = prompt
    workflow["31"]["inputs"]["steps"] = steps

    # Send request
    response = requests.post(
        ENDPOINT_URL,
        headers={"Authorization": f"Bearer {API_KEY}"},
        json={"input": {"workflow": workflow}},
        timeout=600
    )

    response.raise_for_status()
    result = response.json()

    return result["output"]

# Example usage
result = generate_video(
    prompt="A serene lake at sunset with mountains in the background",
    steps=20
)

print(f"Video URL: {result['outputs'][0]['url']}")
print(f"Processing time: {result['execution_time']}s")
```

### JavaScript/TypeScript Example

```typescript
interface VideoGenerationRequest {
  input: {
    workflow: object;
  };
}

interface VideoGenerationResponse {
  id: string;
  status: "COMPLETED" | "FAILED" | "IN_PROGRESS";
  output?: {
    outputs: Array<{ url: string; type: string }>;
    execution_time: number;
  };
}

async function generateVideo(
  prompt: string,
  steps: number = 20
): Promise<VideoGenerationResponse> {
  const ENDPOINT_URL = "https://api.runpod.ai/v2/YOUR_ENDPOINT_ID/runsync";
  const API_KEY = process.env.RUNPOD_API_KEY;

  // Load and customize workflow
  const workflow = await loadWorkflow("examples/t2v_workflow.json");
  workflow["6"]["inputs"]["text"] = prompt;
  workflow["31"]["inputs"]["steps"] = steps;

  // Send request
  const response = await fetch(ENDPOINT_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ input: { workflow } }),
  });

  if (!response.ok) {
    throw new Error(`Request failed: ${response.statusText}`);
  }

  return response.json();
}

// Example usage
const result = await generateVideo(
  "A serene lake at sunset with mountains in the background",
  20
);

console.log(`Video URL: ${result.output?.outputs[0].url}`);
console.log(`Processing time: ${result.output?.execution_time}s`);
```

---

## Next Steps

After successful deployment:

1. **Monitor Performance**: Watch metrics for first few days
2. **Optimize Costs**: Adjust worker count and idle timeout
3. **Scale Up**: Increase max workers as demand grows
4. **Add Features**: Integrate into your application
5. **Backup**: Periodically backup network volume

---

## Quick Reference

### Important URLs
- RunPod Dashboard: https://www.runpod.io/console
- API Docs: https://docs.runpod.io/serverless/overview
- Your Endpoint: `https://api.runpod.ai/v2/YOUR_ENDPOINT_ID`

### Key Files
- Handler: `serverless/handler.py`
- Dockerfile: `Dockerfile`
- Init Script: `serverless/init_network_volume.sh`
- Test Script: `serverless/test_handler.py`
- Template: `template.json`

### Support
- RunPod Discord: https://discord.gg/runpod
- ComfyUI WAN Issues: Your repo's issue tracker
- Documentation: This guide

---

**Estimated Total Setup Time**: 1-2 hours
**Estimated Monthly Cost**: $40-100 (depending on usage)
**GPU Requirement**: 24GB+ VRAM (RTX 4090, A5000, A6000, A100)
