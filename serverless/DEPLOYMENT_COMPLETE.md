# Deployment Complete - RunPod Serverless Setup

**Status**: Network volume initialized ✅
**Next**: Deploy serverless endpoint
**Date**: 2026-03-18

---

## Current Status Summary

### ✅ Completed

1. **Network Volume Initialization**
   - Location: `/workspace` on RunPod network volume
   - Size: ~173GB used (models + venv + custom nodes)
   - Models: All 65GB+ downloaded and verified
   - Venv: Python 3.11.10 with all dependencies
   - Custom nodes: 18 nodes installed

2. **Docker Image Build**
   - Building via GitHub Actions (5-8 minutes)
   - Image: `ghcr.io/smithtravisj/comfyui_wan/comfyui-wan-serverless:latest`
   - Platform: linux/amd64 (RunPod compatible)
   - Size: ~6.75GB

### ⏳ In Progress

- Docker image build running on GitHub Actions
- Check status: https://github.com/smithtravisj/ComfyUI_WAN/actions

### 📋 Next Steps

1. Wait for Docker build to complete (~5-8 minutes)
2. Make Docker image public
3. Deploy serverless endpoint on RunPod
4. Test with example workflow

---

## Docker Image Status

### Check Build Status

```bash
# Via CLI
gh run watch

# Or visit
https://github.com/smithtravisj/ComfyUI_WAN/actions
```

### After Build Completes

1. **Make Image Public**:
   - Go to https://github.com/smithtravisj?tab=packages
   - Click on `comfyui-wan-serverless`
   - Go to **Package settings**
   - Change visibility to **Public**

2. **Verify Image**:
   ```bash
   # Check the image exists
   docker pull ghcr.io/smithtravisj/comfyui_wan/comfyui-wan-serverless:latest

   # Verify architecture
   docker inspect ghcr.io/smithtravisj/comfyui_wan/comfyui-wan-serverless:latest | grep Architecture
   # Should show: "Architecture": "amd64"
   ```

---

## RunPod Endpoint Deployment

### Configuration Details

**Container Image**:
```
ghcr.io/smithtravisj/comfyui_wan/comfyui-wan-serverless:latest
```

**GPU Types** (choose cheapest available):
- NVIDIA RTX 4090
- NVIDIA A5000
- NVIDIA A6000

**Container Settings**:
- Container Disk: 20GB minimum
- Docker Command: (leave default - uses CMD from Dockerfile)
- HTTP Ports: 8000 (default for handler)

**Network Volume**:
- Attach your initialized network volume
- Mount path: `/workspace`
- This contains all models and venv

**Environment Variables** (Optional - for S3 upload):
```bash
AWS_ACCESS_KEY_ID=<your-key>
AWS_SECRET_ACCESS_KEY=<your-secret>
AWS_ENDPOINT_URL_S3=<your-s3-endpoint>
S3_BUCKET_NAME=<your-bucket>
```

**Scaling Settings**:
```yaml
Idle Timeout: 5 seconds
Execution Timeout: 600 seconds (10 minutes)
Active Workers: 0-3
Max Workers: 10
```

---

## Test Workflow Examples

### Simple Text-to-Video

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

**Expected Output**:
- Duration: 3-6 seconds (warm) or 8-12 seconds (cold start)
- Format: Base64-encoded MP4 or S3 URL
- Resolution: Determined by model (default 1024x576)

### Lightning LoRA (4-step fast generation)

```json
{
  "input": {
    "workflow": {
      "prompt": "A cyberpunk city at night with neon lights",
      "num_frames": 49,
      "steps": 4,
      "cfg": 2.0,
      "seed": 123,
      "use_lightning": true
    }
  }
}
```

**Expected Output**:
- Duration: 2-4 seconds (50% faster than standard)
- Same quality with fewer steps

---

## Cost Estimates

