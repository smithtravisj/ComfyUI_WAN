# Next Steps - Deploy RunPod Serverless Endpoint

✅ **Docker Image Built Successfully!**

Your Docker image is ready at:
```
ghcr.io/smithtravisj/comfyui-wan-serverless:latest
```

---

## Step 1: Make Docker Image Public

1. Go to: https://github.com/smithtravisj?tab=packages
2. Click on **`comfyui-wan-serverless`**
3. Click **Package settings** (right sidebar)
4. Scroll to **Danger Zone** → **Change visibility**
5. Select **Public**
6. Type the package name to confirm: `comfyui-wan-serverless`
7. Click **I understand, change package visibility**

---

## Step 2: Create RunPod Serverless Endpoint

### Go to RunPod Console

1. Visit: https://www.runpod.io/console/serverless
2. Click **+ New Endpoint**

### Configure Endpoint

**Basic Settings**:
- **Endpoint Name**: `comfyui-wan-2-2`
- **Description**: ComfyUI WAN 2.2 Video Generation

**Container Configuration**:
```
Container Image: ghcr.io/smithtravisj/comfyui-wan-serverless:latest
Container Disk: 20 GB
Docker Command: (leave default)
```

**GPU Configuration**:
- Select GPUs: **RTX 4090**, **A5000**, or **A6000**
- Max Workers: **3**
- GPUs/Worker: **1**
- Active Workers: **0** (scale from zero)

**Network Volume**:
- Click **Select Network Storage**
- Choose your initialized network volume: `comfy-ui - US-IL-1`
- Mount path: `/runpod-volume` (default - leave as is)
  - The Docker container creates a symlink: `/workspace` → `/runpod-volume`
  - Handler code uses `/workspace`, which automatically points to the network volume

**Advanced Configuration**:
```
Idle Timeout: 5 seconds
Execution Timeout: 600 seconds
```

**Environment Variables** (Optional - skip for now):
```
AWS_ACCESS_KEY_ID=<your-key>
AWS_SECRET_ACCESS_KEY=<your-secret>
AWS_ENDPOINT_URL_S3=<your-s3-endpoint>
S3_BUCKET_NAME=<your-bucket>
```

### Deploy

Click **Deploy** button at the bottom

---

## Step 3: Wait for Endpoint Initialization

After clicking Deploy:
- Endpoint will show "Initializing..." (~30-60 seconds)
- Then status will change to "Ready"
- You'll receive an **Endpoint ID** (looks like: `abc123xyz`)

---

## Step 4: Test Your Endpoint

### Option A: Test via RunPod UI

1. In your endpoint page, click **Requests** tab
2. Click **Run** button
3. Paste this test request:

```json
{
  "input": {
    "workflow": {
      "prompt": "A serene mountain landscape at sunset with flowing water",
      "num_frames": 49,
      "steps": 8,
      "cfg": 2.5,
      "seed": 42
    }
  }
}
```

4. Click **Run**
5. Wait 8-12 seconds (cold start) or 3-6 seconds (warm)
6. Check the response for base64-encoded video

### Option B: Test via API (cURL)

```bash
# Set your credentials
export RUNPOD_ENDPOINT_ID="your-endpoint-id-here"
export RUNPOD_API_KEY="your-api-key-here"

# Test request
curl -X POST "https://api.runpod.ai/v2/${RUNPOD_ENDPOINT_ID}/runsync" \
  -H "Authorization: Bearer ${RUNPOD_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "workflow": {
        "prompt": "A serene mountain landscape at sunset with flowing water",
        "num_frames": 49,
        "steps": 8,
        "cfg": 2.5,
        "seed": 42
      }
    }
  }'
```

### Option C: Test with Python

```python
import requests
import base64

RUNPOD_ENDPOINT_ID = "your-endpoint-id-here"
RUNPOD_API_KEY = "your-api-key-here"

url = f"https://api.runpod.ai/v2/{RUNPOD_ENDPOINT_ID}/runsync"

headers = {
    "Authorization": f"Bearer {RUNPOD_API_KEY}",
    "Content-Type": "application/json"
}

payload = {
    "input": {
        "workflow": {
            "prompt": "A serene mountain landscape at sunset with flowing water",
            "num_frames": 49,
            "steps": 8,
            "cfg": 2.5,
            "seed": 42
        }
    }
}

print("Sending request...")
response = requests.post(url, headers=headers, json=payload)
result = response.json()

if result["status"] == "COMPLETED":
    print("✓ Video generated successfully!")

    # Decode and save video
    video_b64 = result["output"]["video"]
    video_bytes = base64.b64decode(video_b64)

    with open("output.mp4", "wb") as f:
        f.write(video_bytes)

    print(f"✓ Video saved to: output.mp4")
    print(f"✓ Execution time: {result['executionTime']}ms")
else:
    print(f"✗ Error: {result}")
```

