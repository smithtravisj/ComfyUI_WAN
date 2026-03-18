#!/usr/bin/env bash
#
# Verification script for ComfyUI WAN 2.2 serverless implementation
# Checks all components are in place before testing/deployment
#
# Usage:
#   ./verify.sh [--workspace PATH] [--verbose]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
WORKSPACE="${1:-./workspace}"
VERBOSE=false

if [[ "${2:-}" == "--verbose" || "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
check_pass() {
    echo -e "${GREEN}✓${NC} $*"
    PASSED=$((PASSED + 1))
}

check_fail() {
    echo -e "${RED}✗${NC} $*"
    FAILED=$((FAILED + 1))
}

check_warn() {
    echo -e "${YELLOW}⚠${NC} $*"
    WARNINGS=$((WARNINGS + 1))
}

print_header() {
    echo ""
    echo "========================================================================"
    echo "$*"
    echo "========================================================================"
    echo ""
}

# Start verification
print_header "ComfyUI WAN 2.2 Serverless Verification"

echo "Workspace: $WORKSPACE"
echo "Verbose: $VERBOSE"
echo ""

# =============================================================================
# 1. Serverless Files
# =============================================================================

print_header "[1/7] Serverless Files"

FILES=(
    "handler.py:Main handler"
    "warmup.py:Warmup script"
    "init_network_volume.sh:Initialization script"
    "runpod_template.json:RunPod template"
    "docker-compose.test.yml:Docker Compose config"
    "test_handler.py:Test script"
    ".env.example:Environment template"
    "build.sh:Build script"
    "deploy.py:Deployment script"
)

for entry in "${FILES[@]}"; do
    IFS=':' read -r file desc <<< "$entry"
    if [[ -f "$file" ]]; then
        check_pass "$desc ($file)"
        if [[ "$VERBOSE" == true ]]; then
            SIZE=$(du -h "$file" | cut -f1)
            echo "         Size: $SIZE"
        fi
    else
        check_fail "$desc missing ($file)"
    fi
done

# =============================================================================
# 2. Example Workflows
# =============================================================================

print_header "[2/7] Example Workflows"

WORKFLOWS=(
    "examples/minimal_validation.json:Minimal validation"
    "examples/t2v_simple.json:Simple T2V"
    "examples/t2v_lightning.json:Lightning T2V"
)

for entry in "${WORKFLOWS[@]}"; do
    IFS=':' read -r file desc <<< "$entry"
    if [[ -f "$file" ]]; then
        check_pass "$desc ($file)"
        if [[ "$VERBOSE" == true ]]; then
            NODES=$(jq 'keys | length' "$file" 2>/dev/null || echo "?")
            echo "         Nodes: $NODES"
        fi
    else
        check_warn "$desc missing ($file) - not critical"
    fi
done

# =============================================================================
# 3. Docker Configuration
# =============================================================================

print_header "[3/7] Docker Configuration"

# Check Dockerfile
if [[ -f "../Dockerfile" ]]; then
    check_pass "Dockerfile exists"

    # Check for critical directives
    if grep -q "FROM --platform=linux/amd64" ../Dockerfile; then
        check_pass "Platform set to linux/amd64"
    else
        check_fail "Platform not set to linux/amd64"
    fi

    if grep -q "runpod/pytorch" ../Dockerfile; then
        check_pass "Using RunPod PyTorch base image"
    else
        check_warn "Not using RunPod base image"
    fi
else
    check_fail "Dockerfile missing"
fi

# Check .dockerignore
if [[ -f "../.dockerignore" ]]; then
    check_pass ".dockerignore exists"
else
    check_warn ".dockerignore missing - may slow builds"
fi

# =============================================================================
# 4. Workspace Initialization
# =============================================================================

print_header "[4/7] Workspace Initialization"

if [[ ! -d "$WORKSPACE" ]]; then
    check_warn "Workspace not found ($WORKSPACE)"
    echo "         Run: bash init_network_volume.sh"
else
    check_pass "Workspace directory exists"

    # Check initialization marker
    if [[ -f "$WORKSPACE/.initialized" ]]; then
        check_pass "Workspace initialized"
        if [[ "$VERBOSE" == true ]]; then
            cat "$WORKSPACE/.initialized" | grep "Initialized:" || true
        fi
    else
        check_fail "Workspace not initialized"
        echo "         Run: bash init_network_volume.sh"
    fi

    # Check critical directories
    DIRS=(
        "models:Models directory"
        "models/unet:UNET models"
        "models/text_encoders:Text encoders"
        "models/vae:VAE models"
        "venv:Python venv"
        "output:Output directory"
    )

    for entry in "${DIRS[@]}"; do
        IFS=':' read -r dir desc <<< "$entry"
        if [[ -d "$WORKSPACE/$dir" ]]; then
            check_pass "$desc exists"
            if [[ "$VERBOSE" == true ]]; then
                COUNT=$(find "$WORKSPACE/$dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
                echo "         Files: $COUNT"
            fi
        else
            check_fail "$desc missing ($WORKSPACE/$dir)"
        fi
    done
fi

# =============================================================================
# 5. Model Files
# =============================================================================

print_header "[5/7] Model Files"

if [[ -d "$WORKSPACE/models" ]]; then
    # Critical models
    MODELS=(
        "vae/wan_2.1_vae.safetensors:VAE"
        "text_encoders/umt5-xxl-encoder-Q5_K_S.gguf:Text Encoder"
    )

    for entry in "${MODELS[@]}"; do
        IFS=':' read -r path desc <<< "$entry"
        if [[ -f "$WORKSPACE/models/$path" ]]; then
            check_pass "$desc exists"
            if [[ "$VERBOSE" == true ]]; then
                SIZE=$(du -h "$WORKSPACE/models/$path" | cut -f1)
                echo "         Size: $SIZE"
            fi
        else
            check_fail "$desc missing ($WORKSPACE/models/$path)"
        fi
    done

    # Count UNET models
    UNET_COUNT=$(find "$WORKSPACE/models/unet" -name "*.gguf" 2>/dev/null | wc -l)
    if [[ $UNET_COUNT -gt 0 ]]; then
        check_pass "UNET models found ($UNET_COUNT)"
    else
        check_fail "No UNET models found"
    fi

    # Count LoRAs
    LORA_COUNT=$(find "$WORKSPACE/models/loras" -name "*.safetensors" 2>/dev/null | wc -l)
    if [[ $LORA_COUNT -gt 0 ]]; then
        check_pass "LoRA models found ($LORA_COUNT)"
    else
        check_warn "No LoRA models found (optional)"
    fi
else
    check_fail "Models directory not found"
fi

# =============================================================================
# 6. Environment Configuration
# =============================================================================

print_header "[6/7] Environment Configuration"

if [[ -f ".env" ]]; then
    check_pass ".env file exists"

    # Check critical variables
    if grep -q "WORKSPACE_PATH=" .env; then
        check_pass "WORKSPACE_PATH configured"
    else
        check_warn "WORKSPACE_PATH not set"
    fi

    # Check optional S3/R2
    if grep -q "R2_ENDPOINT=" .env && grep -q "R2_ACCESS_KEY=" .env; then
        check_pass "R2/S3 configured"
    else
        check_warn "R2/S3 not configured (outputs stay local)"
    fi
else
    check_warn ".env file not found (using defaults)"
    echo "         Copy from: .env.example"
fi

# =============================================================================
# 7. Build System
# =============================================================================

print_header "[7/7] Build System"

# Check GitHub Actions workflow
if [[ -f "../.github/workflows/build-docker-serverless.yml" ]]; then
    check_pass "GitHub Actions workflow exists"
else
    check_warn "GitHub Actions workflow missing"
fi

# Check Docker command availability
if command -v docker &>/dev/null; then
    check_pass "Docker command available"

    if [[ "$VERBOSE" == true ]]; then
        DOCKER_VERSION=$(docker --version)
        echo "         $DOCKER_VERSION"
    fi

    # Check Docker Buildx
    if docker buildx version &>/dev/null; then
        check_pass "Docker Buildx available"
    else
        check_warn "Docker Buildx not available (needed for Mac builds)"
    fi
else
    check_fail "Docker command not found"
fi

# Check GitHub CLI (for automated builds)
if command -v gh &>/dev/null; then
    check_pass "GitHub CLI available"
else
    check_warn "GitHub CLI not available (manual builds only)"
fi

# =============================================================================
# Summary
# =============================================================================

print_header "Verification Summary"

echo "Passed:   $PASSED"
echo "Failed:   $FAILED"
echo "Warnings: $WARNINGS"
echo ""

if [[ $FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Local testing: docker compose -f docker-compose.test.yml up"
    echo "  2. Build image: ./build.sh latest --github"
    echo "  3. Deploy to RunPod: python deploy.py create"
    echo ""
    exit 0
else
    echo -e "${RED}✗ $FAILED critical checks failed${NC}"
    echo ""
    echo "Please fix the issues above before proceeding."
    echo ""
    exit 1
fi
