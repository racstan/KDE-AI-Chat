# KDE AI Chat - Setup & Usage Guide

A comprehensive guide to setting up and using each feature of the KDE AI Chat KDE Plasma widget.

## Table of Contents
1. [Installation](#installation)
2. [Initial Setup](#initial-setup)
3. [Provider Setup](#provider-setup)
4. [Features & Usage](#features--usage)
5. [Advanced Configuration](#advanced-configuration)
6. [Troubleshooting](#troubleshooting)

---

## Installation

### Prerequisites
- KDE Plasma 6.0+
- Qt 6+
- `notify-send` (for background notifications)
- Optional: `poppler-utils`, `pandoc` for file attachment features

### Install Steps

#### Option A: Native 1-Click Desktop Installation (Recommended)
1. Right-click your desktop background or the panel and click **Add Widgets...**
2. Click **Get New Widgets** -> **Download New Plasma Widgets...**
3. In the search box, search for **"KDE AI Chat"**.
4. Click **Install**.

#### Option B: Manual Package Installation
If you downloaded the compiled `.plasmoid` file directly from the KDE Store:
1. Open a terminal in the folder containing the downloaded `.plasmoid` package.
2. Run the package registration command:
   ```bash
   kpackagetool6 --type Plasma/Applet --install org.kde.plasma.kdeaichat-v1.3.plasmoid
   ```
3. Restart your Plasma shell to apply the update:
   ```bash
   systemctl --user restart plasma-plasmashell.service
   ```

4. **Verify installation:**
   - Right-click your panel/desktop, select **Add Widgets...**, search for **"KDE AI Chat"**, and drag it onto your panel or desktop.
   - Click the chat icon (💬) to open the popup.
   - Navigate to the **Settings** view (click the gear icon) to configure your first provider.

#### Option C: Source Installation
```bash
git clone https://github.com/racstan/KDE-AI-Chat.git
cd KDE-AI-Chat
./install.sh
systemctl --user restart plasma-plasmashell.service
```

---

## Initial Setup

### Access Settings

1. **Open the KDE AI Chat widget** by clicking its panel icon
2. **Click the gear icon** in the top-right corner to open Settings
3. You'll see tabs for **General**, **Appearance**, and **Shortcuts**

### Configure Your First Provider

All 21 providers follow the same pattern:

1. **Select a Provider** from the dropdown in the **General** tab.

2. **Obtain Your API Key:**
   - See [Provider Setup](#provider-setup) for provider-specific instructions

3. **Enter the API Key:**
   - Paste your API key in the **API Key** field
   - Choose your preferred storage mode (Session Only, Plain Config, or KWallet)
   - Click **Test Connection** to verify

4. **Configure API Endpoint (optional):**
   - Most providers use the default endpoint
   - For custom/self-hosted models, enter a different URL (e.g., `http://localhost:8000`)

5. **Select a Model:**
   - After setting the API key, click **Fetch Available Models**
   - Select your preferred model from the dropdown

---

## Provider Setup

Follow the steps below for each provider you want to use.

### OpenAI

1. **Get API Key:**
   - Visit https://platform.openai.com/api-keys
   - Sign in or create an account
   - Click **+ Create new secret key**
   - Copy and paste into KDE AI Chat settings

2. **Model Selection:**
   - Click **Fetch Available Models** in settings
   - Select `gpt-4o`, `gpt-4o-mini`, `gpt-4-turbo`, or similar

3. **Endpoint:**
   - Default: `https://api.openai.com/v1`

---

### Anthropic (Claude)

1. **Get API Key:**
   - Visit https://console.anthropic.com/
   - Navigate to **Account → API Keys**
   - Create a new key, copy it

2. **Model Selection:**
   - Common models: `claude-opus-4-5`, `claude-sonnet-4-5`, `claude-haiku-4-5`
   - Click **Fetch Available Models** to see all

3. **Endpoint:**
   - Default: `https://api.anthropic.com`

---

### Google Gemini

1. **Get API Key:**
   - Visit https://aistudio.google.com/app/apikey
   - Click **Create API Key**
   - Copy the key

2. **Model Selection:**
   - Common: `gemini-2.0-flash`, `gemini-1.5-pro`, `gemini-1.5-flash`
   - Use **Fetch Available Models** to see current options

3. **Endpoint:**
   - Default: `https://generativelanguage.googleapis.com/v1beta/openai/`

---

### Mistral AI

1. **Get API Key:**
   - Visit https://console.mistral.ai/api-keys/
   - Sign in, create a new API key

2. **Model Selection:**
   - Popular: `mistral-large-latest`, `mistral-medium-latest`, `mistral-small-latest`
   - Fetch available models in settings

3. **Endpoint:**
   - Default: `https://api.mistral.ai/v1`

---

### Grok (X.AI)

1. **Get API Key:**
   - Visit https://console.x.ai/
   - Navigate to **API Keys** section
   - Create and copy your key

2. **Model Selection:**
   - Default: `grok-3`, `grok-3-mini`, `grok-2-vision-1212`
   - Fetch to see latest options

3. **Endpoint:**
   - Default: `https://api.x.ai/v1`

---

### DeepSeek

1. **Get API Key:**
   - Visit https://platform.deepseek.com/api_keys
   - Create a new key

2. **Model Selection:**
   - Popular: `deepseek-chat`, `deepseek-reasoner`

3. **Endpoint:**
   - Default: `https://api.deepseek.com`

---

### NVIDIA NIM

1. **Get API Key:**
   - Visit https://build.nvidia.com/
   - Create a free account
   - Generate an API key

2. **Model Selection:**
   - Access NVIDIA's hosted models (Llama 3, Nemotron, etc.)

3. **Endpoint:**
   - Default: `https://integrate.api.nvidia.com/v1`

---

### Cloudflare Workers AI

1. **Get API Key:**
   - Visit https://dash.cloudflare.com/
   - Navigate to **AI** section
   - Create API token

2. **Model Selection:**
   - Access Cloudflare's model catalog via Fetch Models

3. **Endpoint:**
   - Default: `https://api.cloudflare.com/client/v4/accounts/{account-id}/ai/run/`

---

### Hugging Face

1. **Get API Key:**
   - Visit https://huggingface.co/settings/tokens
   - Create a **User Access Token**

2. **Model Selection:**
   - Popular: `mistralai/Mistral-7B-Instruct-v0.3`, `meta-llama/Meta-Llama-3-8B-Instruct`
   - Use the Inference API endpoint

3. **Endpoint:**
   - Default: `https://router.huggingface.co/v1`

---

### OpenRouter

1. **Get API Key:**
   - Visit https://openrouter.ai/keys
   - Create an API key

2. **Model Selection:**
   - Access 300+ models from different providers
   - Popular: `openai/gpt-4o`, `anthropic/claude-opus-4-5`, etc.

3. **Endpoint:**
   - Default: `https://openrouter.ai/api/v1`

---

### LiteLLM Proxy

1. **Install LiteLLM:**
   - `pip install litellm`
   - Or use the [LiteLLM Proxy docs](https://docs.litellm.ai/docs/proxy/quick_start) for a full config-file-based setup

2. **Start the proxy:**
   ```bash
   litellm --model gpt-4o-mini
   # or with a config file:
   litellm --config /path/to/config.yaml
   ```

3. **Configure the widget:**
   - Select **LiteLLM Proxy** from the provider dropdown
   - Set endpoint to `http://localhost:4000/v1` (default)
   - API key is **optional** — leave blank for keyless proxy setups
   - Click **Refresh Models** to discover available models

4. **Endpoint:**
   - Default: `http://localhost:4000/v1`

---

### Local Models (Ollama / LM Studio / vLLM)

1. **Setup Requirements:**
   - Run a local LLM server (Ollama, LM Studio, vLLM, etc.)
   - Ensure it's accessible on localhost

2. **Ollama:**
   - Install: https://ollama.com
   - Run: `ollama serve`
   - Set `OLLAMA_ORIGINS="*"` to allow QML network access
   - Endpoint: `http://localhost:11434/v1`

3. **LM Studio:**
   - Download: https://lmstudio.ai
   - Load a model and start its local server
   - Endpoint: `http://localhost:1234/v1`

4. **API Key:**
   - Local providers (Ollama, LM Studio, Local OpenAI-compatible) are **keyless** — no API key required.

---

## Features & Usage

### 1. Basic Chat

**How to use:**
1. Type your message in the input field at the bottom
2. Press **Enter** to send (or click **Send**)
3. The AI response appears in the chat above

**Tips:**
- Press **Shift+Enter** to create a new line without sending
- Use markdown in your messages (it's supported)
- The chat supports **markdown rendering** for responses (bold, links, code blocks, etc.)

---

### 2. Streaming Responses

**What it does:**
- Responses appear **token-by-token** in real-time instead of waiting for the full response
- The widget shows a **pulsing animation** while streaming

**How to use:**
- Just send a message normally; streaming happens automatically
- Click **Stop** button to interrupt the response mid-stream
- The response is saved to conversation history after completion

**Provider Support:**
- All 21 providers support streaming

---

### 3. Conversation Sessions

**What it does:**
- Chat sessions are persisted through KConfigXT and optionally to a custom history path
- Sessions persist after the widget closes or Plasma restarts

**How to use:**
1. **View Sessions:** Look for the **Sessions menu** in the top-left of the chat (folder icon or label)
2. **Create New Session:** Click **New Chat** button (or use the menu)
3. **Load Previous Session:** Click a session name from the sessions list
4. **Rename Session:** Click the edit pencil icon next to a session name
5. **Archive Session:** Move older conversations off the active list without deleting
6. **Delete Session:** Click the trashcan icon

---

### 4. File Attachments

**What it does:**
- Attach files, images, or clipboard content directly to your messages
- Extracted text is injected into the prompt sent to the AI

**Supported formats:**
- PDF (requires `pdftotext`)
- Word documents (requires `pandoc`)
- Images (base64 encoded for vision models)
- Plain text, CSV, JSON, XML, YAML, JS, TS, PY, SH, HTML, CSS

**How to use:**
1. **Drag and drop** a file onto the chat input area, or
2. **Paste** from clipboard — the widget auto-detects file URIs, images, or text

---

### 5. Response Actions

**Copy Response:**
- Click **Copy** button on any assistant message
- Full response is copied to clipboard

**Regenerate Response:**
- Click **Regenerate** button
- Resends the last user message and gets a fresh AI response

**Edit Message:**
- Click the **Edit** (pencil) button on any user message
- Edits truncate all subsequent messages and re-send from that point (conversation forking)

**Copy Code Block:**
- For responses with multiple code blocks, there are individual **Copy code N** buttons
- Click to copy specific code block to clipboard

---

### 6. Chat Export

**How to export:**
1. Click the **Export** button (download icon) in the chat toolbar
2. Choose your format: **Markdown (`.md`)** or **Plain Text (`.txt`)**
3. The save dialog opens pre-filled with a filename: `<chat_title>_<timestamp>.<ext>`
4. Choose a location and save

---

### 7. Scheduled Prompts

**What it does:**
- Automate AI prompts at specific times or intervals using the built-in scheduler
- Runs via a systemd user service — works even when the widget is closed

**How to set up:**
1. Ensure the scheduler daemon is running: `systemctl --user start kde-ai-scheduler.service`
2. Click the **Schedule** button (clock icon) or type `/schedule` in chat
3. Click **New Schedule** and configure the name, message, timing, and target session
4. Click **Save**

See [scheduler-usage.md](scheduler-usage.md) for full scheduler documentation.

---

### 8. OpenCode Developer Bridge

**What it does:**
- Routes chat through a local [OpenCode](https://opencode.ai/) server for AI-powered development tasks
- Supports tool invocation, file operations, bash execution, and interactive prompts

**How to enable:**
1. Install OpenCode: https://opencode.ai/
2. Open Settings → **OpenCode** tab → toggle **OpenCode Mode** on
3. Set the server URL (default: `http://127.0.0.1:4096/v1`)
4. Click **Start OpenCode Server** or enable auto-start

See [opencode-bridge.md](opencode-bridge.md) for full bridge documentation.

---

### 9. KWallet / API Key Storage

**What it does:**
- API keys can be stored using **KDE Wallet (KWallet)** via DBus, in a **plain config file**, or kept **session-only** in memory.

**How to use:**
1. Open Settings → find the **API Key Storage** mode selector.
2. Choose: **Session Only**, **Plain Config**, or **Secure KWallet**.
3. In **Plain Config** mode, use **Open Config File** to edit `~/.config/kdeaichatrc` directly.
4. In **KWallet** mode, use **Launch KWallet Manager** to inspect stored credentials.

**Manual KWallet inspection:**
```bash
# Open KWallet Manager from terminal
kwalletmanager5

# Or query keys via DBus
qdbus6 org.kde.kwalletd6 /modules/kwalletd6 org.kde.KWallet.wallets
```

---

### 10. Background Notifications

**What it does:**
- When a response completes, a desktop notification is sent (if enabled)
- You don't need to keep the widget open to see it

**How to enable:**
1. Open Settings → **General** tab
2. Enable **"Send desktop notifications for background completions"**
3. Notifications will appear in your system notification panel

---

## Advanced Configuration

### Custom API Endpoints

**Why:**
- Use a proxy, VPN, or self-hosted service
- Route requests through a custom gateway

**How:**
1. Go to Settings → **General**
2. In the **API Endpoint** field, enter your custom URL
3. Example: `http://localhost:8000/v1`
4. Click **Test Connection** to verify

---

### Custom History Path

**Why:**
- Store conversation history in a synced folder (e.g., Nextcloud, Syncthing)
- Keep history outside of KConfigXT for easier backup

**How:**
1. Go to Settings → **General**
2. Set the **Custom History Path** field to your preferred directory
3. The widget will read and write session JSON files from that path

---

### Theme Customization

**What it does:**
- Widget colors and spacing automatically match your KDE Plasma theme

**How to change:**
1. Go to **System Settings** → **Appearance** → **Colors** or **Application Style**
2. Choose your theme
3. KDE AI Chat will automatically update colors/spacing

**Manual theme override:**
- Go to Settings → **Appearance** tab
- Set **Theme Mode** to **Strict Dark** or **Strict Light** to ignore system theme

---

## Troubleshooting

### "Provider configuration is missing"
**Problem:** Settings show a warning about missing configuration.

**Solution:**
1. Open Settings (gear icon)
2. Select a provider from the dropdown
3. Enter API Key and click **Test Connection**
4. Refresh the widget

---

### API Key Not Working
**Problem:** "Test Connection" fails or responses show auth errors.

**Solution:**
1. Verify the API key is correct (copy/paste from provider website)
2. Ensure the **Provider** dropdown matches your API key source
3. Check if the API key has expired or been revoked (regenerate if needed)
4. For paid services, ensure you have active credits/billing

---

### Streaming Not Working
**Problem:** Responses arrive all at once instead of token-by-token.

**Solution:**
1. This is normal for some providers (e.g., if the provider doesn't support streaming)
2. Check that streaming is enabled in the provider's settings
3. Try switching providers to verify feature works

---

### KWallet Errors
**Problem:** "Could not retrieve API key from KWallet" or keys not loading on startup.

**Solution:**
1. Ensure `kwalletd6` is running:
   ```bash
   systemctl --user status plasma-kwalletd.service
   # or start it:
   systemctl --user start plasma-kwalletd.service
   ```

2. Open KWallet Manager and check that the `KaiChat` folder exists and contains your keys:
   ```bash
   kwalletmanager5
   ```

3. If KWallet is not available on your system (e.g., headless server), switch to **Plain Config** mode in the widget Settings instead.

4. Re-enter your API key in Settings — it will be stored to whichever mode is currently selected.

---

### Scheduler Not Triggering
**Problem:** Scheduled prompts are not firing.

**Solution:**
1. Check daemon status: `systemctl --user status kde-ai-scheduler.service`
2. Check logs: `journalctl --user -u kde-ai-scheduler.service`
3. Ensure **Scheduler Enabled** is toggled on in Settings
4. Ensure the schedule's target session exists

---

### High CPU Usage
**Problem:** Widget is using too much CPU (especially during streaming).

**Solution:**
1. Disable background notifications (Settings → **General** → uncheck notification toggle)
2. Close Settings while not configuring
3. Reduce number of conversation sessions (archive or delete old ones)
4. Restart the widget if it seems stuck

---

## Support & Feedback

- **GitHub Issues:** https://github.com/racstan/KDE-AI-Chat/issues
- **Feature Requests:** Open an issue with the `feature` label
- **Bug Reports:** Include widget version and error messages

---

## License

KDE AI Chat is licensed under GPL-2.0+. See `metadata.json` for details.
