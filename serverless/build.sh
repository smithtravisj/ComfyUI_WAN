#!/usr/bin/env bash
#
# Build and push Docker image for ComfyUI WAN serverless
# Mac-compatible with GitHub Actions integration
#
# Usage:
#   ./build.sh [tag] [--push|--no-push] [--local|--github]
#
# Examples:
#   ./build.sh latest --push              # Build and push latest
#   ./build.sh v1.0.0 --no-push          # Build v1.0.0 locally (testing)
#   ./build.sh latest --github            # Trigger GitHub Actions build

set -euo pipefail

# Configuration
REGISTRY="${REGISTRY:-ghcr.io/$(git config user.name | tr '[:upper:]' '[:lower:]')}"
REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"
IMAGE_NAME="${IMAGE_NAME:-${REPO_NAME}/comfyui-wan-serverless}"
TAG="${1:-latest}"
PUSH="${2:-}"
BUILD_METHOD="${3:-}"
FULL_IMAGE="$REGISTRY/$IMAGE_NAME:$TAG"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ${NC} $*"
}

log_success() {
    echo -e "${GREEN}✓${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $*"
}

log_error() {
    echo -e "${RED}✗${NC} $*"
}

print_header() {
    echo ""
    echo "===================================================================="
    echo "$*"
    echo "===================================================================="
    echo ""
}

# Parse arguments
SHOULD_PUSH=true
case "$PUSH" in
    --no-push)
        SHOULD_PUSH=false
        ;;
    --push)
        SHOULD_PUSH=true
        ;;
    *)
        if [[ -n "$PUSH" && "$PUSH" != "--local" && "$PUSH" != "--github" ]]; then
            log_error "Invalid argument: $PUSH"
            echo "Usage: $0 [tag] [--push|--no-push] [--local|--github]"
            exit 1
        fi
        ;;
esac

# GitHub Actions build
if [[ "$BUILD_METHOD" == "--github" || "$PUSH" == "--github" ]]; then
    print_header "Triggering GitHub Actions Build"

    if ! command -v gh &>/dev/null; then
        log_error "GitHub CLI (gh) not found. Install from: https://cli.github.com/"
        exit 1
    fi

    log_info "Tag: $TAG"
    log_info "This will trigger a GitHub Actions workflow to build natively on AMD64"
    log_info "Build time: ~5-8 minutes (vs 20-40 minutes locally on Mac)"
    echo ""

    read -p "Continue? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Cancelled"
        exit 0
    fi

    log_info "Triggering workflow..."
    gh workflow run build-docker-serverless.yml \
        -f tag="$TAG" \
        -f push_image="true"

    log_success "Workflow triggered!"
    echo ""
    log_info "Monitor progress: gh run watch"
    log_info "View all runs: gh run list --workflow=build-docker-serverless.yml"
    exit 0
fi

# Local build
print_header "Building Docker Image for RunPod (linux/amd64)"

log_info "Image: $FULL_IMAGE"
log_info "Platform: linux/amd64 (RunPod compatible)"
log_info "Push to registry: $SHOULD_PUSH"
echo ""

# Detect platform
IS_MAC=false
IS_ARM=false
if [[ "$(uname -s)" == "Darwin" ]]; then
    IS_MAC=true
    if [[ "$(uname -m)" == "arm64" ]]; then
        IS_ARM=true
    fi
fi

