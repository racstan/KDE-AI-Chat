# KDE AI Chat — Native Plasma 6 AI Companion User Manual

Welcome to **KDE AI Chat**, a native, premium, and highly responsive AI companion built specifically for **KDE Plasma 6** and **Qt 6**. 

This manual provides an in-depth operations guide, walkthroughs of every feature, advanced workflows, and troubleshooting FAQs to ensure you get the absolute most out of your desktop assistant.

---

## 📖 Table of Contents
1. [Getting Started & Installation](#1-getting-started--installation)
2. [Configuring Providers & API Keys](#2-configuring-providers--api-keys)
3. [Secure Storage: KWallet vs. Plain Configs](#3-secure-storage-kwallet-vs-plain-configs)
4. [Running Offline Local LLMs (Ollama & LM Studio)](#4-running-offline-local-llms-ollama--lm-studio)
5. [OpenCode Developer Bridge Guide](#5-opencode-developer-bridge-guide)
6. [Managing Conversations & Chat History](#6-managing-conversations--chat-history)
7. [Frequently Asked Questions (FAQ)](#7-frequently-asked-questions-faq)

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

KDE AI Chat supports a total of **16 different AI engines** out of the box. Key setups are handled directly inside the Widget's **Settings** panel (right-click widget -> *Configure KDE AI Chat...*).

### Supported API Providers
| Provider | Default URL / Endpoint | Credentials Needed |
| :--- | :--- | :--- |
| **OpenAI** | `https://api.openai.com/v1` | OpenAI API Key |
| **Anthropic (Claude)** | `https://api.anthropic.com/v1` | Anthropic API Key |
| **DeepSeek** | `https://api.deepseek.com/v1` | DeepSeek API Key |
| **Google Gemini** | `https://generativelanguage.googleapis.com` | Google AI Studio Key |
| **Groq** | `https://api.groq.com/openai/v1` | Groq API Key |
| **OpenRouter** | `https://openrouter.ai/api/v1` | OpenRouter API Key |
| **xAI (Grok)** | `https://api.x.ai/v1` | xAI API Key |
| **Mistral** | `https://api.mistral.ai/v1` | Mistral API Key |
| **NVIDIA NIM** | `https://integrate.api.nvidia.com/v1` | NVIDIA Developer Key |
| **Hugging Face** | `https://api-inference.huggingface.co` | HF User Token |
| **Cloudflare Workers AI** | `https://api.cloudflare.com/client/v4` | CF API Token + Account ID |
| **LM Studio** | `http://localhost:1234/v1` | Keyless / Offline |
| **Ollama** | `http://localhost:11434/v1` | Keyless / Offline |
| **OpenCode** | `http://localhost:1337` | Local Developer Bridge |

---

## 3. Secure Storage: KWallet vs. Plain Configs

By default, KDE AI Chat integrates with the desktop's native secure password storage, **KWallet**, via DBus to protect your private API keys.

### Dynamic Checkbox Switch
Inside the **Settings** panel, you will find a checkbox labeled **"Use KWallet Secure Storage"**:

* **Checkbox Enabled (KWallet Mode)**:
  - Your API keys are encrypted and stored inside your system's secure wallet.
  - When the widget starts, it securely requests keys off-thread, preventing unauthorized plaintext exposures.
  - Recommended for general desktop setups.
  
* **Checkbox Disabled (Direct Config Mode)**:
  - Disables secure KWallet interactions entirely.
  - Keys are stored inside standard, human-readable local config files (`~/.config/kaichatrc` / `~/.config/kdeaichatrc`).
  - Perfect for manual editing, quick backups, or on headless systems where wallet services are inactive.

---

## 4. Running Offline Local LLMs (Ollama & LM Studio)

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

---

## 5. OpenCode Developer Bridge Guide

**OpenCode** is a local development server that turns AI chat into an interactive code-writing session. The widget includes a specialized bridge to manage and run OpenCode directly.

### Running OpenCode from the Widget
1. **Toggle Mode**: In the bottom bar of the main chat, toggle the **OpenCode** selector. Once activated, OpenCode becomes your default conversation engine.
2. **Start the Server**: Open Settings, navigate to the **OpenCode** tab, and click **Start OpenCode Server**.
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

---

## 7. Frequently Asked Questions (FAQ)

### Q: Why does the widget say "Thinking" and hang on OpenCode queries?
**A**: This is usually caused by the local OpenCode server dropping connection mid-stream. We have audited the pipeline to ensure that network errors now trigger explicit failure logs instead of freezing the UI. To fix, verify that the server is active by navigating to the OpenCode settings tab and clicking **Restart Server**.

### Q: I set a theme and it didn't change anything. What should I do?
**A**: Ensure that your Plasma global desktop theme doesn't enforce strict application style sheets that override widget layouts. If you want the widget to ignore system-wide rules, go to settings and change the **Theme Mode** dropdown from "Follow System" to "Strict Dark" or "Strict Light".

### Q: Where are the plain config keys saved when KWallet is turned off?
**A**: Plain keys are saved inside standard KDE configuration pathways. On most Linux distributions, this is located at `~/.config/kaichatrc`.

### Q: How do I report bugs or suggest enhancements?
**A**: KDE AI Chat is open-source! We welcome the community to collaborate, play, and contribute. Please visit our homepage at [https://github.com/racstan/KDE-AI-Chat](https://github.com/racstan/KDE-AI-Chat) to open an issue or fork the project to submit pull requests.
