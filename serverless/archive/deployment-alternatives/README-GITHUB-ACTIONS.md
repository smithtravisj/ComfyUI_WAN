# GitHub Actions Docker Build Guide

This guide explains how to use GitHub Actions to build Docker images for RunPod serverless deployment from a Mac.

## Why GitHub Actions?

Building Docker images on Mac for Linux (AMD64) requires cross-platform emulation, which is **20-40 minutes** slow. GitHub Actions provides native AMD64 builders that complete in **5-8 minutes**.

### Build Time Comparison

| Method | Platform | Build Time | Cost |
|--------|----------|------------|------|
| **Mac Local** | ARM64 → AMD64 (emulation) | 20-40 min | Free |
| **GitHub Actions** | Native AMD64 | 5-8 min | Free* |
| **RunPod Build Pod** | Native AMD64 | 5-8 min | ~$0.10 |

*Free for public repos, generous limits for private repos

---

## Setup Instructions

### 1. Enable GitHub Container Registry (GHCR)

GitHub Container Registry is already enabled by default. No additional setup needed!

The workflow is configured to push images to:
```
ghcr.io/YOUR_USERNAME/comfyui_wan/comfyui-wan-serverless:latest
```

### 2. Verify Workflow File Exists

Check that this file exists:
```
.github/workflows/build-docker-serverless.yml
```

This was created automatically and is ready to use.

### 3. Push to GitHub

```bash
# Add all serverless files
git add .github/workflows/build-docker-serverless.yml
git add Dockerfile
git add .dockerignore
git add serverless/

# Commit
git commit -m "Add serverless Docker build with GitHub Actions"

# Push to trigger build
git push origin main
```

**Note**: The workflow triggers on pushes to `main`, `master`, or `develop` branches.

---

## Using the Workflow

### Method 1: Automatic Builds (Recommended)

Builds trigger automatically when you push changes to:
- `Dockerfile`
- Any file in `serverless/`
- `.github/workflows/build-docker-serverless.yml`

```bash
# Make changes to serverless files
vim serverless/handler.py

# Commit and push
git add serverless/handler.py
git commit -m "Update handler logic"
git push origin main

# GitHub Actions will automatically build and push the image
```

### Method 2: Manual Trigger with Custom Tag

Use the `build.sh` script with the `--github` flag:

```bash
cd serverless

# Trigger build with custom tag
./build.sh v1.0.0 --github

# Or use latest tag
./build.sh latest --github
```

This will:
1. Ask for confirmation
2. Trigger GitHub Actions workflow
3. Provide commands to monitor progress

### Method 3: GitHub Web UI

1. Go to your repository on GitHub
2. Click **Actions** tab
3. Select **Build Serverless Docker Image** workflow
4. Click **Run workflow** dropdown (right side)
5. Enter tag (e.g., `v1.0.0`) and click **Run workflow**

---

## Monitoring Builds

### Using GitHub CLI (Recommended)

```bash
# Install GitHub CLI if not already installed
brew install gh

# Authenticate
gh auth login

# Watch the running build
gh run watch

# List recent runs
gh run list --workflow=build-docker-serverless.yml

# View specific run details
gh run view <run-id>
```

### Using GitHub Web UI

1. Go to repository → **Actions** tab
2. Click on the running workflow
3. Click on the **Build Docker Image (AMD64)** job
4. Expand steps to see real-time logs

---

## Understanding the Workflow

### Trigger Conditions

The workflow runs when:
1. **Push to main/master/develop** with changes to:
   - `Dockerfile`
   - `serverless/**`
   - `.github/workflows/build-docker-serverless.yml`

