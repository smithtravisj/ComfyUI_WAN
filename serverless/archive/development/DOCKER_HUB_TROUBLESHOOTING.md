# Docker Hub Push Troubleshooting

## Problem: "write: broken pipe" Error

This error occurs when pushing large images (6.75GB) to Docker Hub and typically indicates:
- Network timeout
- Docker Desktop resource limits
- Connection instability

## Solutions (Try in Order)

### Solution 1: Use Automated Retry Script

```bash
cd /Users/travissmith/Projects/ComfyUI_WAN/serverless
./push_docker.sh YOUR_DOCKERHUB_USERNAME
```

**What it does:**
- Automatically retries up to 5 times
- Uses exponential backoff (10s → 20s → 40s → 80s → 160s)
- Handles transient network issues

**Expected time:** 15-30 minutes (with retries)

### Solution 2: Increase Docker Desktop Resources

**Before pushing, optimize Docker Desktop:**

1. **Open Docker Desktop**
   - Click Docker icon in menu bar → Settings

2. **Increase Resources** (Settings → Resources):
   - **Memory**: 8GB → 16GB (if available)
   - **CPUs**: 4+ cores
   - **Disk**: Ensure 20GB+ free space

3. **Restart Docker Desktop**
   ```bash
   # Kill Docker Desktop
   pkill -f Docker

   # Restart from Applications
   open -a Docker

   # Wait for Docker to be ready
   while ! docker info >/dev/null 2>&1; do sleep 1; done
   echo "Docker ready"
   ```

4. **Retry push**
   ```bash
   ./push_docker.sh YOUR_DOCKERHUB_USERNAME
   ```

### Solution 3: Disable Network Proxies/VPN

**Docker Desktop proxy can cause issues with large uploads:**

1. **Check proxy settings**
   - Docker Desktop → Settings → Resources → Proxies
   - Disable if enabled

2. **Disable VPN** (if active)
   - Large uploads often fail through VPN tunnels
   - Use direct connection

3. **Retry push**

### Solution 4: Push During Off-Peak Hours

**Docker Hub can be slow during peak times:**

- **Peak hours**: 9 AM - 5 PM PST (weekdays)
- **Off-peak**: Late night or early morning
- **Best time**: 11 PM - 6 AM PST

### Solution 5: Use GitHub Container Registry (Recommended Alternative)

**Advantages:**
- Built on GitHub Actions (native AMD64)
- Faster builds (5-8 min vs 20-40 min)
- More reliable for large images
- Free for public repositories

**Setup:**

1. **Create `.github/workflows/push-ghcr.yml`:**
   ```yaml
   name: Push to GHCR
   on:
     push:
       branches: [main, master]
     workflow_dispatch:

   jobs:
     push:
       runs-on: ubuntu-latest
       permissions:
         contents: read
         packages: write

       steps:
         - uses: actions/checkout@v4

         - name: Log in to GHCR
           uses: docker/login-action@v3
           with:
             registry: ghcr.io
             username: ${{ github.actor }}
             password: ${{ secrets.GITHUB_TOKEN }}

         - name: Build and push
           uses: docker/build-push-action@v5
           with:
             context: .
             file: ./Dockerfile
             push: true
             tags: ghcr.io/${{ github.repository_owner }}/comfyui-wan-serverless:latest
             platforms: linux/amd64
   ```

2. **Push to GitHub:**
   ```bash
   git add .github/workflows/push-ghcr.yml
   git commit -m "Add GHCR push workflow"
   git push
   ```

3. **Use in RunPod:**
   ```
   Container Image: ghcr.io/YOUR_USERNAME/comfyui-wan-serverless:latest
   ```

4. **Make package public:**
   - GitHub.com → Your Profile → Packages
   - Click package → Settings → Change visibility → Public

### Solution 6: Split into Layers and Push Incrementally

**If all else fails, optimize the Dockerfile for better layer caching:**

1. **Create optimized Dockerfile:**
   ```dockerfile
   # Push layers incrementally
   FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

   # Layer 1: System packages (rarely changes)
   RUN apt-get update && apt-get install -y python3.11 git ...

   # Push checkpoint
   # docker build --target layer1 -t user/image:layer1 .
   # docker push user/image:layer1

   # Layer 2: Python dependencies (changes occasionally)
   COPY requirements.txt .
   RUN pip install -r requirements.txt

   # Layer 3: Application code (changes frequently)
   COPY . /comfyui/
   ```

2. **Push incrementally:**
   ```bash
   # Push base layers first (smaller, more reliable)
   docker build --target base -t tjsmithut/comfyui-wan-serverless:base .
   docker push tjsmithut/comfyui-wan-serverless:base

   # Then push full image (reuses base layers)
   docker build -t tjsmithut/comfyui-wan-serverless:latest .
   docker push tjsmithut/comfyui-wan-serverless:latest
   ```

## Quick Diagnosis Commands

```bash
# Check Docker resources
docker info | grep -E "Memory|CPUs"

# Check image size
docker images comfyui-wan-serverless:test

# Check Docker Hub login
docker info | grep Username

# Check network connectivity
curl -I https://registry-1.docker.io/v2/

# Monitor push progress (in another terminal)
watch -n 5 'docker push tjsmithut/comfyui-wan-serverless:latest 2>&1 | tail -20'
```

## Estimated Push Times

| Connection | Time | Notes |
|------------|------|-------|
| Gigabit (1000 Mbps) | 10-15 min | Ideal |
| Fast (100 Mbps) | 15-25 min | Good |
| Medium (50 Mbps) | 25-40 min | Slow but works |
| Slow (<25 Mbps) | 40-60+ min | Use GHCR instead |

## Alternative: Skip Docker Hub Entirely

**Use GitHub Actions + GHCR workflow (already configured):**

1. **Check existing workflow:**
   ```bash
   cat .github/workflows/build-docker-serverless.yml
   ```

2. **Trigger build:**
   ```bash
   git push origin main
   ```

3. **Wait 5-8 minutes** (native AMD64 build)

4. **Use in RunPod:**
   ```
   ghcr.io/YOUR_USERNAME/comfyui_wan/comfyui-wan-serverless:latest
   ```

**Advantages:**
- No manual push needed
- Faster builds
- More reliable
- Automatic on every commit

## Success Indicators

**Push succeeded when you see:**
```
latest: digest: sha256:abc123... size: 1234
```

**Verify on Docker Hub:**
1. Visit: https://hub.docker.com/r/YOUR_USERNAME/comfyui-wan-serverless
2. Check "Tags" tab
3. Verify size: ~6.75GB
4. Note digest for verification

## Still Having Issues?

**Contact Support:**
- Docker Hub Status: https://status.docker.com/
- Docker Community: https://forums.docker.com/
- RunPod Discord: https://discord.gg/runpod (can help with alternative solutions)

**Last Resort:**
Use RunPod's build service:
1. Push code to GitHub/GitLab
2. In RunPod template, specify repo URL
3. Let RunPod build the image on their infrastructure
4. No manual push needed!
