# KDE AI Chat — User Manual

Welcome to **KDE AI Chat**, a native, premium AI companion built specifically for **KDE Plasma 6** and **Qt 6**.

This manual provides an in-depth operations guide, walkthroughs of every feature, advanced workflows, and troubleshooting FAQs.

---

## 📖 Table of Contents
1. [Getting Started & Installation](#1-getting-started--installation)
2. [Configuring Providers & API Keys](#2-configuring-providers--api-keys)
3. [Secure Storage: KWallet vs. Plain Configs](#3-secure-storage-kwallet-vs-plain-configs)
4. [Running Offline Local LLMs (Ollama, LM Studio & LiteLLM)](#4-running-offline-local-llms-ollama-lm-studio--litellm)
5. [OpenCode Developer Bridge Guide](#5-opencode-developer-bridge-guide)
6. [Scheduled AI Prompts](#6-scheduled-ai-prompts)
7. [Managing Conversations & Chat History](#7-managing-conversations--chat-history)
8. [Chat Export](#8-chat-export)
9. [File Attachments](#9-file-attachments)
10. [Frequently Asked Questions (FAQ)](#10-frequently-asked-questions-faq)

---

## 1. Getting Started & Installation

KDE AI Chat integrates seamlessly into your desktop. It can be pinned to your Plasma panel as an icon-popup or dragged directly onto the desktop wallpaper as an active widget.

### Native GUI Installation (Recommended)
1. Right-click your desktop wallpaper or panel and select **Add Widgets...**
2. Click **Get New Widgets** at the bottom of the sidebar, then select **Download New Plasma Widgets...**
3. In the search box, type **"KDE AI Chat"**.
4. Click **Install**. Once complete, drag the widget onto your panel or desktop.

### Command-Line Source Installation
If you prefer using the terminal or want to run the latest development branch:
```bash
# 1. Clone the repository
git clone https://github.com/racstan/KDE-AI-Chat.git
cd KDE-AI-Chat

# 2. Run the automated clean installation script
./install.sh

# 3. Restart the Plasma Shell to load the new widget database
systemctl --user restart plasma-plasmashell.service
```

---

## 2. Configuring Providers & API Keys

KDE AI Chat supports **21 different AI engines** out of the box. Key setups are handled directly inside the Widget's **Settings** panel (right-click widget → *Configure KDE AI Chat...*).

### Supported API Providers

| Provider | Default URL / Endpoint | Credentials Needed |
| :--- | :--- | :--- |
| **OpenAI** | `https://api.openai.com/v1` | OpenAI API Key |
| **Anthropic (Claude)** | `https://api.anthropic.com` | Anthropic API Key |
| **Groq** | `https://api.groq.com/openai/v1` | Groq API Key |
| **DeepSeek** | `https://api.deepseek.com` | DeepSeek API Key |
| **MiniMax** | `https://api.minimax.io/v1` | MiniMax API Key |
| **Fireworks AI** | `https://api.fireworks.ai/inference/v1` | Fireworks API Key |
| **Google Gemini** | `https://generativelanguage.googleapis.com/v1beta/openai/` | Google AI Studio Key |
| **OpenRouter** | `https://openrouter.ai/api/v1` | OpenRouter API Key |
| **Mistral** | `https://api.mistral.ai/v1` | Mistral API Key |
| **Cloudflare Workers AI** | `https://api.cloudflare.com/client/v4/accounts/<ID>/ai/v1` | CF API Token + Account ID |
| **NVIDIA NIM** | `https://integrate.api.nvidia.com/v1` | NVIDIA Developer Key |
| **Hugging Face** | `https://router.huggingface.co/v1` | HF User Token |
| **xAI (Grok)** | `https://api.x.ai/v1` | xAI API Key |
| **Qwen** | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1` | Qwen API Key |
| **Moonshot** | `https://api.moonshot.cn/v1` | Moonshot API Key |
| **MiMo** | `https://api.mimo.ai/v1` | MiMo API Key |
| **Maritaca** | `https://chat.maritaca.ai/api` | Maritaca API Key |
| **LM Studio** | `http://localhost:1234/v1` | Keyless / Offline |
| **Local (OpenAI-compatible)** | `http://localhost:11434/v1` | Keyless / Offline |
| **Ollama** | `http://localhost:11434/v1` | Keyless / Offline |
| **LiteLLM Proxy** | `http://localhost:4000/v1` | Optional (proxy-dependent) |

### Setting Up a Key
1. Open **Settings** → select your provider from the **Default provider** dropdown.
2. Paste your API key into the key field.
3. Click **Refresh Models** to auto-populate the model list.
4. Select your model and close Settings — your choice is saved automatically.

---

## 3. Secure Storage: KWallet vs. Plain Configs

KDE AI Chat offers **three modes** of API key storage, selectable from the Settings panel under **API Key Storage**:

### Mode 1: Session Only
- Keys are kept purely **in memory** while the widget is running.
- Discarded when the widget or Plasma shell is closed.
- Good for one-off use or shared machines.

### Mode 2: Plain Config
- Keys are saved persistently to **`~/.config/kdeaichatrc`**.
- Auto-loaded every time the widget starts.
- You can open, edit, and reload this file directly from the Settings panel using the **Open Config File** and **Reload from Config** buttons.
- Good for headless setups or manual key management.

### Mode 3: Secure KWallet *(recommended)*
- Keys are encrypted and stored inside your system's **[KDE Wallet](https://apps.kde.org/kwalletmanager5/)** via DBus (`qdbus6 org.kde.kwalletd6`).
- Loaded securely on startup — no plaintext exposure.
- Use the **Launch KWallet Manager** button in Settings to inspect or manage stored credentials.
- Recommended for general desktop use.

### Settings Panel Utilities
From the Settings panel you can also:
- **Open Config File** — opens `~/.config/kdeaichatrc` in your default text editor
- **Reload from Config** — re-reads keys from disk without restarting the widget
- **Launch KWallet Manager** — opens the [KDE Wallet Manager](https://apps.kde.org/kwalletmanager5/) app
- **Clear Chat** — wipes the active conversation

> **Tip**: Switching storage modes and entering keys is immediately reflected — no Apply button required.

---

## 4. Running Offline Local LLMs (Ollama, LM Studio & LiteLLM)

Enjoy complete privacy and local speed by pairing the widget with offline servers!

### Ollama Setup Walkthrough
1. **Install and run Ollama**: https://ollama.com
   ```bash
   ollama serve
   ```
2. **Configure CORS (Crucial for QML Networking)**:
   By default, local servers block connections that don't pass standard web verification. Ensure Ollama accepts connections:
   ```bash
   # Add this variable to your shell profiles (~/.bashrc or ~/.zshrc)
   export OLLAMA_ORIGINS="*"
   ```
3. **Configure the Widget**:
   - Open Settings, select **Ollama** from the Provider dropdown list.
   - Enter your Ollama endpoint URL (default is `http://localhost:11434/v1`).
   - Click **Refresh Models**. The dropdown will dynamically discover and fetch all model weights currently downloaded on your machine (e.g., `llama3.2`, `mistral`, `gemma2`, etc.).

### LM Studio Setup
1. Download and install [LM Studio](https://lmstudio.ai/).
2. Load a model in LM Studio, then start its local server.
3. In the widget, select **LM Studio** as the provider and use `http://localhost:1234/v1`.
4. Click **Refresh Models** to discover the loaded model.

### LiteLLM Proxy Setup
[LiteLLM](https://docs.litellm.ai/) acts as a universal OpenAI-compatible proxy that can route requests to 100+ LLMs.
1. Install LiteLLM: `pip install litellm`
2. Start your proxy: `litellm --model gpt-4o-mini` (or use a config file)
3. In the widget, select **LiteLLM Proxy** as the provider.
4. Set the URL to your proxy address (default `http://localhost:4000/v1`).
5. Enter an API key if your proxy requires one, or leave it blank for keyless setups.
6. Click **Refresh Models** to discover available models.

---

## 5. OpenCode Developer Bridge Guide

**[OpenCode](https://opencode.ai/)** ([GitHub: sst/opencode](https://github.com/sst/opencode)) is a local AI development agent that turns your chat session into an interactive code-writing and execution environment.

### Running OpenCode from the Widget
1. **Toggle Mode**: In the bottom bar of the main chat, toggle the **OpenCode** selector. Once activated, OpenCode becomes your default conversation engine.
2. **Start the Server**: Open Settings, navigate to the **OpenCode** tab, and click **Start OpenCode Server** (or use the configured start command).
3. **Connect**: Click **Refresh** in the widget header to discover the active connection. Select your preferred backing LLM provider and models.
4. **Session Tracking**: Once connected, the widget header displays the unique **Active OpenCode Session ID** in real-time.

### Interactive Security & Input Prompt Cards
OpenCode will occasionally require verification or clarification to run tools or process code.

- **Clarification Prompt Cards**: When OpenCode asks a question, an interactive card with a focus border renders inline in the chat bubble list.
- **Permission Cards**: When OpenCode needs to execute a shell command or write files, allow/deny buttons are rendered inline.
- **Actions**:
  - Type your response into the card's native text box and click **Submit** to feed the answer directly to the compiler.
  - Click **Dismiss** to reject the query.
  - The card dynamically preserves your actions, showing a success tick ✅ or rejection cross ❌ directly in the conversation history.

### Tool Invocation Context
When OpenCode executes tools (bash commands, file reads/writes, fetch requests), the widget displays them as collapsible context items on the assistant message bubble, including the tool name, input, and output.

### Token & Cost Diagnostics
Every assistant message in OpenCode mode shows real-time token usage (input, output, cache read/write) and estimated cost in USD.

See [opencode-bridge.md](opencode-bridge.md) for full technical reference.

---

## 6. Scheduled AI Prompts

The built-in scheduler lets you automate AI prompts at specific times or recurring intervals — without keeping the widget open.

### How It Works
A Python daemon (`kde-ai-scheduler.py`) runs as a systemd user service. It checks cron expressions every 15 seconds and writes trigger files to `~/.local/share/kdeaichat/pending/`, which the widget picks up and injects as messages.

### Setup
```bash
# Start the scheduler daemon (installed automatically by install.sh)
systemctl --user start kde-ai-scheduler.service

# Enable auto-start on login
systemctl --user enable kde-ai-scheduler.service
```

### Creating a Schedule
1. Click the **Schedule** button (clock icon) in the chat toolbar, or type `/schedule` in chat.
2. Click **New Schedule**.
3. Fill in the name, target session, message, task type (Single Run or Recurring), and timing.
4. Click **Save**.

### Schedule Types
- **Single Run**: Fires once at the specified date/time, then auto-disables.
- **Recurring**: Repeats at configured intervals (minutes, hours, days, weeks, months). Supports execution limits.

See [scheduler-usage.md](scheduler-usage.md) for full scheduler documentation.

---

## 7. Managing Conversations & Chat History

Conversation threads are tracked in the persistent session panel.

* **Renaming Threads**: Click the edit pencil icon next to any thread in the session list to enter a custom title.
* **Archiving Threads**: Move older conversations into a safe secondary filter list to keep your sidebar active and uncluttered.
* **Deleting Threads**: Click the trashcan icon to delete the thread and its stored data.
* **Visual Identifiers**: OpenCode chats are rendered with distinct system badges to instantly separate development workspaces from standard AI conversations.
* **Branching**: Click the **Edit** button on any older user message to automatically delete all subsequent messages and start a fresh branch from that point.

---

## 8. Chat Search

Search across the active conversation to find specific messages.

### How to Search
1. Press **Ctrl+F** (or click the search icon in the toolbar) to open the search bar.
2. Type your query — matches are highlighted in the chat as you type.
3. Use **Enter** / **Shift+Enter** (or the up/down arrow buttons) to jump between matches.
4. Press **Escape** or click the close button to dismiss the search bar.

### Keyboard Shortcuts
| Shortcut | Action |
|----------|--------|
| `Ctrl+F` | Toggle search bar |
| `Enter` | Next match |
| `Shift+Enter` | Previous match |
| `Escape` | Close search / stop streaming |

---

## 9. Chat Export

Export any conversation to a file directly from the chat toolbar.

### How to Export
1. Click the **Export** button (download icon) in the chat toolbar.
2. Choose your format: **Markdown (`.md`)** or **Plain Text (`.txt`)**.
3. The save dialog opens pre-filled with a filename: `<chat_title>_<timestamp>.<ext>`.
4. Choose a location and save.

### Export Format
- **Header**: Includes the chat title and export timestamp.
- **Messages**: Each message shows the role label (User / Assistant / System Error) and time.
- **Encoding**: Full UTF-8, safe for all languages and special characters.

---

## 10. File Attachments

### Supported Formats
- **PDF** — requires `pdftotext` (poppler-utils)
- **Word documents (.docx)** — requires `pandoc`
- **Images** — base64-encoded inline (PNG, JPG, WEBP, GIF)
- **Plain text** — TXT, CSV, JSON, XML, YAML, JS, TS, PY, SH, HTML, CSS

### How to Attach
1. **Drag and drop** a file onto the chat input area.
2. **Paste from clipboard** — the widget auto-detects file URIs, images, or text content from Wayland (`wl-paste`) or X11 (`xclip`).

### Clipboard Integration
- Copy any text in another application and paste directly into the chat input.
- For images on clipboard, the widget encodes them as base64 for vision-capable models.

---

## 11. Frequently Asked Questions (FAQ)

### Q: Why does the widget say "Thinking" and hang on OpenCode queries?
**A**: This is usually caused by the local OpenCode server dropping connection mid-stream. Verify that the server is active by navigating to the OpenCode settings tab and clicking **Restart Server**. You can also check the server log: `cat "${XDG_RUNTIME_DIR:-/tmp}/kdeaichat-opencode-$(id -u).log"`.

### Q: I set a theme and it didn't change anything. What should I do?
**A**: Ensure that your Plasma global desktop theme doesn't enforce strict application style sheets that override widget layouts. Go to Settings and change the **Theme Mode** dropdown from "Follow System" to "Strict Dark" or "Strict Light".

### Q: Where are the plain config keys saved?
**A**: Plain keys are saved to `~/.config/kdeaichatrc`. You can open this file directly from the Settings panel using the **Open Config File** button, or reload it with **Reload from Config**.

### Q: The config file was blank when I opened it — why?
**A**: This was a known bug in older versions where KConfig's in-memory cache hadn't been flushed to disk yet. It is fully fixed in v1.2.8 — the widget now writes to disk synchronously before opening the file.

### Q: Do I need an API key for Ollama / LM Studio / Local / LiteLLM?
**A**: No. Ollama, LM Studio, and the Local provider are keyless by default. LiteLLM Proxy is also keyless unless your specific proxy configuration requires authentication.

### Q: How do I export a conversation?
**A**: Click the **Export** button (download icon) in the chat toolbar. You can save as `.md` or `.txt`. The filename is pre-filled automatically.

### Q: How do I report bugs or suggest enhancements?
**A**: KDE AI Chat is open-source! Please visit [https://github.com/racstan/KDE-AI-Chat](https://github.com/racstan/KDE-AI-Chat) to open an issue or fork the project to submit pull requests.

### Q: How do I use the scheduler while the widget is closed?
**A**: The scheduler daemon runs as a systemd user service independent of the widget. Enable it with `systemctl --user enable --now kde-ai-scheduler.service` and it will fire scheduled prompts even when the widget is not open, writing trigger files that the widget picks up the next time it loads.
