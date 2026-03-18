# ComfyUI WAN 2.2 Serverless Implementation

Docker + GitHub Actions setup for RunPod serverless deployment, optimized for building from Mac.

## 📁 Files Created

### Core Build Files
- [`.github/workflows/build-docker-serverless.yml`](../.github/workflows/build-docker-serverless.yml) - GitHub Actions workflow
- [`Dockerfile`](../Dockerfile) - Multi-platform Docker image definition
- [`.dockerignore`](../.dockerignore) - Build context optimization
- [`build.sh`](./build.sh) - Build script with Mac support

### Documentation
- [`QUICKSTART.md`](./QUICKSTART.md) - 8-minute setup guide
- [`README-GITHUB-ACTIONS.md`](./README-GITHUB-ACTIONS.md) - Complete GitHub Actions guide
- [`README.md`](./README.md) - This file

### Serverless Implementation (Complete)
- [`handler.py`](handler.py) - Serverless handler (16K)
- [`warmup.py`](warmup.py) - Model preloading (6K)
- [`init_network_volume.sh`](init_network_volume.sh) - Network volume setup (12K)
- [`runpod_template.json`](runpod_template.json) - RunPod configuration (7.4K)
- [`test_handler.py`](test_handler.py) - Testing script (8.8K)

---

## 🚀 Quick Start

### For the Impatient (8 minutes)

```bash
# 1. Push to GitHub (triggers automatic build)
git add .github/ Dockerfile .dockerignore serverless/
git commit -m "Add serverless Docker build"
git push origin main

# 2. Watch build (requires gh CLI)
gh run watch

# 3. After 5-8 minutes, make package public:
#    GitHub.com → Your Profile → Packages → comfyui-wan-serverless → Settings → Make Public

# 4. Use in RunPod:
#    dockerImage: "ghcr.io/YOUR_USERNAME/comfyui_wan/comfyui-wan-serverless:latest"
```

**Full guide**: [QUICKSTART.md](./QUICKSTART.md)

---

## 🔧 Build Methods

### Option A: GitHub Actions (Recommended)

**Best for**: Production builds, regular development

**Pros**:
- ✅ Fast: 5-8 minutes (native AMD64)
- ✅ Free: 2,000 minutes/month
- ✅ Automatic: Triggers on git push
- ✅ Cached: Faster subsequent builds

**Usage**:
```bash
# Automatic trigger
git push origin main

# Manual trigger
./build.sh v1.0.0 --github

# Or via GitHub UI: Actions → Build Serverless → Run workflow
```

**Details**: [README-GITHUB-ACTIONS.md](./README-GITHUB-ACTIONS.md)

### Option B: Local Build (Mac)

**Best for**: Testing without git push, offline development

**Pros**:
- ✅ No git push required
- ✅ Immediate local testing

**Cons**:
- ❌ Slow: 20-40 minutes (QEMU emulation)
- ❌ Resource intensive

**Usage**:
```bash
./build.sh latest --push
```

---

## 📋 Implementation Status

### ✅ Phase 1: Build Infrastructure (Complete)
- [x] GitHub Actions workflow
- [x] Dockerfile with Mac compatibility
- [x] Build automation script
- [x] Documentation

### ✅ Phase 2: Serverless Handler (Complete)
- [x] Created `handler.py` (16K - direct executor, S3 uploads)
- [x] Created `warmup.py` (6K - model preloading)
- [x] Created `init_network_volume.sh` (12K - volume initialization)
- [x] Created `runpod_template.json` (7.4K - endpoint config)
- [x] Testing and validation scripts

### ✅ Phase 3: Local Testing Setup (Complete)
- [x] Workspace initialized with symlinked models
- [x] Docker image built (6.75GB)
- [x] Mac-compatible testing container running
- [x] Comprehensive documentation

### ⏳ Phase 4: RunPod Deployment (Ready)
- [ ] Push Docker image to Docker Hub
- [ ] Create RunPod network volume
- [ ] Initialize volume with GPU pod
- [ ] Deploy serverless endpoint
- [ ] Production testing

**Deployment Guide**: [RUNPOD_DEPLOYMENT.md](RUNPOD_DEPLOYMENT.md)

---

## 🎯 Architecture Overview

```
┌─────────────────────────────────────────────────┐
│          GitHub Actions (Native AMD64)          │
│                                                 │
│  1. Triggered by git push                       │
│  2. Build Docker image (5-8 min)                │
│  3. Push to GHCR                                │
│  4. Verify architecture = amd64                 │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│   GitHub Container Registry (ghcr.io)           │
│   • Image: comfyui-wan-serverless               │
│   • Tags: latest, v1.0.0, main-sha              │
│   • Size: ~3GB                                  │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│              RunPod Serverless                  │
│                                                 │
│  Docker Image (3GB)    Network Volume (100GB)   │
│  ├─ ComfyUI code      ├─ models/ (65GB)        │
│  ├─ handler.py        ├─ venv/ (8GB)           │
│  └─ warmup.py         └─ custom_nodes/         │
└─────────────────────────────────────────────────┘
```

