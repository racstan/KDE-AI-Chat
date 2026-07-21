# KDE AI Chat Voice Setup (Beta Feature)

This guide walks you through setting up Voice Tools (Speech-to-Text and Text-to-Speech), which are currently in Beta, for your KDE AI Chat application.

## Prerequisites

Voice tools rely on Python and a set of local dependencies to function smoothly. The built-in "Repair Engine" handles most of this, but here are the key steps:

### 1. The Virtual Environment

When you click **Repair Engine** in the widget's settings, a dedicated Python virtual environment is created at `~/.local/share/kdeaichat/venv`. 
It will automatically download and install:
- `faster-whisper` for Speech-to-Text
- `kokoro-onnx` and `sounddevice` for Text-to-Speech and audio playing

If you encounter issues, or just want to wipe your setup and start over, you can simply delete the `venv` directory:
```bash
rm -rf ~/.local/share/kdeaichat/venv
```
Then, click **Repair Engine** inside the widget to rebuild it from scratch.

### 2. GPU Acceleration (CUDA)

If you have an NVIDIA graphics card, you can significantly speed up voice processing:
1. In the Voice Tools settings, check **GPU Usage (CUDA)**.
2. If your status shows **GPU libraries: Missing**, click the **Repair Engine** button.
3. The system will download the GPU-enabled versions of PyTorch (which are heavy, around 3GB).
4. Once completed, the status will show **GPU libraries: Installed**, and your voice processing will be drastically faster.

*Note: Currently, only NVIDIA GPU (CUDA) is supported. AMD, Intel, and other GPU architectures are not supported. If you do not have an NVIDIA GPU, leave this option disabled, as installing CUDA libraries without the hardware will just waste disk space and could break CPU processing.*

### 3. Required System Packages

The TTS engine (`kokoro`) requires `espeak-ng` to process words. If your status says "espeak-ng missing", please run the appropriate command for your Linux distribution:

- **Ubuntu / Debian**: `sudo apt install espeak-ng`
- **Fedora**: `sudo dnf install espeak-ng`
- **Arch Linux**: `sudo pacman -S espeak-ng`
- **openSUSE**: `sudo zypper install espeak-ng`

Also make sure you have standard audio libraries (like `portaudio19-dev` or `python3-pyaudio`) if required by your distro for `sounddevice`.

## Setting Up Models

There are two ways to get the AI voice models for STT and TTS:

### Option A: Automatic Download (Recommended for Beginners)
You do not need to hunt for models yourself!
1. Open the Voice Tools settings.
2. Leave the **STT folder** and **TTS folder** paths completely empty.
3. Click **Check**.
4. The system will automatically download the standard models (`faster-whisper-small` and `kokoro-82m`) in the background the first time you use them. Note: Your first voice prompt or read-aloud might take an extra minute or two to execute while the models download to your cache.

### Option B: Bring Your Own Models (Advanced)
If you already have specific models downloaded, you can point the application to them.
1. For STT, browse and select a folder containing `faster-whisper` CTranslate2 model files (e.g. `model.bin` or `model.safetensors`).
2. For TTS, browse and select a folder containing `.onnx` models.

## Troubleshooting

- **"Engine is damaged" or "Repair Engine" keeps showing up:** Try deleting your virtual environment folder (`rm -rf ~/.local/share/kdeaichat/venv`) and clicking Repair Engine again. Ensure your system's python development packages (e.g., `python3-venv`, `python3-dev`) are installed.
- **Microphone not found:** Check your system's PulseAudio or PipeWire settings to ensure a default microphone is selected and unmuted.
- **Continuous Spinning Icon:** Make sure your `voice_helper.py` isn't blocked by missing dependencies. Checking the CLI logs might help identify missing C-libraries.

---

### 🧪 Verified Compatible Models

The voice engine has been tested and verified with the following models:
- **Text-to-Speech (TTS)**: Tested on **Kokoro-82m** (ONNX format) for rapid, high-quality local voice synthesis.
- **Speech-to-Text (STT)**: Tested on **Whisper Small** (default, lightweight) and **Whisper Large (v3)** (for maximum accuracy) in CTranslate2 (`faster-whisper`) format.

