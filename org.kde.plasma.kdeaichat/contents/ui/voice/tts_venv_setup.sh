#!/bin/bash
# tts_venv_setup.sh <venv-dir> [cpu|gpu]
# Creates the Python venv for read aloud's natural voice: kokoro-onnx with
# onnxruntime (no torch), about 50 MB. "gpu" adds onnxruntime-gpu with the
# CUDA and cuDNN libraries (about 2.5 GB) for NVIDIA cards. The voice model
# is downloaded by the helper (kdeaichat/tts_neural.py) after this.
# Settings → Voice shows the sizes before running it.

set -e

VENV_DIR="${1:?usage: tts_venv_setup.sh <venv-dir> [cpu|gpu]}"
MODE="${2:-cpu}"

echo "  KDE AI Chat - natural voice for read aloud (Kokoro, $MODE) in $VENV_DIR"

python_of() {
    if [ -f "$VENV_DIR/bin/python3" ]; then echo "$VENV_DIR/bin/python3"; else echo "$VENV_DIR/bin/python"; fi
}

if [ -d "$VENV_DIR" ] && [ ! -f "$VENV_DIR/bin/python3" ] && [ ! -f "$VENV_DIR/bin/python" ]; then
    echo "  The existing environment is broken (no Python). Recreating it..."
    rm -rf "$VENV_DIR"
fi
[ -d "$VENV_DIR" ] || python3 -m venv "$VENV_DIR"
PY="$(python_of)"

"$PY" -m pip install --quiet --upgrade pip
"$PY" -m pip install --quiet kokoro-onnx

if [ "$MODE" = "gpu" ]; then
    # The GPU build replaces the CPU one; the nvidia packages bring CUDA 12 and cuDNN 9.
    "$PY" -m pip install --quiet "onnxruntime-gpu[cuda,cudnn]"
    "$PY" -m pip uninstall --quiet -y onnxruntime
    "$PY" -m pip install --quiet --force-reinstall --no-deps onnxruntime-gpu
fi

"$PY" -c "import kokoro_onnx, onnxruntime"
echo "  Natural voice installed ($MODE)."
