#!/bin/bash
# venv_setup.sh [venv-dir] [auto|cpu|gpu] [parakeet|faster-whisper]
# Creates the Python venv for the on-demand speech-to-text service, for one engine:
#  - parakeet (the default): transcribe.cpp's Python binding and its prebuilt
#    library (about 24 MB, CPU and Vulkan GPU built in: no CUDA wheels, no torch).
#  - faster-whisper: faster-whisper with CTranslate2 and onnxruntime only (no
#    torch, spacy or transformers). GPU support (cuBLAS + cuDNN wheels, about
#    1.3 GB) is added when an NVIDIA GPU is found; "cpu" or "gpu" overrides.
# Read aloud needs no venv. The download size is printed first (the settings
# page shows it before running this); models are downloaded separately.

set -e

VENV_DIR="${1:-${XDG_DATA_HOME:-$HOME/.local/share}/kdeaichat/venv}"
# Expand tilde if present
VENV_DIR="${VENV_DIR/#\~/$HOME}"
MODE="${2:-auto}"
ENGINE="${3:-parakeet}"
[ "$ENGINE" = "faster-whisper" ] || ENGINE=parakeet
# transcribe.cpp is pre-1.0: the binding and the native library must be the same version.
TRANSCRIBE_CPP_VERSION="0.4.1"

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


if [ "$MODE" != "cpu" ] && [ "$MODE" != "gpu" ]; then
    if [ -e /proc/driver/nvidia/version ] || [ -e /dev/nvidia0 ]; then MODE=gpu; else MODE=cpu; fi
fi
GPU_FLAG=false
[ "$MODE" = "gpu" ] && GPU_FLAG=true

echo "================================================================="
echo "  KDE AI Chat - speech-to-text engine ($ENGINE, $MODE)"
echo "================================================================="

HELPER="$(cd "$(dirname "$0")/.." && pwd)/kde_ai_helper.py"
if [ -f "$HELPER" ]; then
    SIZE_PAYLOAD=$(python3 -c 'import base64, json, sys; print(base64.b64encode(json.dumps({"venv": sys.argv[1], "gpu": sys.argv[2] == "true", "sttEngine": sys.argv[3]}).encode()).decode())' "$VENV_DIR" "$GPU_FLAG" "$ENGINE")
    python3 "$HELPER" stt_setup_size "$SIZE_PAYLOAD" || true
fi

venv_python() {
    if [ -f "$VENV_DIR/bin/python3" ]; then echo "$VENV_DIR/bin/python3"; else echo "$VENV_DIR/bin/python"; fi
}

ready_check() {
    local py
    py="$(venv_python)"
    [ -f "$py" ] || return 1
    if [ "$ENGINE" = "parakeet" ]; then
        "$py" -c "import sys, transcribe_cpp; sys.exit(transcribe_cpp.__version__ != sys.argv[1])" "$TRANSCRIBE_CPP_VERSION" 2>/dev/null || return 1
        return 0
    fi
    "$py" -c "import faster_whisper, ctranslate2, av, sys; sys.exit(int(av.__version__.split('.')[0]) >= 19)" 2>/dev/null || return 1
    if [ "$MODE" = "gpu" ]; then
        "$py" -c "import importlib.util as u; exit(0 if u.find_spec('nvidia.cublas') and u.find_spec('nvidia.cudnn') else 1)" 2>/dev/null || return 1
    fi
    return 0
}

if ready_check; then
    echo "  $ENGINE is already installed at: $VENV_DIR"
    echo '{"type":"setup_status","status":"done","percent":100}'
    wait_for_keypress
    exit 0
fi

cleanup_on_error() {
    echo '{"type":"setup_error","error":"Installing the speech-to-text engine failed. Check your internet connection and the pip output, then try again."}'
    echo "  Setup failed; the environment at $VENV_DIR was kept, so running it again resumes."
    wait_for_keypress
    exit 1
}
trap cleanup_on_error ERR

if [ -d "$VENV_DIR" ] && [ ! -f "$VENV_DIR/bin/python3" ] && [ ! -f "$VENV_DIR/bin/python" ]; then
    echo "  The existing environment is broken (no Python). Recreating it..."
    rm -rf "$VENV_DIR"
fi

echo '{"type":"setup_status","status":"creating_venv","percent":10}'
python3 -m venv "$VENV_DIR"

echo '{"type":"setup_status","status":"upgrading_pip","percent":20}'
"$VENV_DIR/bin/pip" install --upgrade pip

echo '{"type":"setup_status","status":"installing_dependencies","percent":40}'
if [ "$ENGINE" = "parakeet" ]; then
    # Prebuilt for x86_64 and aarch64 Linux; the Vulkan GPU backend is used when the driver has Vulkan.
    "$VENV_DIR/bin/pip" install "transcribe-cpp==$TRANSCRIBE_CPP_VERSION" "transcribe-cpp-native==$TRANSCRIBE_CPP_VERSION"
    echo '{"type":"setup_status","status":"done","percent":100}'
    echo "  Speech-to-text engine installed (Parakeet). The model is downloaded separately, with its size shown first."
    wait_for_keypress
    exit 0
fi

# PyAV 19 dropped an argument faster-whisper 1.2 passes; recordings are decoded without it anyway.
"$VENV_DIR/bin/pip" install faster-whisper "av<19"

if [ "$MODE" = "gpu" ]; then
    echo '{"type":"setup_status","status":"installing_gpu","percent":70}'
    # CTranslate2 4.x needs cuBLAS 12 and cuDNN 9; the service loads them from the venv.
    "$VENV_DIR/bin/pip" install nvidia-cublas-cu12 "nvidia-cudnn-cu12==9.*"
fi

echo '{"type":"setup_status","status":"done","percent":100}'
echo "  Speech-to-text engine installed ($MODE). Models are downloaded separately, with their size shown first."
wait_for_keypress
