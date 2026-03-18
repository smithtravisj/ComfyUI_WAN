#!/usr/bin/env bash
#
# Minimal Workspace Setup (Uses ALL Existing Resources)
# Links to existing models AND uses system Python with existing dependencies
#
# Usage:
#   bash init_workspace_simple.sh

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

print_header "Minimal Workspace Setup (Using ALL Existing Resources)"

echo -e "${BLUE}Workspace: $WORKSPACE${NC}"
echo -e "${BLUE}ComfyUI dir: $COMFYUI_DIR${NC}"
echo -e "${BLUE}Existing models: $EXISTING_MODELS${NC}"
echo ""

# Create workspace structure
print_header "Creating Workspace Structure"

mkdir -p "${WORKSPACE}/output"
mkdir -p "${WORKSPACE}/temp"

echo -e "${GREEN}✓${NC} Output and temp directories created"

# Symlink models
print_header "Linking Existing Models"

if [[ -d "${EXISTING_MODELS}" ]]; then
    rm -rf "${WORKSPACE}/models"
    ln -s "${EXISTING_MODELS}" "${WORKSPACE}/models"
    echo -e "${GREEN}✓${NC} Models linked (65GB, no download needed)"
else
    echo -e "${YELLOW}⚠${NC} Models directory not found: ${EXISTING_MODELS}"
    exit 1
fi

# Verify critical models
echo ""
echo "Verifying critical models:"
CRITICAL_FILES=(
    "vae/wan_2.1_vae.safetensors"
    "text_encoders/umt5-xxl-encoder-Q5_K_S.gguf"
    "unet/Wan2.2-T2V-A14B-HighNoise-Q8_0.gguf"
    "unet/Wan2.2-I2V-A14B-HighNoise-Q8_0.gguf"
)

ALL_FOUND=true
for file in "${CRITICAL_FILES[@]}"; do
    if [[ -f "${WORKSPACE}/models/$file" ]]; then
        SIZE=$(du -h "${WORKSPACE}/models/$file" | cut -f1)
        echo -e "  ${GREEN}✓${NC} $(basename "$file") (${SIZE})"
    else
        echo -e "  ${YELLOW}⚠${NC} Missing: $file"
        ALL_FOUND=false
    fi
done

# Create venv marker pointing to system Python
print_header "Python Environment Setup"

# Check Python version
if command -v python3 &>/dev/null; then
    PYTHON_VERSION=$(python3 --version)
    PYTHON_PATH=$(which python3)
    echo -e "${GREEN}✓${NC} Using system Python: $PYTHON_VERSION"
    echo -e "${BLUE}  Path: $PYTHON_PATH${NC}"

    # Create a minimal venv structure that just points to system Python
    mkdir -p "${WORKSPACE}/venv/bin"
    ln -sf "$PYTHON_PATH" "${WORKSPACE}/venv/bin/python"
    ln -sf "$PYTHON_PATH" "${WORKSPACE}/venv/bin/python3"

    echo -e "${GREEN}✓${NC} Workspace venv linked to system Python"
else
    echo -e "${YELLOW}⚠${NC} Python not found"
    exit 1
fi

# Check if required packages are available
echo ""
echo "Checking Python dependencies:"
REQUIRED_PACKAGES=("torch" "comfy" "folder_paths")
for package in "${REQUIRED_PACKAGES[@]}"; do
    if python3 -c "import ${package}" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $package"
    else
        echo -e "  ${YELLOW}⚠${NC} $package (may need installation)"
    fi
done

# Create initialization marker
print_header "Finalizing"

cat > "${WORKSPACE}/.initialized" <<EOF
# ComfyUI WAN 2.2 Workspace (Minimal Setup)
# Initialized: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Models: Symlinked from ${EXISTING_MODELS}
# Python: System Python (${PYTHON_VERSION})

INITIALIZED=true
VERSION=1.0-minimal
MODELS_SYMLINKED=true
MODELS_SOURCE=${EXISTING_MODELS}
PYTHON_SYSTEM=true
EOF

WORKSPACE_SIZE=$(du -sh "$WORKSPACE" 2>/dev/null | cut -f1 || echo "N/A")

print_header "Setup Complete!"

echo -e "${GREEN}✓${NC} Workspace ready: ${WORKSPACE}"
echo -e "${GREEN}✓${NC} Models: 65GB (symlinked, no download)"
echo -e "${GREEN}✓${NC} Python: System Python (${PYTHON_VERSION})"
echo -e "${GREEN}✓${NC} Workspace size: ${WORKSPACE_SIZE}"
echo ""

if [[ "$ALL_FOUND" == true ]]; then
    echo -e "${GREEN}All critical models found!${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Verify: ./verify.sh workspace"
    echo "  2. For Docker testing, ensure Docker can access system Python packages"
    echo "  3. Or continue to Phase 4: Build Docker image"
else
    echo -e "${YELLOW}Some models missing - but workspace is ready${NC}"
fi
echo ""
