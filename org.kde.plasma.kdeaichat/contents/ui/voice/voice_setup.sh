#!/bin/bash
# voice_setup.sh - One-time setup for KDE AI Chat voice features
# Creates a Python venv with STT/TTS dependencies

set -e

VENV_DIR="${1:-$HOME/.local/share/kdeaichat/venv}"

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
