#!/usr/bin/env bash
#
# Simplified Workspace Initialization (Uses Existing Models)
# Since models are already in /Users/travissmith/Projects/ComfyUI_WAN/models/
#
# This script creates symlinks to existing models instead of downloading
#
# Usage:
#   bash init_workspace_existing_models.sh

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
VENV_PATH="${WORKSPACE}/venv"

print_header "Simplified Workspace Initialization (Using Existing Models)"

echo -e "${BLUE}Workspace: $WORKSPACE${NC}"
echo -e "${BLUE}Existing models: $EXISTING_MODELS${NC}"
echo ""

# Create workspace structure
print_header "Creating Workspace Structure"

mkdir -p "${WORKSPACE}/models"
mkdir -p "${WORKSPACE}/output"
mkdir -p "${WORKSPACE}/temp"

echo -e "${GREEN}✓${NC} Workspace directories created"

# Symlink models (instead of downloading)
print_header "Linking Existing Models"

if [[ -d "${EXISTING_MODELS}" ]]; then
    # Remove workspace/models if it exists and recreate as symlink
    rm -rf "${WORKSPACE}/models"
    ln -s "${EXISTING_MODELS}" "${WORKSPACE}/models"

    echo -e "${GREEN}✓${NC} Models linked from: ${EXISTING_MODELS}"

    # Verify critical models
    CRITICAL_FILES=(
        "vae/wan_2.1_vae.safetensors"
        "text_encoders/umt5-xxl-encoder-Q5_K_S.gguf"
        "unet/Wan2.2-T2V-A14B-HighNoise-Q8_0.gguf"
    )

    echo ""
    echo "Verifying critical models:"
    for file in "${CRITICAL_FILES[@]}"; do
        if [[ -f "${WORKSPACE}/models/$file" ]]; then
            SIZE=$(du -h "${WORKSPACE}/models/$file" | cut -f1)
            echo -e "  ${GREEN}✓${NC} $(basename "$file") (${SIZE})"
        else
            echo -e "  ${YELLOW}⚠${NC} Missing: $file"
        fi
    done
else
    echo -e "${YELLOW}⚠${NC} Models directory not found: ${EXISTING_MODELS}"
    echo "Please ensure models are at the correct location"
    exit 1
fi

# Create Python venv
print_header "Creating Python Virtual Environment"

# Auto-detect Python (prefer python3.11, fallback to python3)
if command -v python3.11 &>/dev/null; then
    PYTHON="python3.11"
elif command -v python3 &>/dev/null; then
    PYTHON="python3"
else
    echo "ERROR: Python 3 not found"
    exit 1
fi

PYTHON_VERSION=$($PYTHON --version)
echo -e "${BLUE}Using: $PYTHON_VERSION${NC}"

if [[ ! -d "$VENV_PATH" ]]; then
    $PYTHON -m venv "$VENV_PATH"
    echo -e "${GREEN}✓${NC} Virtual environment created"
else
    echo -e "${BLUE}ℹ${NC} Virtual environment already exists"
fi

# Activate and install dependencies
source "$VENV_PATH/bin/activate"

echo "Upgrading pip..."
pip install --upgrade pip setuptools wheel --quiet

echo "Installing PyTorch..."
pip install torch==2.4.0 torchvision==0.19.0 torchaudio==2.4.0 --index-url https://download.pytorch.org/whl/cu121 --quiet

echo "Installing ComfyUI dependencies..."
if [[ -f "$COMFYUI_DIR/requirements.txt" ]]; then
    pip install -r "$COMFYUI_DIR/requirements.txt" --quiet
fi

echo "Installing serverless dependencies..."
pip install runpod==1.7.3 boto3==1.34.34 aiofiles==23.2.1 --quiet

echo -e "${GREEN}✓${NC} Python dependencies installed"

# Create initialization marker
print_header "Finalizing"

cat > "${WORKSPACE}/.initialized" <<EOF
# ComfyUI WAN 2.2 Workspace (Existing Models)
# Initialized: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Models: Symlinked from ${EXISTING_MODELS}
# Venv: ${VENV_PATH}

INITIALIZED=true
VERSION=1.0-existing-models
MODELS_SYMLINKED=true
MODELS_SOURCE=${EXISTING_MODELS}
EOF

WORKSPACE_SIZE=$(du -sh "$WORKSPACE" | cut -f1)

print_header "Initialization Complete!"

echo -e "${GREEN}✓${NC} Workspace ready at: ${WORKSPACE}"
echo -e "${GREEN}✓${NC} Models linked (no download needed): 65GB"
echo -e "${GREEN}✓${NC} Workspace size: ${WORKSPACE_SIZE}"
echo ""
echo "Next steps:"
echo "  1. Run verification: ./verify.sh workspace"
echo "  2. Test locally: docker compose -f docker-compose.test.yml up"
echo "  3. Continue to Phase 4: Build Docker image"
echo ""
