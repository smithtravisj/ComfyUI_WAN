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
COMFYUI_DIR="${WORKSPACE}/ComfyUI_WAN"
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
# Phase 2: Python Virtual Environment (handled by WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh)
# =============================================================================

print_header "Phase 2: Python Virtual Environment"

log_info "Python venv will be created by WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh"
log_info "Venv location: $COMFYUI_DIR/venv"
log_info "This phase will be handled in Phase 3 during model download"

# =============================================================================
# Phase 3: Model Downloads
# =============================================================================

print_header "Phase 3: Downloading Models (~65GB, 15-20 minutes)"

# Check if WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh exists
INSTALL_SCRIPT="$COMFYUI_DIR/WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh"

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    log_error "Installation script not found: $INSTALL_SCRIPT"
    log_error "Expected location: $COMFYUI_DIR/WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh"
    log_error "Current directory: $(pwd)"
    log_error "ComfyUI_WAN directory exists: $(test -d "$COMFYUI_DIR" && echo "YES" || echo "NO")"
    if [[ -d "$COMFYUI_DIR" ]]; then
        log_info "Contents of $COMFYUI_DIR:"
        ls -la "$COMFYUI_DIR" | head -20
    fi
    exit 1
fi

# Change to ComfyUI directory for installation
cd "$COMFYUI_DIR"

log_info "Running model download script from $COMFYUI_DIR..."
log_info "This will download:"
log_info "  - 4× UNET models (Q8_0): ~50GB total"
log_info "  - Text encoder: ~4GB"
log_info "  - VAE: ~242MB"
log_info "  - Lightning LoRAs: ~8GB"
echo ""

# Run the install script with environment variables
# Note: WAN script creates venv in COMFYUI_DIR by default (./venv)
# We let it create there, then move to network volume after
export VENV_DIR="venv"
export PYTHON_BIN="python3.11"

# Tell the install script to use network volume for models
# The script already looks for models/ directory, which we created in Phase 1

if bash "$INSTALL_SCRIPT"; then
    log_success "Model downloads and venv setup completed"
else
    log_error "Model download failed"
    log_error "Check logs above for details"
    exit 1
fi

# Move venv to network volume for persistence across containers
if [[ -d "$COMFYUI_DIR/venv" ]]; then
    log_info "Moving venv to network volume for persistence..."

    # Remove old venv on network volume if exists
    rm -rf "$VENV_PATH"

    # Copy venv to network volume (use cp not mv to preserve original)
    cp -a "$COMFYUI_DIR/venv" "$VENV_PATH"

    log_success "Venv copied to $VENV_PATH"
    log_info "Original venv remains at $COMFYUI_DIR/venv for Docker container use"
else
    log_warning "Venv not found at $COMFYUI_DIR/venv"
fi

# Install serverless handler dependencies into network volume venv
if [[ -f "$VENV_PATH/bin/activate" ]]; then
    log_info "Installing serverless dependencies..."
    source "$VENV_PATH/bin/activate"
    pip install --upgrade pip setuptools wheel
    pip install runpod==1.7.3 boto3==1.34.34 aiofiles==23.2.1
    log_success "Serverless dependencies installed"
fi

# Return to workspace root
cd "$WORKSPACE"

# =============================================================================
# Phase 4: Custom Nodes Installation (handled by WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh)
# =============================================================================

print_header "Phase 4: Custom Nodes Installation"

log_success "Custom nodes installed by WAN2_2-ULTRA-AUTO_INSTALL-RUNPOD.sh"
log_info "The installation script already cloned and configured all required custom nodes"

# Count installed nodes for reporting
if [[ -d "$COMFYUI_DIR/custom_nodes" ]]; then
    NODE_COUNT=$(find "$COMFYUI_DIR/custom_nodes" -maxdepth 1 -type d | wc -l)
    NODE_COUNT=$((NODE_COUNT - 1))  # Subtract 1 for the custom_nodes directory itself
    log_info "Total custom nodes installed: $NODE_COUNT"
else
    log_warning "custom_nodes directory not found"
    NODE_COUNT=0
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

# Check venv (check both locations)
if [[ -f "$VENV_PATH/bin/python" ]]; then
    PYTHON_VERSION=$("$VENV_PATH/bin/python" --version)
    log_success "Python venv (network volume): $PYTHON_VERSION"
elif [[ -f "$COMFYUI_DIR/venv/bin/python" ]]; then
    PYTHON_VERSION=$("$COMFYUI_DIR/venv/bin/python" --version)
    log_success "Python venv (ComfyUI dir): $PYTHON_VERSION"
else
    log_error "Python venv not found in either location"
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
