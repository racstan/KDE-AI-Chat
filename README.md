# KDE AI Chat — Native KDE Plasma 6 AI Chat Widget

[![KDE Store](https://img.shields.io/badge/KDE%20Store-Download-blue?style=for-the-badge&logo=kde)](https://store.kde.org/p/2360152/) [![GitHub Release](https://img.shields.io/github/v/release/racstan/KDE-AI-Chat?style=for-the-badge&color=success)](https://github.com/racstan/KDE-AI-Chat/releases)

A native, fast, and easy-to-use AI chat assistant widget for the **KDE Plasma 6** desktop. It connects directly to your favorite AI providers (including offline local models), lets you drag-and-drop files, schedule automated tasks, and securely save your API keys.

---

### 📸 Gallery & Features

| Screenshot | Description |
| :--- | :--- |
| ![Live Chat UI](.github/assets/image.png) | **Simple Chat UI**: A clean conversation interface with full Markdown formatting (lists, tables, code blocks) that scrolls smoothly. |
| ![OpenCode Bridge](.github/assets/image2.png) | **OpenCode Developer Bridge**: Connects your chat directly to your local OpenCode code-editing workspace for running commands and writing scripts. |
| ![Conversations Sidebar](.github/assets/image3.png) | **Chat History Sidebar**: Easily manage your past chats. You can rename, archive, or delete threads with one click. |
| ![OpenCode Settings](.github/assets/image4.png) | **Settings Panel**: Easily manage your settings, toggle developer features, choose AI models, and set up your system preferences. |
| ![API Key Storage Settings](.github/assets/image5.png) | **Secure Storage & Prompts**: Save your API keys safely. Keys are automatically synced with KDE's secure KWallet vault. |

---

## Key Features

- **🛡️ OpenCode Developer Bridge**: Connect the widget to your local code workspace. Run code, search the web, and execute tasks directly from your desktop panel.
- **🗣️ Local Voice Mode (STT & TTS)**: Talk to the AI hands-free. Speaks out loud using local voice tools (configured via Python).
- **📎 Drag & Drop Files**: Paste or drag images, PDFs, CSVs, Word documents, and text files directly into the chat. You can even send a file without typing any text.
- **📝 Prompt Templates**: Save prompts you use often in the settings. Type `/<name>` in the chat to insert them instantly.
- **📅 Task Scheduler**: Set up recurring tasks (like automated code checks or periodic reminders) using simple calendar schedules or cron expressions.
- **🌳 Edit Messages & Rewind**: Edit any older question to clear the messages after it and restart the conversation from that point.
- **🔑 Secure API Key Storage**: Safely save your keys. The widget encrypts keys in KDE's secure password manager (KWallet) and falls back to a local config file (`~/.config/kdeaichatrc`) if KWallet is off.
- **🔄 15+ AI Providers**: Works with OpenAI, Claude, Groq, DeepSeek, Gemini, OpenRouter, Mistral, Ollama, LM Studio, LiteLLM Proxy, and more.
- **📤 Export Chats**: Save your chat history as Markdown (`.md`) or plain text (`.txt`) with a single click.
- **🧭 Quick Navigation**: Easily jump between your questions in a long chat using the Up and Down arrow buttons.
- **⚡ Smooth Scrolling**: Enhanced layout scrolling that won't jump or jitter as messages load.
- **🎨 Resizable Widget**: Drag the bottom-right corner of the chat popup to resize it exactly how you want.

---

## What's New Since v1.2.6

- **Settings Auto-Save**: Your settings and API keys save automatically as you type — no "Apply" or "Save" button needed.
- **Auto-Trim Keys**: Automatically removes accidental spaces or line breaks when you paste your API keys.
- **Dynamic Model Fetching**: Click "Refresh Models" in the settings to automatically fetch the list of available models from your AI provider.
- **LiteLLM Proxy Support**: Easily connect to a local LiteLLM server to use hundreds of models via a single keyless interface.

---

## Installation

### Option 1: Install from the Desktop (Recommended)
1. Right-click your desktop background or panel and select **Add Widgets...**
2. Click **Get New Widgets** -> **Download New Plasma Widgets...**
3. Search for **"KDE AI Chat"** and click **Install**.

### Option 2: Web Browser Download (KDE Store)
1. Go to the [KDE Store Page for KDE AI Chat](https://store.kde.org/p/2360152/).
2. Click the **Download** button to get the `.plasmoid` file.
3. Install it using the terminal:
   ```bash
   kpackagetool6 -i /path/to/downloaded-package.plasmoid
   ```

### Option 3: Install from Source (For Developers)
1. Clone the repository:
   ```bash
   git clone https://github.com/racstan/KDE-AI-Chat.git
   cd KDE-AI-Chat
   ```
2. Run the installer script:
   ```bash
   ./install.sh
   ```
3. Restart your Plasma shell to apply changes:
   ```bash
   systemctl --user restart plasma-plasmashell.service
   ```
4. Right-click your desktop/panel, select **Add Widgets...**, and add **KDE AI Chat**!

---

## System Dependencies

The widget works out of the box, but some features need basic system tools. If a tool is missing, the widget will show a helpful warning inside the chat and explain what to install:

| Feature | Tool Needed | Debian/Ubuntu | Arch Linux | Fedora |
| :--- | :--- | :--- | :--- | :--- |
| **Reading PDFs** | `pdftotext` | `sudo apt install poppler-utils` | `sudo pacman -S poppler` | `sudo dnf install poppler-utils` |
| **Reading Word Docs** | `pandoc` | `sudo apt install pandoc` | `sudo pacman -S pandoc-cli` | `sudo dnf install pandoc` |
| **Secure Key Storage** | `qdbus6` / `qdbus` | *Pre-installed* | *Pre-installed* | *Pre-installed* |

---

## Code Quality & Performance

- **Zero Errors**: Fully passes QML analysis checks (`qmllint`) with zero warnings and zero errors.
- **Fast and Lightweight**: Heavy API calls and file processing are run in the background so your desktop never freezes.
- **Secure Handling**: Safe DBus variables and config paths to prevent system exploits or shell injection issues.

---

## Documentation Guides

- [User Operations Manual](user_manual.md) — Step-by-step instructions on chat history, OpenCode, and Prompt Templates.
- [Voice Setup Guide](VOICE_SETUP.md) — How to set up Speech-to-Text and Text-to-Speech engines locally.
- [API Keys Setup Guide](SETUP.md) — How to get API keys for each provider.

---

## License

GPL-2.0+ — See `metadata.json` for details.
