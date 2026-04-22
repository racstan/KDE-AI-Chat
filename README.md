# AI Chat - KDE Plasma Widget

A KDE Plasma 6 widget that provides AI chat capabilities with support for multiple providers (OpenAI, Anthropic, Local models) and bridges to coding CLI tools like Opencode, Aider, and Claude Code.

## Features

- **Multiple AI Providers:**
  - OpenAI (GPT-4, GPT-4o, GPT-4o-mini, etc.)
  - Anthropic Claude (Claude 3.5 Sonnet, etc.)
  - Local models via OpenAI-compatible endpoints (Ollama, LM Studio, llama.cpp, text-generation-webui)

- **CLI Bridges:**
  - **Opencode** - Send AI responses directly to the Opencode CLI
  - **Aider** - Bridge to Aider coding assistant
  - **Claude Code** - Bridge to Claude Code CLI

- **Chat Interface:**
  - Markdown rendering support
  - Conversation history (configurable limit)
  - Copy to clipboard functionality
  - Provider switching on-the-fly
  - System prompt customization

## Installation

### From Source

1. Clone or download this repository
2. Install the widget:

```bash
kpackagetool6 --install org.kde.plasma.aichat --global
```

Or for user-local installation:

```bash
kpackagetool6 --install org.kde.plasma.aichat
```

### Upgrade

```bash
kpackagetool6 --upgrade org.kde.plasma.aichat --global
```

## Usage

### Adding to Desktop/Panel

1. Right-click on your desktop or panel
2. Select "Add Widgets..."
3. Search for "AI Chat"
4. Drag it to your desired location

### Configuration

1. Right-click the widget and select "Configure AI Chat..."
2. Choose your AI provider and enter the required settings:
   - **OpenAI**: API key and optional custom base URL
   - **Anthropic**: API key
   - **Local**: Base URL of your local server (e.g., `http://localhost:11434/v1` for Ollama)

3. Enable and configure CLI bridges as needed
4. Customize the system prompt to tailor AI behavior

### CLI Bridge Setup

Make sure the respective CLI tools are installed and available in your PATH:

- **Opencode**: `npm install -g opencode` or see [Opencode docs](https://github.com/opencode-ai/opencode)
- **Aider**: `pip install aider-chat` or see [Aider docs](https://aider.chat/)
- **Claude Code**: See [Anthropic's Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview)

### Local Model Setup (Ollama Example)

1. Install Ollama: https://ollama.com/
2. Pull a model: `ollama pull llama3.2`
3. Start Ollama server: `ollama serve`
4. In widget settings, select "Local" provider
5. Set Base URL to: `http://localhost:11434/v1`
6. Set Model to: `llama3.2`

## File Structure

```
org.kde.plasma.aichat/
├── metadata.json                 # Widget metadata
├── contents/
│   ├── config/
│   │   └── main.xml             # Configuration schema
│   └── ui/
│       ├── main.qml             # Main chat interface
│       ├── ConfigGeneral.qml    # Settings UI
│       └── apiWorker.mjs        # API communication worker
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
