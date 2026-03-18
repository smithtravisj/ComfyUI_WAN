# RunPod Deployment Pre-Flight Checklist

Complete this checklist before deploying to RunPod.

## ✅ Required Files Verification

### Core Serverless Files
- [x] `serverless/handler.py` - Main serverless handler (16K)
- [x] `serverless/warmup.py` - Model warmup logic (6.0K)
- [x] `serverless/test_handler.py` - Testing script (8.8K)
- [x] `Dockerfile` - Container definition (3.5K)

### Initialization Scripts
- [x] `serverless/init_network_volume.sh` - RunPod volume setup (12K)
- [x] `serverless/init_workspace_docker_only.sh` - Local testing setup
- [x] `serverless/verify.sh` - Verification script (8.8K)

### Configuration Files
- [x] `serverless/runpod_template.json` - RunPod endpoint template (7.4K)
- [x] `serverless/docker-compose.test.yml` - Local GPU testing
- [x] `serverless/docker-compose.mac.yml` - Mac CPU testing
- [x] `.dockerignore` - Build context optimization (1.3K)

### Documentation
- [x] `serverless/RUNPOD_DEPLOYMENT.md` - Complete deployment guide
- [x] `serverless/STATUS.md` - Current status and limitations
- [x] `serverless/PREFLIGHT_CHECKLIST.md` - This file

## ✅ Docker Image Verification

### Local Build Status
```bash
# Check image exists
docker images | grep comfyui-wan-serverless
```
- [x] Image built: `comfyui-wan-serverless:test`
- [x] Size: 6.75GB
- [x] Platform: linux/amd64
- [x] Base: nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

### Docker Hub Preparation (Required for RunPod)
```bash
# Tag for Docker Hub
docker tag comfyui-wan-serverless:test YOUR_USERNAME/comfyui-wan-serverless:latest

# Login to Docker Hub
docker login

# Push to Docker Hub
docker push YOUR_USERNAME/comfyui-wan-serverless:latest
```
- [x] Docker Hub account created
- [x] Image tagged with username
- [x] Image pushed to Docker Hub
- [x] Image is public or RunPod has access

**Alternative**: Use GitHub/GitLab and let RunPod build

## ✅ RunPod Account Setup

### Account Requirements
- [x] RunPod account created at https://www.runpod.io/
- [x] Email verified
- [x] Billing method added (credit card or credits)
- [x] API key generated (Account Settings → API Keys)

### Cost Understanding
- [x] Understand GPU costs (~$0.34/second for RTX 4090)
- [x] Understand network volume costs (~$10/month per 100GB)
- [x] Budget allocated for initial testing ($50-100 recommended)

## ✅ Network Volume Preparation

### Volume Creation Checklist
- [x] Network volume created in RunPod
- [x] Name: `comfyui-wan-2-2-models` (or your chosen name)
- [x] Size: 100GB minimum (150GB recommended)
- [x] Region selected (closest to your users)
- [x] Volume ID noted for reference

### Volume Initialization Plan
- [ ] GPU pod type selected (RTX 4090, A5000, or A6000)
- [ ] Temporary pod budget allocated (~$0.50-1.00 for 30-40 mins)
- [ ] Time allocated for 30-40 minute initialization
- [ ] Stable internet connection for model downloads

## ✅ Code Repository

### Git Repository Status
```bash
# Check git status
git status
git remote -v
```
- [ ] All serverless code committed to git
- [ ] Repository pushed to GitHub/GitLab/Bitbucket
- [ ] Repository is public OR RunPod has access
- [ ] Latest changes pushed to `main` or `master` branch

**Repository checklist:**
- [ ] `Dockerfile` in repository root
- [ ] `serverless/` directory with all scripts
- [ ] `.dockerignore` configured
- [ ] `requirements.txt` for ComfyUI (if using)

## ✅ Optional: S3/R2 Storage

If you want outputs uploaded to cloud storage:

### Cloudflare R2 Setup (Recommended)
- [ ] Cloudflare account created
- [ ] R2 enabled (no egress fees!)
- [ ] Bucket created (e.g., `comfyui-outputs`)
- [ ] R2 API token created with read/write permissions
- [ ] Public bucket URL configured (optional, for direct links)

**Credentials to note:**
- Account ID: `__________________`
- Access Key: `__________________`
- Secret Key: `__________________` (keep secure!)
- Endpoint: `https://YOUR_ACCOUNT.r2.cloudflarestorage.com`
- Bucket: `__________________`
- Public URL: `https://pub-xxxxx.r2.dev` (if configured)

### Alternative: AWS S3
- [ ] AWS account with S3 access
- [ ] S3 bucket created
- [ ] IAM user with S3 permissions
- [ ] Access keys generated

## ✅ Workflow Files

### Example Workflows
```bash
# Check workflow files exist
ls -lh serverless/examples/*.json
```
- [ ] `examples/minimal_validation.json` - Basic test workflow
- [ ] `examples/t2v_workflow.json` - Text-to-video workflow
- [ ] Custom workflows prepared (if any)

### Workflow Validation
- [ ] Workflows tested locally with ComfyUI
- [ ] Node IDs match your ComfyUI version
- [ ] Custom nodes are included in Docker image
- [ ] Workflow parameters are reasonable

## ✅ Environment Variables

### Required for Endpoint
```bash
# Paths (always required)
MODELS_DIR=/workspace/models
OUTPUT_DIR=/workspace/output
TEMP_DIR=/workspace/temp
VENV_PATH=/workspace/venv

# Cache (always required)
CACHE_TYPE=RAM_PRESSURE
CACHE_RAM=16.0

# Features
WARMUP_MODELS=true
CLEANUP_OUTPUTS=true

# CUDA optimization
CUDA_MODULE_LOADING=LAZY
PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
```

