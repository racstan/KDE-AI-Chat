#!/bin/bash
# venv_setup.sh - One-time setup for KDE AI Chat voice features
# Creates a Python venv with STT/TTS dependencies

set -e

VENV_DIR="${1:-$HOME/.local/share/kdeaichat/venv}"
# Expand tilde if present
VENV_DIR="${VENV_DIR/#\~/$HOME}"
MODE="${2:-cpu}" # cpu or gpu

wait_for_keypress() {
    if [ "$NON_INTERACTIVE" = "1" ] || [ "$NONINTERACTIVE" = "1" ]; then
        return 0
    fi
    if [ -t 0 ]; then
        read -n 1 -s -r -p "Press any key to exit..."
    elif [ -c /dev/tty ]; then
        read -n 1 -s -r -p "Press any key to exit..." </dev/tty
    else
        echo "Press any key to exit (waiting 3 seconds)..."
        sleep 3
    fi
}

if [ "$MODE" = "download_stt" ]; then
    MODEL_NAME="${3:-large-v3-turbo}"
    REPO="Systran/faster-whisper-$MODEL_NAME"
    echo "================================================================="
    echo "  KDE AI Chat - Downloading STT Model: $MODEL_NAME"
    echo "================================================================="
    echo '{"type":"setup_status","status":"downloading_model","percent":30}'
    VENV_PY="$VENV_DIR/bin/python3"
    if [ ! -f "$VENV_PY" ]; then
        VENV_PY="$VENV_DIR/bin/python"
    fi
    if [ ! -f "$VENV_PY" ]; then
        echo "❌ Error: Virtual environment python not found at $VENV_DIR. Please run venv setup first."
        wait_for_keypress
        exit 1
    fi
    VENV_BIN="$(dirname "$VENV_PY")"
    HF_CLI="$VENV_BIN/huggingface-cli"
    if [ -f "$HF_CLI" ]; then
        "$HF_CLI" download "$REPO"
    else
        echo "❌ Error: huggingface-cli not found in venv. Please run venv setup first."
        wait_for_keypress
        exit 1
    fi
    echo '{"type":"setup_status","status":"done","percent":100}'
    echo "================================================================="
    echo "  ✓ STT model downloaded successfully!"
    echo "================================================================="
    echo ""
    wait_for_keypress
    exit 0
fi

if [ "$MODE" = "download_tts" ]; then
    MODEL_NAME="${3:-kokoro-82m}"
    echo "================================================================="
    echo "  KDE AI Chat - Downloading TTS Model: $MODEL_NAME"
    echo "================================================================="
    echo '{"type":"setup_status","status":"downloading_model","percent":30}'
    VENV_PY="$VENV_DIR/bin/python3"
    if [ ! -f "$VENV_PY" ]; then
        VENV_PY="$VENV_DIR/bin/python"
    fi
    if [ ! -f "$VENV_PY" ]; then
        echo "❌ Error: Virtual environment python not found at $VENV_DIR. Please run setup first."
        wait_for_keypress
        exit 1
    fi
    VENV_BIN="$(dirname "$VENV_PY")"
    HF_CLI="$VENV_BIN/huggingface-cli"

    if [ "$MODEL_NAME" = "piper" ]; then
        MODELS_DIR="$HOME/.local/share/kdeaichat/models/piper"
        mkdir -p "$MODELS_DIR"
        echo "  Downloading English medium voice model (lessac) for Piper..."
        curl -L -o "$MODELS_DIR/en_US-lessac-medium.onnx" "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx"
        curl -L -o "$MODELS_DIR/en_US-lessac-medium.onnx.json" "https://huggingface.co/rhasspy/piper-voices/resolve/v1.0.0/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json"
    elif [ "$MODEL_NAME" = "f5-tts" ]; then
        if [ -f "$HF_CLI" ]; then
            "$HF_CLI" download "m-a-p/F5-TTS"
        else
            echo "❌ Error: huggingface-cli not found in venv. Please run setup first."
            wait_for_keypress
            exit 1
        fi
    else
        # default: kokoro-82m
        if [ -f "$HF_CLI" ]; then
            "$HF_CLI" download "hexgrad/Kokoro-82M"
        else
            echo "❌ Error: huggingface-cli not found in venv. Please run setup first."
            wait_for_keypress
            exit 1
        fi
    fi

    echo '{"type":"setup_status","status":"done","percent":100}'
    echo "================================================================="
    echo "  ✓ TTS model $MODEL_NAME downloaded successfully!"
    echo "================================================================="
    echo ""
    wait_for_keypress
    exit 0
fi

