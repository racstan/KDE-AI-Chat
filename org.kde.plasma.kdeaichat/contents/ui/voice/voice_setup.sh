#!/bin/bash
# voice_setup.sh - One-time setup for KDE AI Chat voice features
# Creates a Python venv with STT/TTS dependencies

set -e

VENV_DIR="${1:-$HOME/.local/share/kdeaichat/venv}"
# Expand tilde if present
VENV_DIR="${VENV_DIR/#\~/$HOME}"

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
        read -p "Press Enter to close..."
        exit 0
    fi
fi

echo "  Setting up virtual environment at: $VENV_DIR"
echo "  This might take a few minutes..."
echo "-----------------------------------------------------------------"

echo '{"type":"setup_status","status":"creating_venv","path":"'"$VENV_DIR"'"}'

python3 -m venv "$VENV_DIR"

echo '{"type":"setup_status","status":"installing_packages"}'

"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet \
    faster-whisper \
    kokoro \
    sounddevice \
    numpy \
    soundfile \
    huggingface_hub

echo '{"type":"setup_status","status":"done"}'
echo "-----------------------------------------------------------------"
echo "  ✓ Voice setup completed successfully!"
echo "================================================================="
echo ""
read -p "Press Enter to close..."
