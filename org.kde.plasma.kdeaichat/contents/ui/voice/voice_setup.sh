#!/bin/bash
# voice_setup.sh - One-time setup for KDE AI Chat voice features
# Creates a Python venv with STT/TTS dependencies

set -e

VENV_DIR="${1:-$HOME/.local/share/kdeaichat/venv}"
# Expand tilde if present
VENV_DIR="${VENV_DIR/#\~/$HOME}"
MODE="${2:-cpu}" # cpu or gpu

echo "================================================================="
echo "  KDE AI Chat - Virtual Environment setup for TTS and STT"
echo "================================================================="

# Check if venv is already fully set up
if [ -d "$VENV_DIR" ]; then
    VENV_PY="$VENV_DIR/bin/python3"
    if [ ! -f "$VENV_PY" ]; then
        VENV_PY="$VENV_DIR/bin/python"
    fi
    if [ -f "$VENV_PY" ] && "$VENV_PY" -c "import faster_whisper, kokoro, sounddevice, numpy, soundfile, huggingface_hub" 2>/dev/null; then
        echo "  ✓ Virtual environment already exists at: $VENV_DIR"
        echo "  ✓ All required Python packages are already installed."
        echo "================================================================="
        echo ""
        read -n 1 -s -r -p "Press any key to exit..."
        echo ""
        exit 0
    fi
fi

echo "  Setting up virtual environment at: $VENV_DIR ($MODE mode)"
echo "  This might take a few minutes..."
echo "-----------------------------------------------------------------"

echo '{"type":"setup_status","status":"creating_venv","path":"'"$VENV_DIR"'","mode":"'"$MODE"'"}'

python3 -m venv "$VENV_DIR"

echo '{"type":"setup_status","status":"installing_packages"}'

"$VENV_DIR/bin/pip" install --quiet --upgrade pip

if [ "$MODE" = "gpu" ]; then
    echo "  Installing GPU (CUDA) enabled PyTorch and runtime libraries..."
    # Install standard torch (comes with CUDA by default on Linux) and nvidia runtime packages
    "$VENV_DIR/bin/pip" install --quiet torch nvidia-cublas-cu12 nvidia-cudnn-cu12
else
    echo "  Installing CPU-only PyTorch (efficient space-saving wheel)..."
    # Install cpu-only PyTorch to avoid massive ~2GB CUDA download
    "$VENV_DIR/bin/pip" install --quiet torch --index-url https://download.pytorch.org/whl/cpu
fi

echo "  Installing remaining packages (faster-whisper, kokoro, sounddevice, etc.)..."
"$VENV_DIR/bin/pip" install --quiet \
    faster-whisper \
    kokoro \
    sounddevice \
    numpy \
    soundfile \
    huggingface_hub

echo '{"type":"setup_status","status":"done"}'
echo "-----------------------------------------------------------------"
echo "  ✓ Voice setup ($MODE) completed successfully!"
echo "================================================================="
echo ""
read -n 1 -s -r -p "Press any key to exit..."
echo ""
