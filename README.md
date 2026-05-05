# Kai Chat – KDE Plasma Widget

A KDE Plasma 6 widget that provides AI chat through 13 built-in providers and an experimental OpenCode Bridge, plus CLI bridges to Opencode, Aider, and Claude Code.

## Features

- **13 Built-in AI Providers:**
  - OpenAI (GPT-4o, GPT-4.1, o3, o4-mini, etc.)
  - Anthropic Claude (claude-sonnet-4-5, claude-3-7, etc.)
  - Google Gemini (gemini-2.0-flash, gemini-2.5-pro, etc.)
  - Mistral AI (mistral-large, codestral, etc.)
  - xAI Grok (grok-3, grok-3-mini, etc.)
  - DeepSeek (deepseek-chat, deepseek-reasoner)
  - NVIDIA NIMs (llama, mistral, and more via NVIDIA's inference platform)
  - Cerebras (llama3.1, qwen-3, etc. — ultra-fast inference)
  - Cloudflare Workers AI (llama, gemma, qwq, etc.)
  - HuggingFace Inference API (serverless, OpenAI-compatible)
  - OpenRouter (400+ models via one API key)
  - LiteLLM proxy (local OpenAI-compatible proxy for any model)
  - Local models (Ollama, LM Studio, llama.cpp, text-generation-webui)

- **[BETA] OpenCode Bridge:**
  - Kai Chat talks to your locally-running OpenCode server as the AI backend
  - OpenCode manages model selection and provider credentials — no API key setup needed in the widget
  - Session persistence across restarts; "new session" button in the chat header
  - Start with: `opencode serve`

- **CLI Bridges (forward AI responses → coding tools):**
  - **Opencode** – `opencode -p "…"`
  - **Aider** – `aider --message "…"`
  - **Claude Code** – `claude -p "…"`

- **Streaming Chat UI:**
  - Token streaming over SSE for OpenAI-compatible providers
  - Stop button to abort generation while keeping partial output
  - Per-message timestamps and regenerate support
  - Auto-scroll unless user manually scrolls up

- **Compact ↔ Full Representation:**
  - Compact panel icon with state dot (idle, streaming, success, error)
  - Pulsing animation while streaming
  - Tooltip preview of last assistant response

- **Conversation Sessions on Disk:**
  - Stored as JSON under `~/.local/share/plasmoids/org.kde.plasma.kaichat/conversations/`
  - New chat/session switcher in the header
  - Auto-title from first user message

- **Global Shortcut Ready:**
  - Implements `activate()` to open widget and focus input field
  - Shortcut assignment available from Plasma widget Shortcuts tab

- **Clipboard / Selection Inject:**
  - Paste clipboard or primary selection text into prompt
  - Large pasted text is attached as a chip instead of flooding the input box

- **Response Actions:**
  - Copy full response
  - Copy each detected markdown code block separately
  - Regenerate last response
  - Delete assistant message

- **Theme Compliance:**
  - Uses `Kirigami.Theme.*` colors and `Kirigami.Units.*` spacing
  - Popup uses Plasma dialog background (`dialogs/background`) for native appearance

- **Secure Keyring Integration (Secret Service/KWallet backend):**
  - Active provider key can be stored via `secret-tool`
  - Runtime key lookup from Secret Service when config key is empty
  - Plain-text config key is cleared after secure store (settings action)

- **Background Completion Notifications:**
  - Optional desktop notification when response completes while widget is collapsed
  - Configurable via settings toggle

## Installation

### From Source

```bash
kpackagetool6 --install org.kde.plasma.kaichat --global
```

Or user-local:

```bash
kpackagetool6 --install org.kde.plasma.kaichat
```

Or use the helper script:

```bash
bash install.sh          # user-local
bash install.sh global   # system-wide (needs sudo)
```

### Upgrade

```bash
kpackagetool6 --upgrade org.kde.plasma.kaichat --global
```

## Usage

### Adding to Desktop/Panel

1. Right-click your desktop or panel
2. Select **Add Widgets…**
3. Search for **Kai Chat**
4. Drag it to your desired location

### Configuration

1. Right-click the widget → **Configure Kai Chat…**
2. Choose a provider and enter the required credentials
3. Optionally enable CLI bridges, Secret Service key storage, notifications, and/or the OpenCode beta bridge

### Sessions

- Use the session dropdown in the chat header to switch conversations
- Use the **+** button to create a new conversation JSON file

### OpenCode Bridge (Beta)

```bash
# Start OpenCode in server mode (exposes HTTP API on port 4096)
opencode serve

# Then in Kai Chat Settings → Provider → [BETA] OpenCode Bridge
```

The widget creates a session on your first message and reuses it for context.  
Use the **+** button in the chat header to start a fresh session.

### Local Model Setup (Ollama Example)

```bash
ollama pull llama3.2
ollama serve
# Base URL: http://localhost:11434/v1   Model: llama3.2
```

## File Structure

```
org.kde.plasma.kaichat/
├── metadata.json                 # Widget metadata (ID: org.kde.plasma.kaichat)
├── contents/
│   ├── config/
│   │   └── main.xml             # KConfigXT configuration schema (all providers)
│   └── ui/
│       ├── main.qml             # Main chat interface + panel icon
│       ├── ConfigGeneral.qml    # Settings UI (all 13 providers + OpenCode bridge)
│       └── apiWorker.mjs        # Background API worker (WorkerScript)
```

## Security Notes

- API keys entered directly in provider fields are plain-text KConfig values.
- Use **Secret Service (KWallet backend)** controls in settings to move keys into keyring storage.
- Kai Chat can look up provider keys at runtime via `secret-tool lookup`.
- For shared systems, prefer keyring storage and local model endpoints.

## Requirements

- KDE Plasma 6
- Qt 6
- Network access for API providers
- CLI tools installed for bridging features
- `xclip` (X11) or `wl-clipboard` (Wayland) for clipboard/selection inject
- `libsecret` / `secret-tool` for keyring-backed key storage
- `notify-send` for background completion notifications

## License

GPL-2.0+

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests.