### Initialization (One-Time)
- GPU Pod (RTX 4090): ~$0.20 for 30-40 minutes
- Network Volume: $7-10/month (persistent)

### Serverless Usage
- **Cold Start**: 8-12 seconds @ $0.34/hour = ~$0.0009-0.0011
- **Warm Request**: 3-6 seconds @ $0.34/hour = ~$0.0003-0.0006
- **30-second video**: ~$0.003-0.005 per generation

### Monthly Estimates
- **Low usage** (100 videos/month): ~$1-2 + $7 storage = **$8-9/month**
- **Medium usage** (1000 videos/month): ~$10-15 + $7 storage = **$17-22/month**
- **High usage** (10,000 videos/month): ~$100-150 + $7 storage = **$107-157/month**

---

## Monitoring and Optimization

### Check Endpoint Health

```bash
# Using RunPod CLI
runpod endpoint logs <endpoint-id>

# Using API
curl https://api.runpod.ai/v2/<endpoint-id>/health \
  -H "Authorization: Bearer $RUNPOD_API_KEY"
```

### Performance Metrics

Monitor in RunPod console:
- **Cold Start Time**: Should be 8-12 seconds
- **Warm Execution**: Should be 3-6 seconds
- **Success Rate**: Should be >95%
- **GPU Utilization**: Check if properly using CUDA

### Optimization Tips

1. **Reduce Cold Starts**:
   - Increase idle timeout (trade-off: higher costs)
   - Keep 1 worker active during peak hours
   - Use warmup endpoint periodically

2. **Improve Performance**:
   - Use Lightning LoRA for 4-step generation (2x faster)
   - Reduce num_frames for shorter videos
   - Batch multiple generations

3. **Cost Optimization**:
   - Set aggressive idle timeout (5 seconds)
   - Scale to zero during off-hours
   - Use cheaper GPU types (A5000 vs A6000)

---

## Troubleshooting

### Container Fails to Start

**Symptom**: Endpoint shows "Error" status

**Checks**:
1. Is Docker image public?
   - Visit https://github.com/smithtravisj?tab=packages
   - Verify `comfyui-wan-serverless` is public

2. Is network volume attached?
   - Check endpoint settings
   - Mount path should be `/workspace`

3. Check container logs:
   - RunPod console → Endpoint → Logs
   - Look for initialization errors

**Common Issues**:
- Image not found (403): Make package public
- Models not found: Verify `/workspace/models` exists
- Import errors: Check venv installation

### Requests Timing Out

**Symptom**: 504 Gateway Timeout

**Checks**:
1. Increase execution timeout (Settings → 600-900 seconds)
2. Check GPU availability in your region
3. Verify workflow parameters (reduce steps/frames)

**Common Issues**:
- First request takes longer (cold start)
- Complex workflows need more time
- GPU out of memory (reduce resolution)

### Model Loading Failures

**Symptom**: Error: "Model not found" in logs

**Checks**:
1. Verify network volume initialization completed:
   ```bash
   cat /workspace/.initialized
   ```

2. Check models exist:
   ```bash
   ls -lh /workspace/models/vae/
   ls -lh /workspace/models/unet/
   ```

3. Verify symlinks:
   ```bash
   ls -la /workspace/ComfyUI_WAN/models
   # Should show: models -> /workspace/models
   ```

**Fix**:
- Re-run initialization if models missing
- Check network volume is attached correctly

---

## API Usage Examples

### Python Client

