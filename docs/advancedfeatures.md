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

With the environment initialized, you can enable local high-quality Speech-to-Text and Text-to-Speech engines.

### Speech-to-Text (STT)
Powered by **Faster Whisper**, which runs OpenAI's Whisper model locally.
*   **Model Selection:** Choose from multiple sizes (`tiny`, `base`, `small`, `medium`, `large-v3-turbo`) in the dropdown depending on your RAM/VRAM capacity.
*   **Download:** Click the **Download** button to pull the chosen model from Hugging Face via `huggingface-cli` (progress is shown in a terminal).
*   **Custom Model Path:** If you already have a model downloaded, specify its directory path in the **Custom STT model path** field.

### Text-to-Speech (TTS)
Powered by the state-of-the-art local neural TTS model **Kokoro-82M**.
*   **Phonemizer (`espeak-ng`):** Neural speech requires a phonemizer to translate words into sounds. Click **Install** next to the `espeak-ng path` label to automatically fetch this utility via your system's package manager (e.g., `apt`, `pacman`, `dnf`), or provide a custom directory path if installed manually.
*   **Voices:** Choose from curated high-quality voices (e.g., `af_heart`, `am_fenrir`, `bf_bella`, `bm_george`, etc.) to read your messages aloud.
*   **Speak Test:** Enter custom text in the **Test TTS** input box and click **Speak Test** to hear the synthesis immediately.

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
