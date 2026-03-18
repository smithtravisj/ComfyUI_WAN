# Git Setup for Serverless Deployment

## Current Situation

Your local repository is pointing to the original ComfyUI repo, which you don't have write access to.

**Current remote:**
```
origin → https://github.com/comfyanonymous/ComfyUI.git
```

**Current branch:** `master` (not `main`)

---

## Solution: Set Up Your Own Repository

### Step 1: Create New GitHub Repository

1. Go to https://github.com/new
2. Repository name: `ComfyUI_WAN` (or your preferred name)
3. Description: "ComfyUI WAN 2.2 Serverless on RunPod"
4. **Public** (required for free GitHub Actions)
5. **Don't** initialize with README (you already have code)
6. Click "Create repository"

### Step 2: Update Git Remote

```bash
cd /Users/travissmith/Projects/ComfyUI_WAN

# Rename current remote (backup)
git remote rename origin upstream

# Add your new repository as origin
git remote add origin https://github.com/YOUR_USERNAME/ComfyUI_WAN.git

# Verify
git remote -v
```

**Expected output:**
```
origin    https://github.com/YOUR_USERNAME/ComfyUI_WAN.git (fetch)
origin    https://github.com/YOUR_USERNAME/ComfyUI_WAN.git (push)
upstream  https://github.com/comfyanonymous/ComfyUI.git (fetch)
upstream  https://github.com/comfyanonymous/ComfyUI.git (push)
```

### Step 3: Push Your Code

```bash
# Stage all changes (serverless files and archive)
git add .

# Commit
git commit -m "Add serverless implementation with RunPod deployment"

# Push to YOUR repository on master branch
git push -u origin master
```

**Note**: The branch is `master`, not `main`

### Step 4: Enable GitHub Actions

After pushing:

1. Go to your repository: `https://github.com/YOUR_USERNAME/ComfyUI_WAN`
2. Click **Settings** tab
3. Go to **Actions** → **General**
4. Under "Workflow permissions":
   - Select **"Read and write permissions"**
   - Check **"Allow GitHub Actions to create and approve pull requests"**
5. Click **Save**

### Step 5: Trigger Build

The push should automatically trigger the GitHub Actions build workflow.

**Check build status:**
```bash
# Using gh CLI
gh run watch

# Or visit:
# https://github.com/YOUR_USERNAME/ComfyUI_WAN/actions
```

---

## Alternative: Keep Existing Setup

If you want to keep the original ComfyUI as `origin`:

```bash
# Add your fork as a new remote
git remote add myfork https://github.com/YOUR_USERNAME/ComfyUI_WAN.git

# Push to your fork
git push -u myfork master
```

Then update GitHub Actions to use `myfork` remote.

---

## Quick Commands Reference

### Check Current Setup
```bash
git remote -v              # Show remotes
git branch -a              # Show branches
git status                 # Current changes
```

### Change Remote
```bash
git remote set-url origin https://github.com/YOUR_USERNAME/ComfyUI_WAN.git
```

### Force Push (if needed)
```bash
git push -f origin master  # Use carefully!
```

---

## For GitHub Actions to Work

The `.github/workflows/build-docker-serverless.yml` workflow will:

1. **Trigger on**: Push to `master` branch (not `main`)
2. **Build**: Docker image on AMD64
3. **Push to**: GitHub Container Registry (ghcr.io)
4. **Duration**: 5-8 minutes

**After successful build:**
- Image: `ghcr.io/YOUR_USERNAME/comfyui_wan/comfyui-wan-serverless:latest`
- Make package public: GitHub → Packages → Settings → Public

---

## Summary

1. ✅ Create new GitHub repository
2. ✅ Add as `origin` remote
3. ✅ Push your code (`git push origin master`)
4. ✅ Enable GitHub Actions permissions
5. ✅ Wait for build (5-8 min)
6. ✅ Make package public
7. ✅ Use in RunPod deployment

**Your branch is `master`, not `main`** - update any documentation references accordingly.