```python
import requests
import base64
import json

RUNPOD_ENDPOINT_ID = "your-endpoint-id"
RUNPOD_API_KEY = "your-api-key"

def generate_video(prompt, num_frames=49, steps=8):
    url = f"https://api.runpod.ai/v2/{RUNPOD_ENDPOINT_ID}/runsync"

    headers = {
        "Authorization": f"Bearer {RUNPOD_API_KEY}",
        "Content-Type": "application/json"
    }

    payload = {
        "input": {
            "workflow": {
                "prompt": prompt,
                "num_frames": num_frames,
                "steps": steps,
                "cfg": 2.5,
                "seed": 42
            }
        }
    }

    response = requests.post(url, headers=headers, json=payload)
    result = response.json()

    if result["status"] == "COMPLETED":
        # Decode base64 video
        video_b64 = result["output"]["video"]
        video_bytes = base64.b64decode(video_b64)

        # Save to file
        with open("output.mp4", "wb") as f:
            f.write(video_bytes)

        print(f"Video saved to output.mp4")
        return video_bytes
    else:
        print(f"Error: {result}")
        return None

# Example usage
generate_video("A serene mountain landscape at sunset")
```

### cURL Example

```bash
curl -X POST "https://api.runpod.ai/v2/${RUNPOD_ENDPOINT_ID}/runsync" \
  -H "Authorization: Bearer ${RUNPOD_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "workflow": {
        "prompt": "A serene mountain landscape at sunset",
        "num_frames": 49,
        "steps": 8,
        "cfg": 2.5,
        "seed": 42
      }
    }
  }'
```

---

## Network Volume Details

### Current Structure

```
/workspace/
├── ComfyUI_WAN/           # Cloned repository
│   ├── serverless/        # Handler and configs
│   ├── custom_nodes/      # 18 custom nodes
│   ├── venv/             # Python environment (copy)
│   └── models/           # Symlink → /workspace/models
├── models/               # Persistent model storage
│   ├── unet/            # 4 UNET models (Q8_0, ~48GB)
│   ├── text_encoders/   # Text encoder (~4GB)
│   ├── vae/             # VAE model (~242MB)
│   ├── loras/           # Lightning LoRAs (~8GB)
│   └── upscale_models/  # Upscalers (~200MB)
├── venv/                # Network volume venv (for serverless)
├── output/              # Generated videos
├── temp/                # Temporary files
└── .initialized         # Marker file with metadata
```

### Initialization Marker

```bash
cat /workspace/.initialized
```

Shows:
- Initialization date
- Python version
- Model counts
- Space used

---

## Next Actions Checklist

- [ ] Wait for Docker build to complete (5-8 minutes)
- [ ] Check GitHub Actions: https://github.com/smithtravisj/ComfyUI_WAN/actions
- [ ] Make Docker image public: https://github.com/smithtravisj?tab=packages
- [ ] Go to RunPod → Serverless → Create Endpoint
- [ ] Configure with image: `ghcr.io/smithtravisj/comfyui_wan/comfyui-wan-serverless:latest`
- [ ] Attach network volume to `/workspace`
- [ ] Set GPU types (RTX 4090, A5000, A6000)
- [ ] Configure scaling (0-3 workers, 5s idle timeout)
- [ ] Deploy endpoint
- [ ] Test with simple workflow
- [ ] Monitor performance and costs
- [ ] Optimize based on usage patterns

---

## Support and Resources

### Documentation
- Main README: [README.md](README.md)
- Quick Start: [QUICKSTART.md](QUICKSTART.md)
- Full Deployment: [RUNPOD_DEPLOYMENT.md](RUNPOD_DEPLOYMENT.md)
- Init Commands: [RUNPOD_INIT_COMMANDS.md](RUNPOD_INIT_COMMANDS.md)

### GitHub Repository
- Code: https://github.com/smithtravisj/ComfyUI_WAN
- Actions: https://github.com/smithtravisj/ComfyUI_WAN/actions
- Packages: https://github.com/smithtravisj?tab=packages

### RunPod Resources
- Console: https://www.runpod.io/console
- Docs: https://docs.runpod.io/serverless/overview
- Community: https://discord.gg/runpod

---

**Status**: Ready for serverless deployment after Docker build completes
**Build ETA**: 5-8 minutes from manual trigger
**Total Implementation Time**: ~2 hours (including troubleshooting)

🎉 **You're almost there!** Just waiting for the Docker build to finish.
