# Contributing to KDE AI Chat

Thank you for your interest in contributing to KDE AI Chat! This document outlines the guidelines for contributing to the project.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Code Style & Conventions](#code-style--conventions)
- [Pull Request Process](#pull-request-process)
- [Adding a New AI Provider](#adding-a-new-ai-provider)
- [Adding Translations](#adding-translations)
- [Testing](#testing)
- [Reporting Issues](#reporting-issues)

## Code of Conduct

By participating, you agree to maintain a respectful and inclusive environment for everyone. Harassment, discrimination, or offensive behavior will not be tolerated.

## Getting Started

1. Fork the repository on GitHub.
2. Clone your fork: `git clone https://github.com/your-username/KDE-AI-Chat.git`
3. Create a feature branch: `git checkout -b feature/my-feature`
4. Install the widget locally: `./install.sh`
5. Restart Plasma shell: `systemctl --user restart plasma-plasmashell.service`

## Development Setup

### Prerequisites

- KDE Plasma 6 or later
- Qt 6
- `kpackagetool6` (part of `kpackage`)
- `qmllint` (part of `qt6-declarative`)
- Optional: `poppler-utils`, `pandoc` for file attachment features

### Live Reloading

After editing QML files, reinstall the widget without restarting the entire shell:

```bash
kpackagetool6 --type Plasma/Applet --upgrade ./org.kde.plasma.kdeaichat
```

Then right-click the widget and select **Reload** from the context menu, or restart the shell:

```bash
systemctl --user restart plasma-plasmashell.service
```

### Running the Scheduler Daemon (Optional)

```bash
systemctl --user start kde-ai-scheduler.service
systemctl --user enable kde-ai-scheduler.service
```

## Code Style & Conventions

This project is written primarily in **QML** with embedded **JavaScript**, with a **Python 3** scheduler daemon and **Shell** scripts for installation.

### General Rules

- Follow the existing code style in the file you are editing.
- Use meaningful variable and function names.
- Avoid adding comments unless the logic is non-obvious.
- Keep QML property declarations organized at the top of components.
- Prefer Kirigami components over raw QQC2 where available.

### QML

- Use 4 spaces for indentation.
- Properties and signal declarations go first, then functions, then UI elements.
- Use `readonly property` for computed values.
- Namespace Qt Quick Controls imports as `QQC2`.

### JavaScript

- Use `var` for local variables (QML JS engine limitation).
- Function names use camelCase.
- Errors go to `console.log(...)`.

### Python

- Follow PEP 8.
- Use f-strings for formatting.
- Include module docstrings.

### Shell

- Use `#!/bin/bash` with `set -e`.
- Quote all variable expansions.

## Pull Request Process

1. Ensure your branch is up to date with `main`.
2. Run `qmllint` on any modified QML files and ensure zero warnings and errors.
3. Update or add documentation in `docs/` if your change introduces new features.
4. Update `docs/changelog.md` following the [Keep a Changelog](https://keepachangelog.com/) format.
5. Submit a pull request with a clear title and description of the changes.
6. A maintainer will review your PR. Please address any feedback.

## Adding a New AI Provider

To add a new AI provider to the widget, follow these steps:

1. **Add configuration entries** in `contents/config/main.xml`:
   - Add `<entry>` fields for `baseUrl`, `apiKey`, and `model` using the provider ID as prefix.
   - Provide sensible defaults.

2. **Register in `ProviderData.js`** in `contents/ui/`:
   - Add an entry to the `providerData` array with the provider `id` and display `name`.
   - This file is used by the KWallet helper to discover all provider IDs.

3. **Add config UI bindings** in `contents/ui/ConfigGeneral.qml`:
   - Add `property alias cfg_<provider>BaseUrl`, `cfg_<provider>ApiKey`, `cfg_<provider>Model`.
   - Add the corresponding text fields in the provider settings section.
   - Add the provider to `providerNeedsApiKey()`, `providerEnabled()`, `currentProviderConfig()`, `apiKeyForTarget()`, `applyLoadedKey()`, `applyPlainConfigKeys()`, and `writeKeysToDiskAndOpen()`.

4. **Add API call support** in `contents/ui/main.qml`:
   - Add the provider to the provider switch in `sendMessageByIndex()` or the relevant dispatch function.
   - Handle any provider-specific authentication or headers.
   - Add display name mapping in `providerDisplayName()`.

5. **Add KWallet key target** in `ConfigGeneral.qml`:
   - Add the provider ID to `keyTargetIds()`.

6. **Update documentation**:
   - Add the provider to `docs/SETUP.md` with API key acquisition instructions.
   - Update the provider count and list in `README.md`.

7. **Add to model discovery** in `ConfigGeneral.qml`:
   - If the provider has OpenAI-compatible `/v1/models` endpoint, it works out of the box.
   - For Anthropic-style endpoints, add special handling in `refreshCurrentProviderModels()`.

## Adding Translations

See the [Translation Guide](translation-guide.md) for detailed instructions on adding or updating language translations.

## Testing

### Python Tests

The project has an automated pytest test suite under `tests/` with test cases covering the scheduler and doc extractor:

```bash
# Install pytest if needed
pip install pytest

# Run all tests
pytest tests/ -v

# Run specific test files
pytest tests/test_scheduler.py -v
pytest tests/test_doc_extractor.py -v
```

The CI pipeline runs these automatically on every push/pull request. Python code is also linted with `ruff`:

```bash
pipx run ruff check --select=E9,F --output-format=github org.kde.plasma.kdeaichat/contents/scripts/ org.kde.plasma.kdeaichat/contents/ui/
```

### QML Linting

Run `qmllint` on all QML files to ensure zero warnings and errors:

```bash
qmllint org.kde.plasma.kdeaichat/contents/ui/*.qml
qmllint org.kde.plasma.kdeaichat/contents/config/config.qml
```

### Manual Testing

1. Install the widget: `./install.sh`
2. Restart Plasma shell: `systemctl --user restart plasma-plasmashell.service`
3. Add the widget to your panel/desktop and verify it loads correctly

## Reporting Issues

Report bugs and feature requests on the [GitHub Issues](https://github.com/racstan/KDE-AI-Chat/issues) page. When reporting a bug, include:

- Your Plasma and Qt versions
- Widget version (from `metadata.json`)
- Steps to reproduce
- Expected vs actual behavior
- Relevant error output from `journalctl --user -u plasma-plasmashell`

## Supported Providers (21 total)

| Provider ID | Display Name | API Required |
|:--|:--|:--:|
| `openai` | OpenAI | Yes |
| `anthropic` | Anthropic (Claude) | Yes |
| `groq` | Groq | Yes |
| `deepseek` | DeepSeek | Yes |
| `minimax` | MiniMax | Yes |
| `fireworks` | Fireworks AI | Yes |
| `google` | Google Gemini | Yes |
| `openrouter` | OpenRouter | Yes |
| `mistral` | Mistral | Yes |
| `cloudflare` | Cloudflare Workers AI | Yes |
| `nvidia` | NVIDIA NIM | Yes |
| `huggingface` | Hugging Face | Yes |
| `xai` | xAI (Grok) | Yes |
| `litellm` | LiteLLM Proxy | Optional |
| `qwen` | Qwen | Yes |
| `moonshot` | Moonshot | Yes |
| `mimo` | MiMo | Yes |
| `maritaca` | Maritaca | Yes |
| `lmstudio` | LM Studio | No (local) |
| `local` | Local (OpenAI-compatible) | No (local) |
| `ollama` | Ollama | No (local) |
