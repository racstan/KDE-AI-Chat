# Advanced Features & System Integration — User Guide

KDE AI Chat provides advanced features designed for power users, developers, and those looking to enhance their widget experience with voice features, local background services, and resource monitoring.

This guide covers:
1. [Virtual Environment (Venv) Setup](#1-virtual-environment-venv-setup)
2. [Speech Features: STT & TTS](#2-speech-features-stt--tts)
3. [Memory Usage Tracking](#3-memory-usage-tracking)
4. [Custom Chat Storage](#4-custom-chat-storage)
5. [Secure Credential Storage (KWallet)](#5-secure-credential-storage-kwallet)

---

## 1. Virtual Environment (Venv) Setup

To keep your system clean, KDE AI Chat manages its speech capabilities inside a Python Virtual Environment (`venv`). This virtual environment isolates dependencies such as PyTorch, Faster Whisper, and Kokoro.

### CPU Setup vs. GPU Setup

You can set up the virtual environment in one of two modes from the **Advanced Settings** page:

*   **CPU Setup (Recommended for general use):**
    *   Installs a light-weight CPU-only PyTorch build (~150MB instead of 2.2GB).
    *   Extremely resource-friendly and runs on any CPU-compatible hardware.
*   **GPU Setup (NVIDIA CUDA):**
    *   Installs full GPU-accelerated PyTorch with CUDA 12 and cuDNN library bindings.
    *   Requires a compatible NVIDIA graphics card with NVIDIA drivers installed on the host system.
    *   Significantly speeds up speech-to-text (STT) transcription and text-to-speech (TTS) synthesis.

### Running Setup

1. Open the widget's settings page and select **Advanced Features**.
2. Under the **Voice & Audio** section, toggle **Enable voice features** ON.
3. Click either **Run CPU Setup** or **Run GPU Setup**. A terminal emulator (Konsole or similar) will launch to show live progress of pip installations.
4. Once completed, press any key to exit the terminal.
5. Click **Check Status** in the widget settings to verify that all packages show as `Installed`.

---

## 2. Speech Features: STT & TTS

With the environment initialized, you can enable local high-quality Speech-to-Text and Text-to-Speech engines. **Note:** KDE AI Chat relies on the user to download model files manually and provide their paths. Automated downloads have been removed to prevent setup failures and give users full control over model variants.

### Speech-to-Text (STT)
Powered by **Faster Whisper**, which runs OpenAI's Whisper model locally.
*   **Download:** Click the **Download Models (Hugging Face)** button to open Hugging Face search for `faster-whisper` models.
*   **Model Path:** Enter the directory path containing your manually downloaded Whisper model (containing files like `model.bin`, `config.json`, etc.) in the **STT model path** field.

### Text-to-Speech (TTS)
Supports multiple neural TTS models including **Kokoro-82M**, **Piper**, **F5-TTS**, and **Coqui-TTS**, as well as a native system **eSpeak-NG** fallback.
*   **Auto-Detection:** The widget automatically detects the TTS engine/provider based on the path you enter in the **TTS model path** field:
    *   Paths containing `kokoro` will run using **Kokoro**.
    *   Paths containing `piper` or ending with `.onnx` will run using **Piper**.
    *   Paths containing `f5` will run using **F5-TTS**.
    *   Paths containing `coqui` will run using **Coqui-TTS**.
    *   If left empty, it falls back to native system **eSpeak-NG**.
*   **Download:** Click the **Download Models (Hugging Face)** button to find models on Hugging Face.
*   **Model Path:** Enter the folder or file path to your manually downloaded TTS model in the **TTS model path** field.
*   **Voices:** Choose from curated voices to read your messages aloud.
*   **Speak Test:** Enter custom text in the **Test TTS** input box and click **Speak Test** to hear the synthesis immediately.

### eSpeak-NG Configuration
Neural TTS engines require a phonemizer (like `espeak-ng`) to convert text into phoneme sounds.
*   **Separate Category:** eSpeak-NG settings are grouped into a dedicated panel.
*   **eSpeak Path:** Specify the path to your manual `espeak-ng` binary.
*   **System Package Installer:** Click **Install via Package Manager** to automatically install `espeak-ng` via your system's package manager (e.g. `apt`, `dnf`, `pacman`, `zypper`).

---

## 3. Memory Usage Tracking

The **Memory Usage** section monitors the system impact of the background daemons.

*   **Monitored Daemons:**
    *   **Scheduler Daemon:** Automated prompt injector (`kde-ai-scheduler.py`).
    *   **OpenCode Bridge:** Local code developer server (`opencode`).
    *   **STT Daemon:** Background speech recognition server.
    *   **TTS Daemon:** Background text-to-speech server.
*   **How it works:** Reads `/proc/[pid]/status` directly to calculate precise RSS (Resident Set Size) RAM footprint.
*   **Refresh:** Click **Refresh** to instantly query the system and calculate live total memory consumption.

---

## 4. Custom Chat Storage

By default, chat history is saved to the standard user config directory (`~/.config/kdeaichat`). You can change this location to export, sync, or backup your data easily:

1. Under the **Chat Storage** section, click **Browse...**.
2. Select your desired directory.
3. The widget will automatically sync all historical chat sessions to the new location.

---

## 5. Secure Credential Storage (KWallet)

API Keys can be stored securely using standard desktop keyrings instead of plain-text configuration files.

*   **Mode Settings:** Select **KWallet** or **File System (plaintext)**.
*   **Automated Prompts:** Securely prompts for your wallet decryption password when retrieving credentials during start-up or prompt execution.
*   **Attempt Limits:** The keyring interface handles password prompts gracefully, stopping after 3 unsuccessful attempts to prevent locking.

---

## 6. Development Log & Audit Summary

Below is a record of recent updates, audit findings, and troubleshooting details for the advanced features section:

### What We Did (Session Overview)
*   **Manual Model Paths and HF Search Links:** Completely removed the automatic download system. Downloading models is now the user's responsibility. The Download buttons open Hugging Face search queries directly.
*   **TTS Provider Auto-Detection:** Removed the manual TTS provider dropdown selection. The active TTS provider is dynamically detected from the manual model path (detecting Kokoro, Piper, F5-TTS, Coqui, or falling back to espeak-ng).
*   **Dedicated eSpeak-NG Panel:** Extracted the eSpeak-NG configuration into a dedicated category panel, cleanly separating it from STT and TTS configuration groups.
*   **Selectable STT Result and TTS Status Fields:** Replaced the previous dynamic result label with read-only, copy-enabled `QQC2.TextField` input blocks for STT transcriptions and live TTS status messages (Synthesizing, Playing, Done, or Errors), providing detailed feedback on playback errors.
*   **Terminal execution simplification:** Rewrote terminal launchers to pass direct command parameters (`konsole -e bash <script_path> <args>`) rather than complex nested quoted commands.
*   **Interactive prompt resilience:** Introduced a robust TTY checking helper (`wait_for_keypress`) in `voice_setup.sh` that detects if standard input is a terminal or character device, preventing execution termination on missing TTY devices.
*   **Installation script consolidation:** Moved model downloading and distribution package manager installer command compositions out of QML and directly into central sub-modes of `voice_setup.sh` for unified terminal output, progress visualizers, and keypress handling.
*   **Configurable CPU/GPU Setup:** Decoupled virtual environment setups into explicit GPU (with CUDA libraries) and CPU (lightweight/clean) setups.
*   **Speech Decoupling:** Decoupled model files from the main python library dependencies. Added selection dropdowns to download model files separately or specify existing local paths.
*   **Clarified Helper UI Elements:** Overhauled placeholder texts in speech input fields to prevent setup confusion.
*   **Venv Uninstaller / Eraser:** Configured a complete file deletion routine to clean up the virtual environment directory and Hugging Face hub cache directory upon uninstallation.

### Problems Found & Fixed
*   **Silent TTS Playback Failures:** Addressed silent failures in TTS synthesis/playback by capturing the synthesis events, exposing errors in the status field, and handling errors gracefully.
*   **Hardcoded Environment Checks:** Updated the environment verification schema to respect user selection of Kokoro-82m models dynamically.
*   **Blank screens in terminal setups:** Fixed an issue where nested single quotes inside `konsole -e bash -c` caused newer version shells to exit instantly or render a blank window due to parsing errors.
*   **Input Blocking & /dev/tty errors:** Replaced raw `read </dev/tty` commands with safe TTY device presence checks so setup doesn't fail silently or crash when spawned in environments without active character device streams.
*   **Variable Scope Typos:** Resolved helper execution crashes caused by namespace collisions (e.g., `custom_path` variable vs. `custom_model_path`) during local voice synthesis initialization.
*   **Package Manager Autodetect Failures:** Added fallback package management setups for a wider array of Linux distributions (Arch, Fedora, openSUSE, Debian) within the `espeak-ng` installer.
*   **D-Bus & Audio System Connection:** Solved systemd audio playback failures in background daemons by routing commands directly to local user shells where PipeWire/PulseAudio session environment variables are populated.

### Audit Pass (Latest)
*   **Simplified Verification Grid:** Replaced 8 hardcoded status rows (Microphone, Audio player, Venv, STT library, TTS library, Phonemizer, STT model, TTS model) with 3 dynamic summary entries: STT, TTS, and Phonemizer. Each entry shows the first actionable reason for failure instead of raw library status.
*   **Service-Gated Testing:** Test STT and Test TTS controls are now only visible when their respective systemd services are running. A hint label tells the user to start the service first.
*   **Autostart Fix:** The Enable Autostart buttons now call `setupVoiceServices()` to create the systemd service files before running `systemctl --user enable`, preventing "unit not found" failures.
*   **Removed Play Recorded Audio:** Removed the dead "Play Recorded Audio" button and its associated `recordedAudioPath` property.
*   **UI Consistency:** Fixed STT Service label width to match TTS Service label (12 grid units).
