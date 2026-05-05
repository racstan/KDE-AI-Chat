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

- **Chat Interface:**
  - Markdown rendering
  - Configurable conversation history
  - Copy to clipboard
  - Provider switching on the fly
  - Customisable system prompt

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
3. Optionally enable CLI bridges and/or the OpenCode beta bridge

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

- API keys are stored using KDE's secure KConfig system
- Keys are masked in the configuration UI
- For shared systems, be cautious with local model endpoints

## Requirements

- KDE Plasma 6
- Qt 6
- Network access for API providers
- CLI tools installed for bridging features

## License

GPL-2.0+

## Contributing

Contributions are welcome! Feel free to submit issues or pull requests.
