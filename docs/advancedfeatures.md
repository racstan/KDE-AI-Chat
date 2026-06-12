# Advanced Voice Features — STT & TTS User Guide

KDE AI Chat includes advanced features for voice interaction, allowing you to speak to the AI (Speech-to-Text) and have the AI speak its responses back to you (Text-to-Speech). These features run entirely locally on your system using high-quality open-source AI models.

---

## Architecture Overview

The voice features system consists of:
1. **TTS Daemon (`kde-ai-tts.service`)**: A local background server powered by **Kokoro-82M** (a state-of-the-art 82-million parameter multilingual text-to-speech model).
2. **STT Daemon (`kde-ai-stt.service`)**: A local background server powered by **Faster-Whisper** (highly optimized version of OpenAI's Whisper model).
3. **Isolated Python Virtual Environment (venv)**: All Python package dependencies (such as `torch`, `sounddevice`, `soundfile`, `faster-whisper`, `kokoro`, etc.) are installed in a dedicated environment to prevent conflicts with your system packages.

---

## Dependencies & Requirements

To use the voice features, the following system package dependencies are required:

- **espeak-ng**: Used by the TTS system for phonemization.
- **PortAudio**: Used by the `sounddevice` Python package to interface with the microphone and speakers.
- **PulseAudio / ALSA utils** (`paplay` / `aplay`): Used to play synthesized speech audio back smoothly.

### Auto-Installing espeak-ng & System Libraries
You can install these dependencies directly from the **Advanced Features** settings section by clicking the **Install** button next to **espeak-ng path**, or manually using your package manager:

- **Debian / Ubuntu / Mint**:
  ```bash
  sudo apt-get update && sudo apt-get install -y espeak-ng libportaudio2 pulseaudio-utils alsa-utils
  ```
- **Fedora**:
  ```bash
  sudo dnf install -y espeak-ng portaudio pulseaudio-utils alsa-utils
  ```
- **Arch Linux**:
  ```bash
  sudo pacman -S --noconfirm espeak-ng portaudio pulseaudio-utils alsa-utils
  ```

---

## Virtual Environment Setup

Because deep learning packages like PyTorch and Faster Whisper are large and require complex library bindings, KDE AI Chat installs them in an isolated virtual environment (`venv`). 

### CPU vs. GPU Setup
From the settings, you can choose to trigger one of two automated setup modes:

1. **CPU Setup**:
   - Best for systems without an NVIDIA GPU or with limited RAM.
   - Installs PyTorch in CPU mode and Faster-Whisper/Kokoro.
   - Run by clicking **Run CPU Setup**.

2. **GPU Setup**:
   - Best for systems with NVIDIA graphics cards.
   - Installs PyTorch with CUDA acceleration to run models significantly faster.
   - **Note**: Requires working NVIDIA CUDA drivers and libraries installed on your host system.
   - Run by clicking **Run GPU Setup**.

Both setups open a terminal window running the setup script. When the installation finishes, you will be prompted to **"Press any key to exit..."**.

### Changing the Virtual Environment Path
By default, the venv is created at:
`~/.local/share/kdeaichat/venv`

You can customize this path in the **Advanced Features** configuration settings under **Virtual Env Path**.

---

## Models configuration

To avoid redownloading models every time or if you are running in an offline environment, you can point the application to locally cached models:

### 1. Custom STT Model Path
If left blank, Faster-Whisper will download the default `large-v3-turbo` model from Hugging Face on demand.
If you have downloaded a Whisper model manually (containing `model.bin`, `config.json`, etc.), enter its folder path or browse to it.

### 2. Custom TTS Model Path
If left blank, Kokoro will download `kokoro-82m` on demand.
If you have downloaded the Kokoro model files (containing `kokoro-v0_19.pth` or similar and `config.json`), browse to the directory containing those files.

---

## Testing Voice Features

To verify your configuration, use the testing utilities in the settings panel:

### Testing STT (Speech-to-Text)
1. Click **Test STT**. The status will transition to `Recording...` (for 5 seconds).
2. Speak clearly into your microphone.
3. The status will transition to `Transcribing...` and display the recognized text in the settings view.
4. (Optional) Click **Play Recorded Audio** to hear what was captured.

### Testing TTS (Text-to-Speech)
1. Enter any test text in the **Test TTS** input field.
2. Click **Speak Test**. The system will synthesize the text and play it back.
3. Click **Stop** at any time to interrupt the audio playback.

---

## File and Service Locations

| Path | Purpose |
|------|---------|
| `~/.local/share/kdeaichat/venv` | Isolated Python Virtual Environment |
| `~/.config/systemd/user/kde-ai-tts.service` | systemd service unit for TTS daemon |
| `~/.config/systemd/user/kde-ai-stt.service` | systemd service unit for STT daemon |
| `/org.kde.plasma.kdeaichat/contents/ui/voice/voice_setup.sh` | Main shell script for CPU/GPU setups |
| `/org.kde.plasma.kdeaichat/contents/ui/voice/voice_helper.py` | Python server handling local speech inference |
