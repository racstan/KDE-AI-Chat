# Changelog

All notable changes to the **KDE AI Chat** project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-05-21

### Added
- **Ollama Provider Integration**: Out-of-the-box keyless support for local Ollama instances, pre-configured to point to `http://localhost:11434/v1` and defaulting to `llama3.2`.
- **Optional KWallet Support**: Toggle Secure KWallet credentials storage via a simple checkbox in settings. Disabling it saves API keys directly inside plain local configuration files for easier manual setups.
- **Provider Static-Analysis Suite**: Added a Python automation checker (`validate_providers.py`) to systematically audit and verify alignment of all 16 providers across system schemas, UI settings, and execution engines.
- **Full Offline Local LLM Support**: Keyless setup integration for local/offline engines (Ollama, LM Studio, or custom local OpenAI-compatible endpoints) without requiring dummy API keys.

### Fixed
- **Dynamic Theme apply bug**: Added strict `Kirigami.Theme` overrides and matching solid layouts in representations to honor Light and Dark appearance mode selections.
- **Repository Rename**: Updated all links, descriptors, metadata files, and git configuration to point to the new home: `https://github.com/racstan/KDE-AI-Chat`.

---

## [1.0.0] - 2026-05-20

### Added
- **Initial Release of KDE AI Chat** for KDE Plasma 6 & Qt 6.
- **13 API Providers**: Multi-provider support (OpenAI, Anthropic Claude, Groq, DeepSeek, Google Gemini, OpenRouter, Mistral, Cloudflare Workers AI, NVIDIA, Hugging Face, xAI, LM Studio, local OpenAI-compatible).
- **Session History Persistence**: Elegant native calendar-grouped history panel.
- **Smart Model Search**: Real-time searchable dropdown box for model switching.
- **Native Canvas Scaling**: Drag-to-resize panel support.
