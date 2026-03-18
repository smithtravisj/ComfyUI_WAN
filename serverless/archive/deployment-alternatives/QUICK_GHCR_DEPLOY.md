# Quick GitHub Container Registry Deployment

**Problem**: Docker Hub push failing with "broken pipe" due to large image size (6.75GB) and limited Docker Desktop memory (7.6GB).

**Solution**: Use GitHub Container Registry (GHCR) with GitHub Actions - faster, more reliable, already configured!

---

## Why GHCR Instead of Docker Hub?

| Feature | Docker Hub | GHCR (GitHub Actions) |
|---------|------------|----------------------|
| Build time | 20-40 min (Mac) | 5-8 min (native AMD64) |
| Push reliability | ❌ Failing | ✅ Reliable |
| Memory required | 12-16GB | None (runs on GitHub) |
| Manual steps | Many | Just `git push` |
| Cost | Free | Free (2000 min/month) |

---

## Step 1: Push Code to GitHub (1 minute)

Your code is ready! Just commit and push:

```bash
cd /Users/travissmith/Projects/ComfyUI_WAN

# Check what needs to be committed
git status

# Stage all serverless files
git add serverless/ Dockerfile .dockerignore .github/

# Commit
git commit -m "Complete serverless implementation - ready for deployment"

# Push to trigger GitHub Actions build
git push origin main
```

**This automatically triggers the build workflow!**

---

## Step 2: Monitor Build (5-8 minutes)

### Option A: Use GitHub CLI (Recommended)

```bash
# Install gh CLI if needed
brew install gh

# Watch the build in real-time
gh run watch
```

### Option B: Use GitHub Web UI

1. Go to: https://github.com/YOUR_USERNAME/ComfyUI_WAN/actions
2. Click on the latest "Build Serverless Docker Image" run
3. Watch progress (takes 5-8 minutes)

**What's happening:**
- GitHub Actions spins up Ubuntu runner
- Builds Docker image natively on AMD64 (fast!)
- Pushes to GHCR automatically
- No manual work needed!

---

## Step 3: Make Package Public (30 seconds)

After build completes:

1. Go to: https://github.com/YOUR_USERNAME?tab=packages
2. Click on `comfyui_wan/comfyui-wan-serverless`
3. Click **Package settings** (right sidebar)
4. Scroll to **Danger Zone**
5. Click **Change visibility** → **Public**
6. Confirm

---

## Step 4: Get Image URL for RunPod

Your image URL is:
```
ghcr.io/YOUR_GITHUB_USERNAME/comfyui_wan/comfyui-wan-serverless:latest
```

**Example:**
```
ghcr.io/tjsmithut/comfyui_wan/comfyui-wan-serverless:latest
```

---

## Step 5: Use in RunPod Template

When creating your serverless endpoint, use:

**Container Image:**
```
ghcr.io/YOUR_GITHUB_USERNAME/comfyui_wan/comfyui-wan-serverless:latest
```

**That's it!** No Docker Hub push needed.

---

## Verification

### Check Build Success

```bash
# Using gh CLI
gh run list --workflow build-docker-serverless.yml --limit 1

# Should show: ✓ Build Serverless Docker Image
```

### Verify Image Exists

Visit:
```
https://github.com/YOUR_USERNAME/ComfyUI_WAN/pkgs/container/comfyui_wan%2Fcomfyui-wan-serverless
```

You should see:
- ✅ Package visible
- ✅ Tag: `latest`
- ✅ Size: ~6.75GB
- ✅ Published: Today

---

## Troubleshooting

### Build Failed

**Check logs:**
```bash
gh run view --log
```

**Common issues:**
- **Permissions**: Repo Settings → Actions → General → Workflow permissions → "Read and write"
- **Branch name**: Workflow triggers on `main` or `master` branch
- **File changes**: Make sure Dockerfile or serverless/ files changed

### Package Not Public

- Default: Packages are private
- Must manually change to public (Step 3 above)
- RunPod needs public access or authentication

### Can't Find Package

- Wait 1-2 minutes after build completes
- Refresh GitHub packages page
- Check: https://github.com/YOUR_USERNAME?tab=packages

---

## Future Updates

**Every time you update the code:**

```bash
# Make changes to handler.py, Dockerfile, etc.
git add .
git commit -m "Update serverless handler"
git push

# GitHub Actions automatically rebuilds and pushes!
# No manual Docker commands needed
```

---

## Comparison: Manual vs Automated

### Manual (Docker Hub) - ❌ Failing
```bash
# 1. Build locally (20-40 min on Mac)
docker build --platform linux/amd64 -t image:latest .

# 2. Tag for Docker Hub
docker tag image:latest user/image:latest

# 3. Push (fails with broken pipe)
docker push user/image:latest  # ❌ FAILS
```

### Automated (GHCR) - ✅ Working
```bash
# 1. Just push code
git push origin main

# 2. Wait 5-8 minutes
# GitHub Actions does everything automatically!

# 3. Use in RunPod
# ghcr.io/user/repo/image:latest
```

---

## Cost Comparison

### Docker Hub Push (Manual)
- Docker Desktop memory: Need 12-16GB
- Time: 15-30 minutes (if it works)
- Reliability: Low (failing with large images)
- Maintenance: Manual every update

### GHCR + GitHub Actions (Automated)
- Cost: $0 (2000 free minutes/month)
- Time: 5-8 minutes
- Reliability: High
- Maintenance: Zero (automatic on push)

---

## Ready to Deploy?

After GHCR image is ready:

1. ✅ Image URL: `ghcr.io/YOUR_USERNAME/comfyui_wan/comfyui-wan-serverless:latest`
2. ✅ Next: Continue with [RUNPOD_DEPLOYMENT.md](RUNPOD_DEPLOYMENT.md) Phase 1
3. ✅ Use GHCR URL in RunPod template instead of Docker Hub

---

**Recommendation**: Abandon Docker Hub push attempts, use GHCR instead!
