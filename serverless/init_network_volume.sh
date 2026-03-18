#!/usr/bin/env bash
#
# Network Volume Initialization Script for ComfyUI WAN 2.2 Serverless
# Run this ONCE in a RunPod GPU Pod with network volume attached
#
# Purpose:
#   - Initialize /workspace directory structure
#   - Download all models (~65GB) to network volume
#   - Install Python venv and dependencies
#   - Install all custom nodes
#   - Create .initialized marker for validation
#
# Usage:
#   1. Start a RunPod GPU Pod with network volume attached to /workspace
#   2. Clone ComfyUI WAN 2.2 repo
#   3. Run: bash serverless/init_network_volume.sh
#   4. Wait 30-40 minutes for completion
#   5. Stop the pod (network volume persists)
#
# Execution Time: 30-40 minutes
# Network Volume Size Required: 100GB minimum
# Run Frequency: ONCE (reuse network volume across deployments)

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
WORKSPACE="/workspace"
COMFYUI_DIR="/comfyui"
VENV_PATH="${WORKSPACE}/venv"
MODELS_DIR="${WORKSPACE}/models"
OUTPUT_DIR="${WORKSPACE}/output"
TEMP_DIR="${WORKSPACE}/temp"
MARKER_FILE="${WORKSPACE}/.initialized"

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
    echo "========================================================================"
    echo "$*"
    echo "========================================================================"
    echo ""
}

# Check if already initialized
if [[ -f "$MARKER_FILE" ]]; then
    print_header "Network Volume Already Initialized"
    log_warning "Found existing initialization marker: $MARKER_FILE"
    echo ""
    read -p "Reinitialize network volume? This will DELETE existing data (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Keeping existing initialization. Exiting."
        exit 0
    fi
    log_warning "Proceeding with reinitialization..."
    rm -f "$MARKER_FILE"
fi

# Verify network volume is mounted
if [[ ! -d "$WORKSPACE" ]]; then
    log_error "Network volume not mounted at $WORKSPACE"
    log_error "Please ensure network volume is attached to /workspace"
    exit 1
fi

# Check available space
AVAILABLE_GB=$(df -BG "$WORKSPACE" | awk 'NR==2 {print $4}' | sed 's/G//')
if [[ $AVAILABLE_GB -lt 80 ]]; then
    log_error "Insufficient space on network volume"
    log_error "Available: ${AVAILABLE_GB}GB, Required: 80GB minimum"
    exit 1
fi

print_header "ComfyUI WAN 2.2 Network Volume Initialization"
log_info "Network volume: $WORKSPACE"
log_info "Available space: ${AVAILABLE_GB}GB"
log_info "Estimated time: 30-40 minutes"
echo ""

START_TIME=$(date +%s)

# =============================================================================
# Phase 1: Directory Structure
# =============================================================================

print_header "Phase 1: Creating Directory Structure"

DIRS=(
    "$MODELS_DIR"
    "$MODELS_DIR/unet"
    "$MODELS_DIR/text_encoders"
    "$MODELS_DIR/vae"
    "$MODELS_DIR/loras"
    "$OUTPUT_DIR"
    "$TEMP_DIR"
    "$VENV_PATH"
)

for dir in "${DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_success "Created: $dir"
    else
        log_info "Exists: $dir"
    fi
done

# =============================================================================
# Phase 2: Python Virtual Environment
# =============================================================================

print_header "Phase 2: Installing Python Virtual Environment"

if [[ ! -f "$VENV_PATH/bin/activate" ]]; then
    log_info "Creating virtual environment at $VENV_PATH"
    python3.11 -m venv "$VENV_PATH"
    log_success "Virtual environment created"
else
    log_info "Virtual environment already exists"
fi

# Activate venv
source "$VENV_PATH/bin/activate"
log_success "Virtual environment activated"

# Upgrade pip
log_info "Upgrading pip..."
pip install --upgrade pip setuptools wheel
log_success "pip upgraded"

# Install ComfyUI dependencies
log_info "Installing ComfyUI dependencies..."

if [[ -f "$COMFYUI_DIR/requirements.txt" ]]; then
    pip install -r "$COMFYUI_DIR/requirements.txt"
    log_success "ComfyUI requirements installed"