### Optional for S3/R2
```bash
R2_ENDPOINT=https://YOUR_ACCOUNT.r2.cloudflarestorage.com
R2_ACCESS_KEY=your_access_key
R2_SECRET_KEY=your_secret_key
R2_BUCKET=comfyui-outputs
R2_PUBLIC_URL=https://pub-xxxxx.r2.dev
```

- [ ] All required variables prepared
- [ ] S3/R2 variables prepared (if using cloud storage)
- [ ] Sensitive values kept secure (not in git!)

## ✅ Testing Plan

### Local Testing (Already Done)
- [x] Docker image builds successfully
- [x] Container starts without errors
- [x] Workspace structure verified
- [x] Models accessible via symlinks

### RunPod Testing Phases
- [ ] **Phase 1**: Network volume initialization (~40 mins)
- [ ] **Phase 2**: Serverless endpoint deployment (~5 mins)
- [ ] **Phase 3**: Minimal validation test (~30 seconds)
- [ ] **Phase 4**: Full T2V workflow test (~60 seconds)
- [ ] **Phase 5**: Burst test with multiple concurrent requests

### Success Criteria
- [ ] Cold start < 15 seconds
- [ ] Warm start < 2 seconds
- [ ] T2V generation completes in < 90 seconds
- [ ] Outputs uploaded to S3/R2 successfully
- [ ] No memory errors or crashes
- [ ] Workers scale up/down correctly

## ✅ Monitoring & Observability

### Monitoring Setup
- [ ] RunPod dashboard accessible
- [ ] Log viewing tested
- [ ] Metrics understand (requests, duration, errors)
- [ ] Alerts configured (optional)

### Debug Tools Ready
- [ ] `test_handler.py` script tested locally
- [ ] API key environment variable set
- [ ] Endpoint URL format understood
- [ ] Log analysis skills prepared

## ✅ Documentation Review

### Have You Read?
- [ ] Complete `RUNPOD_DEPLOYMENT.md` guide
- [ ] Understand `STATUS.md` limitations
- [ ] Familiar with `handler.py` logic
- [ ] Reviewed `runpod_template.json` configuration

### Do You Understand?
- [ ] Serverless vs persistent pods difference
- [ ] Network volume purpose and persistence
- [ ] Cold vs warm start concepts
- [ ] Burst scaling behavior
- [ ] Idle timeout implications

## ✅ Support Resources

### Documentation Links
- [ ] Bookmarked: https://docs.runpod.io/serverless/overview
- [ ] Bookmarked: https://docs.runpod.io/serverless/endpoints/create-an-endpoint
- [ ] Bookmarked: https://discord.gg/runpod (support)

### Backup Plan
- [ ] Time allocated for troubleshooting
- [ ] Budget for extended testing if needed
- [ ] Fallback to persistent pod if serverless issues

---

## 🚀 Ready to Deploy?

### Quick Pre-Flight Check
1. ✅ Docker image built and accessible
2. ✅ RunPod account with billing
3. ⬜ Network volume ready
4. ⬜ Code in git repository
5. ⬜ Environment variables prepared
6. ⬜ Testing plan understood

### Deployment Steps Summary
1. **Create network volume** (2 mins)
2. **Initialize volume with GPU pod** (40 mins)
3. **Push Docker image to Docker Hub** (10 mins)
4. **Create serverless endpoint** (5 mins)
5. **Test with minimal workflow** (1 min)
6. **Test with full T2V workflow** (2 mins)
7. **Monitor and optimize** (ongoing)

### Estimated Time to First Working Endpoint
- **Minimum**: 1 hour (if everything works perfectly)
- **Realistic**: 1.5-2 hours (with troubleshooting)
- **Maximum**: 3 hours (with significant issues)

### Estimated Costs for Setup
- Network volume initialization pod: $0.50-1.00 (one-time)
- Network volume storage: $10/month (ongoing)
- Serverless GPU time: Pay per request (varies)
- Testing (first day): $5-10
- **Total first month**: ~$15-30 for moderate usage

---

## 📋 Deployment Command Reference

### Docker Hub Push
```bash
docker tag comfyui-wan-serverless:test YOUR_USERNAME/comfyui-wan-serverless:latest
docker login
docker push YOUR_USERNAME/comfyui-wan-serverless:latest
```

### Network Volume Initialization
```bash
# In RunPod GPU pod terminal
cd /workspace
git clone YOUR_REPO_URL
cd ComfyUI_WAN
chmod +x serverless/init_network_volume.sh
bash serverless/init_network_volume.sh
```

### Local Testing (Post-Deployment)
```bash
export RUNPOD_ENDPOINT_ID="your_endpoint_id"
export RUNPOD_API_KEY="your_api_key"

python serverless/test_handler.py --remote \
  --endpoint "https://api.runpod.ai/v2/${RUNPOD_ENDPOINT_ID}/runsync" \
  --workflow serverless/examples/minimal_validation.json
```

---

## ✅ Final Sign-Off

- [ ] All critical items checked
- [ ] Budget allocated and approved
- [ ] Time allocated for deployment
- [ ] Understand rollback if needed
- [ ] Ready to proceed with deployment

**Deployment Date**: _______________
**Completed By**: _______________
**Endpoint ID** (after deployment): _______________

---

**Next Step**: Follow [RUNPOD_DEPLOYMENT.md](RUNPOD_DEPLOYMENT.md) Phase 1: Network Volume Setup