# Mac-specific warnings and setup
if [[ "$IS_MAC" == true ]]; then
    log_warning "Detected macOS"

    if [[ "$IS_ARM" == true ]]; then
        log_warning "Apple Silicon (ARM) detected - cross-compilation required"
    fi

    echo ""
    log_info "Cross-platform build uses QEMU emulation"
    log_info "Estimated build time: 20-40 minutes"
    echo ""
    log_warning "💡 TIP: For faster builds, use GitHub Actions:"
    log_warning "   $0 $TAG --github"
    echo ""

    read -p "Continue with local build? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Cancelled. Run with --github for faster builds."
        exit 0
    fi

    # Check if buildx is available
    if ! docker buildx version &>/dev/null; then
        log_error "Docker buildx not available"
        log_error "Please update Docker Desktop to the latest version"
        exit 1
    fi

    # Create/use multiarch builder
    log_info "Setting up multiarch builder..."
    docker buildx create --name comfyui-multiarch --use 2>/dev/null || docker buildx use comfyui-multiarch
    docker buildx inspect --bootstrap

    # Build with buildx
    print_header "Building with Docker Buildx (QEMU Emulation)"

    BUILD_CMD=(
        docker buildx build
        --platform linux/amd64
        --tag "$FULL_IMAGE"
        --progress=plain
        --build-arg "BUILDTIME=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        --build-arg "VERSION=$TAG"
        --build-arg "REVISION=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
    )

    if [[ "$SHOULD_PUSH" == true ]]; then
        BUILD_CMD+=(--push)
    else
        BUILD_CMD+=(--load)
    fi

    BUILD_CMD+=(.)

else
    # Linux: Native build
    log_success "Detected Linux - using native build"
    echo ""

    print_header "Building with Docker (Native AMD64)"

    BUILD_CMD=(
        docker build
        --platform linux/amd64
        --tag "$FULL_IMAGE"
        --progress=plain
        --build-arg "BUILDTIME=$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
        --build-arg "VERSION=$TAG"
        --build-arg "REVISION=$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
        .
    )
fi

# Execute build
log_info "Running: ${BUILD_CMD[*]}"
echo ""

if "${BUILD_CMD[@]}"; then
    log_success "Build completed successfully"
else
    log_error "Build failed"
    exit 1
fi

# Verification
print_header "Verifying Image Architecture"

if [[ "$SHOULD_PUSH" == false || "$IS_MAC" == false ]]; then
    # Pull image to verify if pushed, or check local if not
    if [[ "$SHOULD_PUSH" == true ]]; then
        log_info "Pulling image from registry..."
        docker pull "$FULL_IMAGE"
    fi

    ARCH=$(docker inspect "$FULL_IMAGE" 2>/dev/null | grep -m1 "Architecture" | awk '{print $2}' | tr -d '",')

    if [[ -z "$ARCH" ]]; then
        log_error "Could not determine image architecture"
        exit 1
    fi

    log_info "Architecture: $ARCH"

    if [[ "$ARCH" != "amd64" ]]; then
        log_error "Image is $ARCH, expected amd64!"
        log_error "This image will NOT work on RunPod"
        exit 1
    fi

    log_success "Correct architecture (amd64)"

    # Show image size
    SIZE=$(docker image inspect "$FULL_IMAGE" 2>/dev/null | grep -m1 "Size" | awk '{print $2}' | tr -d '",')
    if [[ -n "$SIZE" ]]; then
        SIZE_MB=$((SIZE / 1024 / 1024))
        log_info "Image size: ${SIZE_MB}MB"
    fi
fi

# Push if requested and not already pushed by buildx
if [[ "$SHOULD_PUSH" == true && "$IS_MAC" == false ]]; then
    print_header "Pushing to Registry"
    docker push "$FULL_IMAGE"
    log_success "Image pushed successfully"
fi

# Summary
print_header "Build Summary"

echo "✓ Image: $FULL_IMAGE"
echo "✓ Platform: linux/amd64"
echo "✓ Registry: $REGISTRY"

if [[ "$SHOULD_PUSH" == true ]]; then
    echo "✓ Status: Pushed to registry"
else
    echo "✓ Status: Built locally (not pushed)"
fi

echo ""
log_info "Next steps:"
echo "  1. Update RunPod template with image: $FULL_IMAGE"
echo "  2. Deploy serverless endpoint"
echo "  3. Test with example workflow"
echo ""

if [[ "$IS_MAC" == true ]]; then
    log_warning "Note: Built with cross-compilation (slow)"
    log_warning "For production builds, use GitHub Actions: $0 $TAG --github"
fi
