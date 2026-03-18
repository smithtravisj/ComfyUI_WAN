#!/usr/bin/env bash
#
# Workspace Setup for Docker Testing (No Local venv Needed)
#
# This creates a minimal workspace structure that Docker will use.
# All Python dependencies will be inside the Docker container.
#
# Usage:
#   bash init_workspace_docker_only.sh

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
    echo ""
    echo "========================================================================"
    echo "$*"
    echo "========================================================================"
    echo ""
}

# Configuration
WORKSPACE="./workspace"
COMFYUI_DIR="/Users/travissmith/Projects/ComfyUI_WAN"
EXISTING_MODELS="${COMFYUI_DIR}/models"

print_header "Workspace Setup for Docker Testing"

echo -e "${BLUE}Purpose: Create workspace for Docker container${NC}"
echo -e "${BLUE}Note: No local Python venv needed (runs in Docker)${NC}"
echo ""
echo -e "${BLUE}Workspace: $WORKSPACE${NC}"
echo -e "${BLUE}Models: $EXISTING_MODELS${NC}"
echo ""

# Create workspace structure
print_header "Creating Workspace Structure"

mkdir -p "${WORKSPACE}/output"
mkdir -p "${WORKSPACE}/temp"

echo -e "${GREEN}✓${NC} Output and temp directories created"

# Symlink models (Docker will access these)
print_header "Linking Models for Docker Access"

if [[ -d "${EXISTING_MODELS}" ]]; then
    rm -rf "${WORKSPACE}/models"
    ln -s "${EXISTING_MODELS}" "${WORKSPACE}/models"
    echo -e "${GREEN}✓${NC} Models linked: ${EXISTING_MODELS}"
    echo -e "${BLUE}  Docker will mount this at /workspace/models${NC}"
else
    echo -e "${YELLOW}⚠${NC} Models not found: ${EXISTING_MODELS}"
    exit 1
fi

# Verify critical models
echo ""
echo "Verifying critical models for Docker:"

CRITICAL_FILES=(
    "vae/wan_2.1_vae.safetensors:VAE"
    "text_encoders/umt5-xxl-encoder-Q5_K_S.gguf:Text Encoder"
    "unet/Wan2.2-T2V-A14B-HighNoise-Q8_0.gguf:T2V UNET (High)"
    "unet/Wan2.2-T2V-A14B-LowNoise-Q8_0.gguf:T2V UNET (Low)"
    "unet/Wan2.2-I2V-A14B-HighNoise-Q8_0.gguf:I2V UNET (High)"
    "unet/Wan2.2-I2V-A14B-LowNoise-Q8_0.gguf:I2V UNET (Low)"
)

ALL_FOUND=true
for entry in "${CRITICAL_FILES[@]}"; do
    IFS=':' read -r file desc <<< "$entry"
    if [[ -f "${WORKSPACE}/models/$file" ]]; then
        SIZE=$(du -h "${WORKSPACE}/models/$file" | cut -f1)
        echo -e "  ${GREEN}✓${NC} $desc: ${SIZE}"
    else
        echo -e "  ${YELLOW}⚠${NC} Missing: $desc"
        ALL_FOUND=false
    fi
done

# Count LoRAs
LORA_COUNT=$(find "${WORKSPACE}/models/loras" -name "*.safetensors" 2>/dev/null | wc -l)
echo -e "  ${GREEN}✓${NC} Lightning LoRAs: $LORA_COUNT files"

# Create a stub venv directory (Docker will create real one on RunPod)
print_header "Creating Venv Placeholder"

mkdir -p "${WORKSPACE}/venv"
cat > "${WORKSPACE}/venv/README.txt" <<EOF
This is a placeholder directory.

For LOCAL TESTING:
- Python dependencies are inside the Docker container
- No local venv installation needed

For RUNPOD DEPLOYMENT:
- The real venv will be created here on the RunPod network volume
- Run init_network_volume.sh inside a RunPod pod to set it up
EOF

echo -e "${GREEN}✓${NC} Venv placeholder created"
echo -e "${BLUE}  (Real venv will be on RunPod network volume)${NC}"

# Create initialization marker
print_header "Finalizing"

cat > "${WORKSPACE}/.initialized" <<EOF
# ComfyUI WAN 2.2 Workspace - Docker Testing Setup
# Initialized: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Models: Symlinked from ${EXISTING_MODELS} (65GB)
# Venv: Placeholder (runs in Docker for local testing)

INITIALIZED=true
VERSION=1.0-docker-only
MODELS_SYMLINKED=true
MODELS_SOURCE=${EXISTING_MODELS}
DOCKER_TESTING=true
VENV_PLACEHOLDER=true

# For RunPod deployment, this workspace structure will be recreated
# on the network volume with a real venv.
EOF

MODELS_SIZE=$(du -sh "${EXISTING_MODELS}" 2>/dev/null | cut -f1 || echo "65GB")

print_header "Setup Complete!"

echo -e "${GREEN}✓${NC} Workspace ready for Docker testing"
echo -e "${GREEN}✓${NC} Models: ${MODELS_SIZE} (symlinked, no download)"
echo -e "${GREEN}✓${NC} Structure: output/, temp/, models/ → venv/ (placeholder)"
echo ""

if [[ "$ALL_FOUND" == true ]]; then
    echo -e "${GREEN}All critical models found!${NC}"
    echo ""
    echo "✅ Ready for Docker testing"
    echo ""
    echo "Next steps:"
    echo "  1. Verify setup:"
    echo "     ./verify.sh workspace"
    echo ""
    echo "  2. Test with Docker:"
    echo "     docker compose -f docker-compose.test.yml build"
    echo "     docker compose -f docker-compose.test.yml up -d"
    echo ""
    echo "  3. Run test workflow:"
    echo "     python test_handler.py --local --workflow examples/minimal_validation.json"
    echo ""
    echo "📝 Note: For actual RunPod deployment, you'll need to run"
    echo "   init_network_volume.sh inside a RunPod pod to create the real venv."
else
    echo -e "${YELLOW}⚠ Some models missing${NC}"
    echo "Check the list above and ensure all required models are present."
fi
echo ""