---

## 🔍 Mac-Specific Considerations

### Why GitHub Actions?

Building Docker images on Mac for Linux requires cross-platform emulation:

| Platform | Build Time | Method |
|----------|------------|--------|
| Mac → Linux | 20-40 min | QEMU emulation (slow) |
| Linux → Linux | 5-8 min | Native (fast) |

GitHub Actions provides **free** Linux runners = **4x faster builds**!

### Platform Architecture

```dockerfile
# Always use --platform flag for Mac builds
FROM --platform=linux/amd64 runpod/pytorch:2.4.0-py3.11-cuda12.1.1-devel-ubuntu22.04
```

This ensures the image works on RunPod's AMD64 servers.

### Verification

```bash
# Check built image architecture
docker inspect IMAGE_NAME | grep Architecture

# Must show: "amd64" (NOT "arm64")
```

---

## 📊 Cost Analysis

### GitHub Actions Minutes

| Repository | Free Minutes | Build Time | Builds/Month |
|------------|--------------|------------|--------------|
| Public | 2,000 min/month | 5-8 min | ~250-400 |
| Private | 2,000 min/month | 5-8 min | ~250-400 |

**Conclusion**: More than enough for typical development!

### GitHub Container Registry

| Tier | Storage | Bandwidth |
|------|---------|-----------|
| Free | 500MB | Unlimited (public) |
| Image Size | ~3GB compressed | - |

**Tip**: Delete old versions to stay within free tier.

### RunPod Serverless (After Deployment)

| Component | Cost/Month (10 req/day) |
|-----------|-------------------------|
| Network Volume (100GB) | $10 |
| Compute (RTX 4090) | $15 |
| S3 Storage | $2 |
| **Total** | **~$27** |

**vs Persistent Pod**: $360/month = **92% savings**!

---

## 🛠️ Troubleshooting

### Build Failed

```bash
# View logs
gh run list
gh run view <run-id> --log

# Or via web: GitHub → Actions → Click on failed run
```

### Wrong Architecture (arm64 instead of amd64)

**Check**: Dockerfile starts with `--platform=linux/amd64`
**Fix**: Add platform flag and rebuild

### Can't Push to GHCR

**Cause**: Insufficient permissions
**Fix**:
1. Repo Settings → Actions → General
2. Workflow permissions → "Read and write"
3. Save and re-run

### Package Not Visible

**Cause**: Package is private by default
**Fix**:
1. GitHub Profile → Packages
2. Click package → Settings
3. Change visibility → Public

---

## 📚 Additional Resources

- **Implementation Plan**: [_design_docs/SERVERLESS_IMPLEMENTATION.md](../_design_docs/SERVERLESS_IMPLEMENTATION.md)
- **GitHub Actions Guide**: [README-GITHUB-ACTIONS.md](./README-GITHUB-ACTIONS.md)
- **Quick Start**: [QUICKSTART.md](./QUICKSTART.md)
- **RunPod Docs**: https://docs.runpod.io/serverless/overview
- **GitHub Actions Docs**: https://docs.github.com/en/actions
- **GHCR Docs**: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry

---

## ✅ Verification Checklist

Before deploying to RunPod:

- [ ] Workflow file exists: `.github/workflows/build-docker-serverless.yml`
- [ ] Dockerfile has `--platform=linux/amd64` flag
- [ ] `.dockerignore` excludes models, venv, output
- [ ] Code pushed to GitHub
- [ ] Build completed successfully (Actions tab)
- [ ] Image architecture verified (amd64)
- [ ] Package made public in GHCR
- [ ] Image URL copied for RunPod template

---

## 🎯 Next Steps

1. **Complete this setup** (you are here!)
2. **Implement handler.py** - Core serverless logic
3. **Implement warmup.py** - Cold start optimization
4. **Create init script** - Network volume setup
5. **Test locally** - Docker Compose validation
6. **Deploy to RunPod** - Create serverless endpoint
7. **Production testing** - Verify cold/warm starts

---

## 💡 Tips

- **Use GitHub Actions** for all production builds (4x faster)
- **Make packages public** to avoid authentication hassles
- **Use semver tags** (v1.0.0) for versioned releases
- **Monitor build cache** to speed up subsequent builds
- **Delete old images** to stay within free storage tier

---

## 🤝 Contributing

This is part of the ComfyUI WAN project. For issues or improvements:
1. Check existing issues/PRs
2. Test changes locally first
3. Submit PR with description

---

**Status**: ✅ Implementation complete - Ready for RunPod deployment!

**Build Time**: Mac local (20-40 min) → GitHub Actions (5-8 min) = **4x faster!** 🚀

**Next Step**: Follow [PREFLIGHT_CHECKLIST.md](PREFLIGHT_CHECKLIST.md) then [RUNPOD_DEPLOYMENT.md](RUNPOD_DEPLOYMENT.md)