else
    log_warning "No requirements.txt found, installing core dependencies"
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121
    pip install opencv-python pillow numpy scipy einops transformers safetensors
    log_success "Core dependencies installed"
fi

# Install serverless handler dependencies
log_info "Installing serverless dependencies..."
pip install runpod==1.7.3 boto3==1.34.34 aiofiles==23.2.1
log_success "Serverless dependencies installed"

# =============================================================================
# Phase 3: Model Downloads
# =============================================================================

print_header "Phase 3: Downloading Models (~65GB, 15-20 minutes)"

# Check if WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh exists
INSTALL_SCRIPT="$COMFYUI_DIR/WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh"

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    log_error "Installation script not found: $INSTALL_SCRIPT"
    log_error "Please ensure you're running from ComfyUI WAN 2.2 directory"
    exit 1
fi

# Modify paths in install script to use network volume
log_info "Adapting installation script for network volume..."

# Create temporary modified script
TEMP_INSTALL_SCRIPT="/tmp/install_network_volume.sh"
cp "$INSTALL_SCRIPT" "$TEMP_INSTALL_SCRIPT"

# Replace paths to use network volume
sed -i "s|/comfyui/models|$MODELS_DIR|g" "$TEMP_INSTALL_SCRIPT"
sed -i "s|cd /comfyui|cd $COMFYUI_DIR|g" "$TEMP_INSTALL_SCRIPT"

# Make executable
chmod +x "$TEMP_INSTALL_SCRIPT"

log_info "Running model download script..."
log_info "This will download:"
log_info "  - 4× UNET models (Q8_0): ~50GB total"
log_info "  - Text encoder: ~4GB"
log_info "  - VAE: ~242MB"
log_info "  - Lightning LoRAs: ~8GB"
echo ""

# Run the modified install script
if bash "$TEMP_INSTALL_SCRIPT"; then
    log_success "Model downloads completed"
else
    log_error "Model download failed"
    log_error "Check logs above for details"
    exit 1
fi

# Clean up temporary script
rm -f "$TEMP_INSTALL_SCRIPT"

# =============================================================================
# Phase 4: Custom Nodes Installation
# =============================================================================

print_header "Phase 4: Installing Custom Nodes"

cd "$COMFYUI_DIR/custom_nodes"

# List of required custom nodes (from WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh)
CUSTOM_NODES=(
    "https://github.com/ltdrdata/ComfyUI-Manager"
    "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
    "https://github.com/Kosinkadink/ComfyUI-Advanced-ControlNet"
    "https://github.com/Fannovel16/comfyui_controlnet_aux"
    "https://github.com/jags111/efficiency-nodes-comfyui"
    "https://github.com/crystian/ComfyUI-Crystools"
    "https://github.com/cubiq/ComfyUI_essentials"
    "https://github.com/cubiq/ComfyUI_IPAdapter_plus"
    "https://github.com/kijai/ComfyUI-Florence2"
    "https://github.com/chflame163/ComfyUI_LayerStyle"
    "https://github.com/Acly/comfyui-inpaint-nodes"
    "https://github.com/cubiq/ComfyUI_InstantID"
    "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
    "https://github.com/rgthree/rgthree-comfy"
    "https://github.com/LarryJane491/Image-Captioning-in-ComfyUI"
    "https://github.com/kijai/ComfyUI-KJNodes"
    "https://github.com/Gourieff/comfyui-reactor-node"
    "https://github.com/alessandrozonta/ComfyUI-ClapAPI"
)

NODE_COUNT=0
FAILED_NODES=()

for repo_url in "${CUSTOM_NODES[@]}"; do
    NODE_NAME=$(basename "$repo_url")
    NODE_COUNT=$((NODE_COUNT + 1))

    log_info "[$NODE_COUNT/${#CUSTOM_NODES[@]}] Installing: $NODE_NAME"

    if [[ -d "$NODE_NAME" ]]; then
        log_info "Already exists, pulling updates..."
        cd "$NODE_NAME"
        if git pull; then
            log_success "Updated: $NODE_NAME"
        else
            log_warning "Update failed: $NODE_NAME"
        fi
        cd ..
    else
        if git clone "$repo_url"; then
            log_success "Installed: $NODE_NAME"
        else
            log_error "Failed: $NODE_NAME"
            FAILED_NODES+=("$NODE_NAME")
        fi
    fi

    # Install node dependencies if requirements.txt exists
    if [[ -f "$NODE_NAME/requirements.txt" ]]; then
        log_info "Installing dependencies for $NODE_NAME..."
        pip install -r "$NODE_NAME/requirements.txt" || log_warning "Some dependencies failed for $NODE_NAME"
    fi
