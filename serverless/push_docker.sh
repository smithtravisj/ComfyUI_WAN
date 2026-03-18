#!/usr/bin/env bash
#
# Robust Docker Push Script for Large Images
# Handles network timeouts and retries automatically
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo "========================================================================"
    echo "$*"
    echo "========================================================================"
    echo ""
}

log_info() { echo -e "${BLUE}ℹ${NC} $*"; }
log_success() { echo -e "${GREEN}✓${NC} $*"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $*"; }
log_error() { echo -e "${RED}✗${NC} $*"; }

# Configuration
LOCAL_IMAGE="comfyui-wan-serverless:test"
DOCKERHUB_USERNAME="${1:-}"
MAX_RETRIES=5
RETRY_DELAY=10

if [[ -z "$DOCKERHUB_USERNAME" ]]; then
    log_error "Usage: $0 <dockerhub_username>"
    echo ""
    echo "Example:"
    echo "  $0 yourusername"
    echo ""
    exit 1
fi

REMOTE_IMAGE="${DOCKERHUB_USERNAME}/comfyui-wan-serverless:latest"

print_header "Docker Hub Push for Large Images"
log_info "Local image: $LOCAL_IMAGE"
log_info "Remote image: $REMOTE_IMAGE"
log_info "Max retries: $MAX_RETRIES"
echo ""

# Check if local image exists
if ! docker image inspect "$LOCAL_IMAGE" >/dev/null 2>&1; then
    log_error "Local image not found: $LOCAL_IMAGE"
    log_error "Please build the image first"
    exit 1
fi

IMAGE_SIZE=$(docker image inspect "$LOCAL_IMAGE" --format='{{.Size}}' | awk '{print $1/1024/1024/1024}')
log_info "Image size: $(printf "%.2f" "$IMAGE_SIZE")GB"
echo ""

# Check if already logged in
if ! docker info | grep -q "Username:"; then
    log_warning "Not logged into Docker Hub"
    echo ""
    log_info "Please log in to Docker Hub:"
    docker login
    echo ""
fi

# Tag the image
print_header "Tagging Image"
log_info "Tagging $LOCAL_IMAGE as $REMOTE_IMAGE"

if docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"; then
    log_success "Image tagged successfully"
else
    log_error "Failed to tag image"
    exit 1
fi

# Push with retries
print_header "Pushing to Docker Hub (with automatic retries)"
log_warning "This may take 10-30 minutes for a ${IMAGE_SIZE}GB image"
echo ""

ATTEMPT=1
while [[ $ATTEMPT -le $MAX_RETRIES ]]; do
    log_info "Attempt $ATTEMPT of $MAX_RETRIES..."
    echo ""

    if docker push "$REMOTE_IMAGE"; then
        echo ""
        log_success "Push completed successfully!"

        print_header "Verification"
        log_info "Image pushed to: https://hub.docker.com/r/${DOCKERHUB_USERNAME}/comfyui-wan-serverless"
        log_info "Pull command: docker pull $REMOTE_IMAGE"
        echo ""

        log_success "Next steps:"
        echo "  1. Verify image on Docker Hub (should be ~6.75GB)"
        echo "  2. Make repository public (if needed):"
        echo "     Docker Hub → Repositories → comfyui-wan-serverless → Settings"
        echo "  3. Use in RunPod template:"
        echo "     Container Image: $REMOTE_IMAGE"
        echo ""

        exit 0
    else
        EXIT_CODE=$?
        echo ""
        log_warning "Push failed with exit code $EXIT_CODE"

        if [[ $ATTEMPT -lt $MAX_RETRIES ]]; then
            log_info "Retrying in ${RETRY_DELAY} seconds..."
            sleep $RETRY_DELAY
            ATTEMPT=$((ATTEMPT + 1))

            # Exponential backoff
            RETRY_DELAY=$((RETRY_DELAY * 2))
        else
            log_error "Push failed after $MAX_RETRIES attempts"
            echo ""
            log_error "Troubleshooting steps:"
            echo "  1. Check Docker Desktop is running with enough resources"
            echo "  2. Check internet connection stability"
            echo "  3. Try increasing Docker Desktop memory (Settings → Resources → Memory)"
            echo "  4. Disable VPN if active"
            echo "  5. Try pushing during off-peak hours"
            echo ""
            log_info "Alternative: Use GitHub Container Registry (ghcr.io)"
            echo "  See README-GITHUB-ACTIONS.md for instructions"
            echo ""
            exit 1
        fi
    fi
done