---

## Expected Results

### First Request (Cold Start)
```json
{
  "status": "COMPLETED",
  "executionTime": 8000-12000,
  "output": {
    "video": "base64_encoded_mp4_data...",
    "info": {
      "frames": 49,
      "duration": "~2 seconds",
      "format": "mp4"
    }
  }
}
```

### Subsequent Requests (Warm)
```json
{
  "status": "COMPLETED",
  "executionTime": 3000-6000,
  "output": {
    "video": "base64_encoded_mp4_data...",
    "info": {
      "frames": 49,
      "duration": "~2 seconds",
      "format": "mp4"
    }
  }
}
```

---

## Troubleshooting

### Container Fails to Start

**Symptom**: Endpoint shows "Error" status

**Fix**:
1. Verify Docker image is public (Step 1)
2. Check network volume is attached to `/workspace`
3. View logs: Endpoint → **Logs** tab
4. Look for initialization errors

### Request Timeouts

**Symptom**: 504 Gateway Timeout

**Fix**:
1. Increase **Execution Timeout** to 900 seconds
2. Check GPU availability in your region
3. Try smaller workflow (reduce frames/steps)

### Models Not Found

**Symptom**: Error logs show "Model file not found"

**Fix**:
1. Verify network volume initialization completed:
   ```bash
   # In RunPod pod terminal
   cat /workspace/.initialized
   ls -lh /workspace/models/vae/
   ```
2. Check symlink exists:
   ```bash
   ls -la /workspace/ComfyUI_WAN/models
   # Should show: models -> /workspace/models
   ```

---

## Performance Optimization

### Reduce Cold Starts

1. Increase **Idle Timeout** from 5s to 30s
2. Keep 1 **Active Worker** during peak hours
3. Use warmup requests periodically

### Improve Speed

1. Use **Lightning LoRA** (4-step generation):
   ```json
   {
     "workflow": {
       "prompt": "...",
       "steps": 4,
       "use_lightning": true
     }
   }
   ```

2. Reduce frames for shorter videos:
   ```json
   {
     "workflow": {
       "prompt": "...",
       "num_frames": 25
     }
   }
   ```

### Cost Optimization

1. Set aggressive **Idle Timeout**: 5 seconds
2. **Scale to Zero**: Active Workers = 0
3. Use cheaper GPUs: RTX 4090 > A5000 > A6000

---

## Cost Estimates

### Per Video Generation
- **Cold Start** (8-12s): ~$0.0009-0.0011
- **Warm Request** (3-6s): ~$0.0003-0.0006
- **Average**: ~$0.003-0.005 per video

### Monthly Estimates
- **100 videos**: ~$1-2 + $7 storage = **$8-9/month**
- **1,000 videos**: ~$10-15 + $7 storage = **$17-22/month**
- **10,000 videos**: ~$100-150 + $7 storage = **$107-157/month**

---

## Monitoring

### Check Endpoint Health

```bash
curl "https://api.runpod.ai/v2/${RUNPOD_ENDPOINT_ID}/health" \
  -H "Authorization: Bearer ${RUNPOD_API_KEY}"
```

### View Request Logs

1. Go to endpoint page
2. Click **Requests** tab
3. View status, duration, errors for each request

### Monitor Metrics

- **Success Rate**: Should be >95%
- **Cold Start Time**: 8-12 seconds
- **Warm Execution**: 3-6 seconds
- **GPU Utilization**: Check in logs

---

## Summary Checklist

- [ ] Make Docker image public on GitHub
- [ ] Create RunPod serverless endpoint
- [ ] Configure GPU types and scaling
- [ ] Attach network volume to `/workspace`
- [ ] Set execution timeout to 600 seconds
- [ ] Deploy endpoint
- [ ] Wait for "Ready" status
- [ ] Copy Endpoint ID
- [ ] Run test request
- [ ] Verify video output
- [ ] Check execution time
- [ ] Monitor logs for errors
- [ ] Optimize settings based on usage

---

## Resources

- **GitHub Repository**: https://github.com/smithtravisj/ComfyUI_WAN
- **Docker Image**: https://github.com/smithtravisj?tab=packages
- **RunPod Console**: https://www.runpod.io/console/serverless
- **RunPod Docs**: https://docs.runpod.io/serverless/overview

---

**Status**: Ready for deployment! 🚀

**Completion Time**: ~10 minutes to deploy and test

**You're at the finish line!** Just need to make the image public and create the endpoint.
