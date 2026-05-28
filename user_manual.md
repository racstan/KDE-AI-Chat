# KDE AI Chat — Native Plasma 6 AI Companion User Manual

Welcome to **KDE AI Chat**, a native, premium, and highly responsive AI companion built specifically for **KDE Plasma 6** and **Qt 6**. 

This manual provides an in-depth operations guide, walkthroughs of every feature, advanced workflows, and troubleshooting FAQs to ensure you get the absolute most out of your desktop assistant.

---

## 📖 Table of Contents
1. [Getting Started & Installation](#1-getting-started--installation)
2. [Configuring Providers & API Keys](#2-configuring-providers--api-keys)
3. [Secure Storage: KWallet vs. Plain Configs](#3-secure-storage-kwallet-vs-plain-configs)
4. [Running Offline Local LLMs (Ollama, LM Studio & LiteLLM)](#4-running-offline-local-llms-ollama-lm-studio--litellm)
5. [OpenCode Developer Bridge Guide](#5-opencode-developer-bridge-guide)
6. [Managing Conversations & Chat History](#6-managing-conversations--chat-history)
7. [Chat Export](#7-chat-export)
8. [Frequently Asked Questions (FAQ)](#8-frequently-asked-questions-faq)

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

KDE AI Chat supports **17 different AI engines** out of the box. Key setups are handled directly inside the Widget's **Settings** panel (right-click widget → *Configure KDE AI Chat...*).

### Supported API Providers

| Provider | Default URL / Endpoint | Credentials Needed |
| :--- | :--- | :--- |
| **OpenAI** | `https://api.openai.com/v1` | OpenAI API Key |
| **Anthropic (Claude)** | `https://api.anthropic.com/v1` | Anthropic API Key |
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
1. **Ensure Ollama is Running**: Boot your local daemon.
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
   - Click **Refresh Models**. The dropdown will dynamically discover and fetch all model weights currently downloaded on your machine (e.g., `llama3.2`, `mistral`, etc.).

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

**[OpenCode](https://opencode.ai/)** ([GitHub: sst/opencode](https://github.com/sst/opencode)) is a local AI development agent that turns your chat session into an interactive code-writing and execution environment. The widget includes a specialized bridge to manage and run OpenCode directly.

### Running OpenCode from the Widget
1. **Toggle Mode**: In the bottom bar of the main chat, toggle the **OpenCode** selector. Once activated, OpenCode becomes your default conversation engine.
2. **Start the Server**: Open Settings, navigate to the **OpenCode** tab, and click **Start OpenCode Server** (or use the configured start command).
3. **Connect**: Click **Refresh** in the widget header to discover the active connection. Select your preferred backing LLM provider and models.
4. **Session Tracking**: Once connected, the widget header displays the unique **Active OpenCode Session ID** in real-time.

### Interactive Security & Input Prompt Cards
OpenCode will occasionally require verification or clarification to run tools or process code. 

- **Clarification Prompt Cards**: When OpenCode asks a question, an interactive card with a focus border renders inline in the chat bubble list.
- **Actions**:
  - Type your response into the card's native text box and click **Submit** to feed the answer directly to the compiler.
  - Click **Dismiss** to reject the query.
  - The card dynamically preserves your actions, showing a success tick ✅ or rejection cross ❌ directly in the conversation history.

---

## 6. Managing Conversations & Chat History

Conversation threads are tracked in the persistent sidebar.

* **Renaming Threads**: Click the edit pencil icon next to any thread in the history panel to enter a custom title.
* **Archiving Threads**: Move older conversations into a safe secondary filter list to keep your sidebar active and uncluttered.
* **Deleting Threads**: Click the trashcan icon to delete the thread and remove its database cache from the disk.
* **Visual Identifiers**: OpenCode chats are rendered with distinct system badges to instantly separate development workspaces from standard AI conversations.
* **Branching**: Edit any older user message to automatically delete all subsequent messages and start a fresh branch from that point.

---

## 7. Chat Export

Export any conversation to a file directly from the chat toolbar.

### How to Export
1. Click the **Export** button (download icon) in the chat toolbar.
2. Choose your format: **Markdown (`.md`)** or **Plain Text (`.txt`)**.
3. The save dialog opens pre-filled with a filename: `<chat_title>_<timestamp>.<ext>`.
4. Choose a location and save.

### Export Format
- **Header**: Includes the chat title and export timestamp.
- **Messages**: Each message shows the role label (User / Assistant / System Error) and time.
- **Layout**: User messages are right-aligned; AI and system messages are left-aligned — matching the live chat UI.
- **Encoding**: Full UTF-8, safe for all languages and special characters.

---

## 8. Frequently Asked Questions (FAQ)

### Q: Why does the widget say "Thinking" and hang on OpenCode queries?
**A**: This is usually caused by the local OpenCode server dropping connection mid-stream. We have audited the pipeline to ensure that network errors now trigger explicit failure logs instead of freezing the UI. To fix, verify that the server is active by navigating to the OpenCode settings tab and clicking **Restart Server**.

### Q: I set a theme and it didn't change anything. What should I do?
**A**: Ensure that your Plasma global desktop theme doesn't enforce strict application style sheets that override widget layouts. If you want the widget to ignore system-wide rules, go to Settings and change the **Theme Mode** dropdown from "Follow System" to "Strict Dark" or "Strict Light".

### Q: Where are the plain config keys saved?
**A**: Plain keys are saved to `~/.config/kdeaichatrc`. You can open this file directly from the Settings panel using the **Open Config File** button, or reload it with **Reload from Config**.

### Q: The config file was blank when I opened it — why?
**A**: This was a known bug in older versions where KConfig's in-memory cache hadn't been flushed to disk yet. It is fully fixed in v1.2.8 — the widget now writes to disk synchronously before opening the file.

### Q: Do I need an API key for Ollama / LM Studio / LiteLLM?
**A**: No. Ollama, LM Studio, and the local provider are keyless by default. LiteLLM Proxy is also keyless unless your specific proxy configuration requires authentication.

### Q: How do I export a conversation?
**A**: Click the **Export** button (download icon) in the chat toolbar. You can save as `.md` or `.txt`. The filename is pre-filled automatically.

### Q: How do I report bugs or suggest enhancements?
**A**: KDE AI Chat is open-source! Please visit [https://github.com/racstan/KDE-AI-Chat](https://github.com/racstan/KDE-AI-Chat) to open an issue or fork the project to submit pull requests.