if [ "$MODE" = "install_espeak" ]; then
    echo "================================================================="
    echo "  KDE AI Chat - Installing espeak-ng (Phonemizer)"
    echo "================================================================="
    if command -v apt-get >/dev/null 2>&1; then
        echo "  Detected Debian/Ubuntu/Mint (apt)..."
        sudo apt-get update && sudo apt-get install -y espeak-ng
    elif command -v dnf >/dev/null 2>&1; then
        echo "  Detected Fedora/RHEL (dnf)..."
        sudo dnf install -y espeak-ng
    elif command -v pacman >/dev/null 2>&1; then
        echo "  Detected Arch Linux (pacman)..."
        sudo pacman -S --noconfirm espeak-ng
    elif command -v zypper >/dev/null 2>&1; then
        echo "  Detected openSUSE (zypper)..."
        sudo zypper install -y espeak-ng
    elif command -v emerge >/dev/null 2>&1; then
        echo "  Detected Gentoo (emerge)..."
        sudo emerge app-accessibility/espeak-ng
    elif command -v apk >/dev/null 2>&1; then
        echo "  Detected Alpine Linux (apk)..."
        sudo apk add espeak-ng
    else
        echo "❌ Error: Could not auto-detect package manager."
        echo "  Please install the 'espeak-ng' package manually using your distribution package manager."
    fi
    echo "================================================================="
    echo ""
    wait_for_keypress
    exit 0
fi

echo "================================================================="
echo "  KDE AI Chat - Virtual Environment setup for TTS and STT"
echo "================================================================="

# Check if venv is already fully set up
if [ -d "$VENV_DIR" ]; then
    VENV_PY="$VENV_DIR/bin/python3"
    if [ ! -f "$VENV_PY" ]; then
        VENV_PY="$VENV_DIR/bin/python"
    fi
    if [ -f "$VENV_PY" ] && "$VENV_PY" -c "import faster_whisper, kokoro, sounddevice, numpy, soundfile, huggingface_hub, scipy, transformers, phonemizer" 2>/dev/null; then
        echo "  ✓ Virtual environment already exists at: $VENV_DIR"
        echo "  ✓ All required Python packages are already installed."
        echo "================================================================="
        echo ""
        wait_for_keypress
        echo ""
        exit 0
    fi
fi

cleanup_on_error() {
    echo ""
    echo "❌ ERROR: Venv setup failed during package installation!"
    echo "  Virtual environment at: $VENV_DIR was kept."
    echo "  You can run the venv setup again to resume installing the missing packages."
    echo "================================================================="
    echo ""
    wait_for_keypress
    echo ""
    exit 1
}
trap cleanup_on_error ERR

echo "  Preparing setup environment at: $VENV_DIR"
if [ -d "$VENV_DIR" ]; then
    VENV_PY="$VENV_DIR/bin/python3"
    if [ ! -f "$VENV_PY" ]; then
        VENV_PY="$VENV_DIR/bin/python"
    fi
    if [ ! -f "$VENV_PY" ]; then
        echo "  Existing virtual environment seems broken (missing Python executable). Recreating..."
        rm -rf "$VENV_DIR"
    else
        echo "  Using existing virtual environment to resume/update packages..."
    fi
fi

echo "  Creating virtual environment ($MODE mode)..."
echo '{"type":"setup_status","status":"creating_venv","percent":10}'

python3 -m venv "$VENV_DIR"

echo '{"type":"setup_status","status":"upgrading_pip","percent":20}'

echo "  Upgrading pip, setuptools, and wheel..."
"$VENV_DIR/bin/pip" install --upgrade pip setuptools wheel

echo '{"type":"setup_status","status":"installing_pytorch","percent":35}'

if [ "$MODE" = "gpu" ]; then
    echo "  Installing GPU (CUDA) enabled PyTorch and runtime libraries..."
    # Install standard torch (comes with CUDA by default on Linux) and nvidia runtime packages
    "$VENV_DIR/bin/pip" install torch nvidia-cublas-cu12 nvidia-cudnn-cu12
else
    echo "  Installing CPU-only PyTorch (efficient space-saving wheel)..."
    # Install cpu-only PyTorch to avoid massive ~2GB CUDA download
    "$VENV_DIR/bin/pip" install torch --index-url https://download.pytorch.org/whl/cpu
fi

echo '{"type":"setup_status","status":"installing_spacy","percent":65}'

echo "  Installing spacy>=3.8.0 (ensures pre-built wheels on Python 3.13)..."
"$VENV_DIR/bin/pip" install "spacy>=3.8.0"

echo '{"type":"setup_status","status":"installing_dependencies","percent":75}'

echo "  Installing voice helper and core dependencies (faster-whisper, sounddevice, etc.)..."
"$VENV_DIR/bin/pip" install \
    faster-whisper \
    sounddevice \
    numpy \
    soundfile \
    huggingface_hub \
    loguru \
    scipy \
    transformers \
    num2words \
    espeak-phonemizer \
    phonemizer \
    piper-tts

echo '{"type":"setup_status","status":"installing_kokoro","percent":90}'

echo "  Installing speech models dependencies (kokoro, misaki)..."
"$VENV_DIR/bin/pip" install --no-deps kokoro misaki

echo '{"type":"setup_status","status":"done","percent":100}'
echo "-----------------------------------------------------------------"
echo "  ✓ Virtual environment setup ($MODE) completed successfully!"
echo "================================================================="
echo ""
wait_for_keypress
echo ""

