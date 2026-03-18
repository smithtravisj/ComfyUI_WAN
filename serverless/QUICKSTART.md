# Quick Start: GitHub Actions Docker Build

Get your ComfyUI WAN serverless Docker image built in **5 minutes** using GitHub Actions.

## Prerequisites

- [ ] GitHub account
- [ ] This repository pushed to GitHub
- [ ] Git configured locally

## Step 1: Enable GitHub Packages (30 seconds)

GitHub Container Registry (GHCR) is enabled by default - no setup needed!

## Step 2: Push Code to GitHub (1 minute)

```bash
# Navigate to project
cd /Users/travissmith/Projects/ComfyUI_WAN

# Add all serverless files
git add .github/ Dockerfile .dockerignore serverless/

# Commit
git commit -m "Add serverless Docker build with GitHub Actions"

# Push (triggers automatic build)
git push origin main
```

## Step 3: Monitor Build (5-8 minutes)

### Option A: GitHub Web UI
1. Go to your repository on GitHub
2. Click **Actions** tab
3. See your build running
4. Click on the workflow to see progress

### Option B: GitHub CLI (Recommended)
```bash
# Install GitHub CLI (one-time)
brew install gh
gh auth login

# Watch build in real-time
gh run watch
```

## Step 4: Make Package Public (30 seconds)

Once build completes:

1. Go to your GitHub profile
2. Click **Packages** tab
3. Click **comfyui-wan-serverless**
4. Click **Package settings** (gear icon)
5. Scroll to "Danger Zone"
6. Click **Change visibility**
7. Select **Public**
8. Type package name to confirm

## Step 5: Get Image URL (10 seconds)

Your image is now available at:
```
ghcr.io/YOUR_GITHUB_USERNAME/comfyui_wan/comfyui-wan-serverless:latest
```

Replace `YOUR_GITHUB_USERNAME` with your actual GitHub username (lowercase).

Example:
```
ghcr.io/travissmith/comfyui_wan/comfyui-wan-serverless:latest
```

## Step 6: Use in RunPod (2 minutes)

Copy your image URL and use it in RunPod serverless template:

```json
{
  "dockerImage": "ghcr.io/YOUR_USERNAME/comfyui_wan/comfyui-wan-serverless:latest"
}
```

---

## Verification

Test that your image is correct:

```bash
# Pull image
docker pull ghcr.io/YOUR_USERNAME/comfyui_wan/comfyui-wan-serverless:latest

# Verify architecture (must be amd64)
docker inspect ghcr.io/YOUR_USERNAME/comfyui_wan/comfyui-wan-serverless:latest | grep Architecture

# Expected output: "Architecture": "amd64"
```

---

## Next Builds

Future builds are even easier:

```bash
# Make changes
vim serverless/handler.py

# Commit and push
git add serverless/handler.py
git commit -m "Update handler"
git push

# GitHub Actions builds automatically! 🚀
```

---

## Manual Trigger (Optional)

Trigger builds without git push:

```bash
./serverless/build.sh v1.0.0 --github
```

Or via GitHub web UI:
1. Actions tab
2. Build Serverless Docker Image
3. Run workflow (button on right)
4. Enter tag and run

---

## Troubleshooting

### Build Failed?

```bash
# View logs
gh run list
gh run view <run-id> --log
```

### Wrong Architecture?

Check that Dockerfile starts with:
```dockerfile
FROM --platform=linux/amd64 runpod/pytorch:...
```

### Can't Push to GHCR?

1. Repo Settings → Actions → General
2. Workflow permissions → "Read and write"
3. Save

---

## Total Time: ~8 minutes

- Setup: 2 minutes
- Build: 5-8 minutes
- Package public: 30 seconds

**vs 20-40 minutes** building locally on Mac! 🎉

---

## What's Next?

Follow the full serverless implementation guide:
- [Implementation Plan](../_design_docs/SERVERLESS_IMPLEMENTATION.md)
- [GitHub Actions Details](./README-GITHUB-ACTIONS.md)
- Create handler.py, warmup.py, etc.