done

echo ""
log_success "Custom node installation complete"

if [[ ${#FAILED_NODES[@]} -gt 0 ]]; then
    log_warning "Failed nodes (may not be critical):"
    for node in "${FAILED_NODES[@]}"; do
        echo "  - $node"
    done
fi

# =============================================================================
# Phase 5: Verification
# =============================================================================

print_header "Phase 5: Verifying Installation"

# Check critical models exist
log_info "Checking model files..."

CRITICAL_FILES=(
    "$MODELS_DIR/vae/wan_2.1_vae.safetensors"
    "$MODELS_DIR/text_encoders/umt5-xxl-encoder-Q5_K_S.gguf"
)

MISSING_FILES=()
for file in "${CRITICAL_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        SIZE=$(du -h "$file" | cut -f1)
        log_success "Found: $(basename "$file") ($SIZE)"
    else
        log_error "Missing: $file"
        MISSING_FILES+=("$file")
    fi
done

# Check UNET models (at least one should exist)
UNET_COUNT=$(find "$MODELS_DIR/unet" -name "*.gguf" | wc -l)
if [[ $UNET_COUNT -gt 0 ]]; then
    log_success "Found $UNET_COUNT UNET model(s)"
else
    log_error "No UNET models found in $MODELS_DIR/unet"
    MISSING_FILES+=("UNET models")
fi

# Check LoRAs
LORA_COUNT=$(find "$MODELS_DIR/loras" -name "*.safetensors" | wc -l)
if [[ $LORA_COUNT -gt 0 ]]; then
    log_success "Found $LORA_COUNT LoRA file(s)"
else
    log_warning "No LoRA files found (optional)"
fi

# Check venv
if [[ -f "$VENV_PATH/bin/python" ]]; then
    PYTHON_VERSION=$("$VENV_PATH/bin/python" --version)
    log_success "Python venv: $PYTHON_VERSION"
else
    log_error "Python venv not properly installed"
    exit 1
fi

# Check disk usage
USED_GB=$(du -sh "$WORKSPACE" | cut -f1)
log_info "Total network volume usage: $USED_GB"

# =============================================================================
# Phase 6: Create Marker File
# =============================================================================

print_header "Phase 6: Finalizing Installation"

if [[ ${#MISSING_FILES[@]} -eq 0 ]]; then
    # Create initialization marker
    cat > "$MARKER_FILE" <<EOF
# ComfyUI WAN 2.2 Network Volume Initialization
# Initialized: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Models: $MODELS_DIR
# Venv: $VENV_PATH
# Output: $OUTPUT_DIR
# Space used: $USED_GB

INITIALIZED=true
VERSION=1.0
PYTHON_VERSION=$PYTHON_VERSION
UNET_MODELS=$UNET_COUNT
LORA_MODELS=$LORA_COUNT
CUSTOM_NODES=$NODE_COUNT
EOF

    log_success "Created initialization marker: $MARKER_FILE"

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    MINUTES=$((DURATION / 60))
    SECONDS=$((DURATION % 60))

    print_header "Initialization Complete!"
    echo ""
    echo "✓ Network volume ready for serverless deployment"
    echo "✓ Total time: ${MINUTES}m ${SECONDS}s"
    echo "✓ Space used: $USED_GB"
    echo ""
    log_info "Next steps:"
    echo "  1. Stop this RunPod pod (network volume persists)"
    echo "  2. Build Docker image: cd serverless && ./build.sh latest --github"
    echo "  3. Create serverless endpoint with network volume attached"
    echo "  4. Test with example workflow"
    echo ""

else
    log_error "Initialization incomplete - missing critical files:"
    for file in "${MISSING_FILES[@]}"; do
        echo "  - $file"
    done
    log_error "Please investigate errors above and re-run script"
    exit 1
fi