2. **Pull Request** to main/master (builds but doesn't push)

3. **Manual trigger** via `workflow_dispatch`

### Build Process

```yaml
jobs:
  build:
    runs-on: ubuntu-latest  # ✓ Native AMD64
    steps:
      1. Checkout code
      2. Setup Docker Buildx
      3. Login to GHCR
      4. Extract metadata (tags, labels)
      5. Build and push image
      6. Verify architecture is amd64
      7. Generate summary
```

### Image Tags

Images are automatically tagged with:
- `latest` - For pushes to default branch (main/master)
- `main-<sha>` - Branch name + commit SHA
- `pr-<number>` - For pull requests (not pushed)
- `v1.0.0` - For semver tags
- `<custom>` - For manual triggers with custom tag input

Example tags for a push to main:
```
ghcr.io/yourname/comfyui_wan/comfyui-wan-serverless:latest
ghcr.io/yourname/comfyui_wan/comfyui-wan-serverless:main-abc1234
```

---

## Using Built Images

### 1. View Available Images

**GitHub Web UI**:
1. Go to your repository
2. Click **Packages** (right sidebar)
3. Click on `comfyui-wan-serverless`
4. See all available tags and their details

**GitHub CLI**:
```bash
gh api user/packages/container/comfyui_wan%2Fcomfyui-wan-serverless/versions
```

**Docker CLI**:
```bash
# Login to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# List tags (requires API call)
curl -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://ghcr.io/v2/USERNAME/comfyui_wan/comfyui-wan-serverless/tags/list
```

### 2. Pull Image Locally

```bash
# Login first
echo $GITHUB_TOKEN | docker login ghcr.io -u USERNAME --password-stdin

# Pull image
docker pull ghcr.io/USERNAME/comfyui_wan/comfyui-wan-serverless:latest

# Verify architecture
docker inspect ghcr.io/USERNAME/comfyui_wan/comfyui-wan-serverless:latest | grep Architecture
# Should show: "amd64"
```

### 3. Use in RunPod Template

Update your RunPod serverless template JSON:

```json
{
  "name": "ComfyUI WAN 2.2 Serverless",
  "dockerImage": "ghcr.io/USERNAME/comfyui_wan/comfyui-wan-serverless:latest",
  ...
}
```

**Important**: Make the GHCR package public or provide RunPod with credentials:

**Option A: Make Package Public** (Recommended)
1. Go to package settings
2. Scroll to "Danger Zone"
3. Click "Change visibility"
4. Select "Public"

**Option B: Use Docker Registry Credentials in RunPod**
1. Generate GitHub Personal Access Token with `read:packages` scope
2. In RunPod template, add Docker registry credentials:
```json
{
  "dockerAuth": {
    "username": "YOUR_GITHUB_USERNAME",
    "password": "YOUR_GITHUB_TOKEN"
  }
}
```

---

## Advanced Usage

### Build Caching

The workflow uses GitHub Actions cache to speed up subsequent builds:

```yaml
cache-from: type=gha
cache-to: type=gha,mode=max
```

This means:
- First build: 5-8 minutes
- Subsequent builds (no changes): 2-3 minutes
- Subsequent builds (small changes): 3-5 minutes

### Building Specific Versions

Create a git tag to trigger versioned builds:

```bash
# Tag a commit
git tag v1.0.0
git push origin v1.0.0

# GitHub Actions will build and tag:
# - ghcr.io/.../comfyui-wan-serverless:v1.0.0
# - ghcr.io/.../comfyui-wan-serverless:1.0
# - ghcr.io/.../comfyui-wan-serverless:latest (if on default branch)
```

### Testing Builds in PRs

Pull requests trigger builds but **do not push** images:

```bash
# Create a branch
git checkout -b feature/update-handler

# Make changes
vim serverless/handler.py

# Commit and push
git commit -am "Update handler"
git push origin feature/update-handler

# Open PR on GitHub
# GitHub Actions will:
# - Build the image
# - Verify it's amd64
# - Comment on the PR with results
# - NOT push to registry
```

### Debugging Failed Builds

If a build fails:

1. **View logs**:
   ```bash
   gh run view <run-id> --log
   ```

2. **Common issues**:

   - **Architecture mismatch**: Check Dockerfile has `--platform=linux/amd64`
   - **Python wheel issues**: Check pip install uses correct flags
   - **Build context too large**: Check `.dockerignore` is present
   - **Out of disk space**: Image too large (>10GB)

3. **Re-run failed builds**:
   ```bash
   gh run rerun <run-id>
   ```

---

## Cost Considerations

### GitHub Actions Minutes

**Free Tier** (Public repositories):
- 2,000 minutes/month
- Each build: ~5-8 minutes
- **You can do ~250-400 builds/month for free**

**Free Tier** (Private repositories):
- 2,000 minutes/month for free tier
- Each build: ~5-8 minutes
- **You can do ~250-400 builds/month**

### GitHub Container Registry Storage

**Free Tier**:
- 500MB storage
- Unlimited public images
- 1GB bandwidth/month for private images

**Image Size**:
- ComfyUI WAN serverless: ~3GB compressed
- Can store ~1-2 versions with free tier
- Delete old versions to free space

### Managing Storage

**Delete old versions**:
1. Go to package → Versions
2. Click ⋮ next to old version
3. Click "Delete version"

**Automated cleanup** (add to workflow):
```yaml
- name: Delete old images
  uses: actions/delete-package-versions@v4
  with:
    package-name: 'comfyui_wan/comfyui-wan-serverless'
    min-versions-to-keep: 3
    delete-only-untagged-versions: 'true'
```

---

## Comparison: GitHub Actions vs Local Build

### GitHub Actions ✅ (Recommended)

**Pros**:
- ✅ Fast: 5-8 minute builds (native AMD64)
- ✅ Free: 2,000 minutes/month
- ✅ Automatic: Triggers on git push
- ✅ Reliable: Consistent build environment
- ✅ Cached: Layer caching speeds up rebuilds
- ✅ Verified: Auto-checks architecture

**Cons**:
- ❌ Requires git push
- ❌ Internet dependency
- ❌ Limited to 2,000 minutes/month

### Local Build (Mac) ⚠️

**Pros**:
- ✅ No git push required
- ✅ Immediate local testing
- ✅ No minute limits

**Cons**:
- ❌ Slow: 20-40 minute builds (QEMU emulation)
- ❌ Resource intensive (CPU + memory)
- ❌ Manual architecture verification needed

### When to Use Each

**Use GitHub Actions**:
- Production builds
- Regular development workflow
- Team collaboration
- CI/CD integration

**Use Local Build**:
- Quick testing without git push
- Offline development
- Exceeded GitHub Actions minutes

---

## Troubleshooting

### "Resource not accessible by integration" Error

**Problem**: Workflow can't push to GHCR

**Solution**:
1. Go to repo Settings → Actions → General
2. Scroll to "Workflow permissions"
3. Select "Read and write permissions"
4. Save

### "Failed to push" Error

**Problem**: Package doesn't exist yet

**Solution**: First push creates the package. Make it public:
1. Go to your GitHub profile
2. Click "Packages"
3. Click on the package
4. Settings → Change visibility → Public

### Image Architecture Wrong

**Problem**: Image shows arm64 instead of amd64

**Solution**: Check Dockerfile has:
```dockerfile
FROM --platform=linux/amd64 runpod/pytorch:...
```

And build command uses:
```bash
docker buildx build --platform linux/amd64 ...
```

---

## Next Steps

1. ✅ Push code to GitHub to trigger first build
2. ✅ Monitor build in Actions tab
3. ✅ Make GHCR package public
4. ✅ Update RunPod template with GHCR image URL
5. ✅ Deploy serverless endpoint
6. ✅ Test with example workflow

---

## Quick Reference

```bash
# Trigger build via script
./serverless/build.sh latest --github

# Watch build progress
gh run watch

# List recent builds
gh run list --workflow=build-docker-serverless.yml

# View build logs
gh run view <run-id> --log

# Pull built image
docker pull ghcr.io/USERNAME/comfyui_wan/comfyui-wan-serverless:latest

# Verify architecture
docker inspect ghcr.io/USERNAME/comfyui_wan/comfyui-wan-serverless:latest | grep Architecture
```

---

## Support

For issues with:
- **GitHub Actions**: Check [workflow logs](../../actions)
- **GHCR**: Check [package settings](../../packages)
- **Docker build**: Check [Dockerfile](../Dockerfile) and [.dockerignore](../.dockerignore)
- **RunPod**: Check [RunPod docs](https://docs.runpod.io)

---

**Ready to build?** Push your code to GitHub and watch it build automatically! 🚀
