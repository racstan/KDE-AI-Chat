# KDE AI Chat — Native KDE Plasma 6 AI Chat Widget

[![KDE Store](https://img.shields.io/badge/KDE%20Store-Download-blue?style=for-the-badge&logo=kde)](https://store.kde.org/p/2360152/) [![GitHub Release](https://img.shields.io/github/v/release/racstan/KDE-AI-Chat?style=for-the-badge&color=success)](https://github.com/racstan/KDE-AI-Chat/releases)

Native, highly responsive AI chat widget (plasmoid) for **KDE Plasma 6** and **Qt 6**. It features seamless multi-provider switching, real-time model discovery, session persistence, direct SSE streaming, flexible API key storage, and native chat export. Available to download on the [KDE Store](https://store.kde.org/p/2360152/).

---

### 📸 Showcase & Feature Walkthrough

#### 🖼️ Screenshot Gallery & Walkthrough

| Screenshot | Feature & Explanation |
| :--- | :--- |
| ![Live Chat UI](.github/assets/image.png) | **Premium Native Chat UI**: Features a beautiful, high-performance conversational interface with rich Markdown support (headers, lists, tables, and nested elements) rendered instantly with smooth layout scrolling. |
| ![OpenCode Bridge](.github/assets/image2.png) | **OpenCode Developer Bridge**: Build an interactive execution link between the chat widget and your local OpenCode workspace. When active, it displays the unique session ID header and utilizes developer-focused models (e.g. `deepseek`) for CLI or scripting tasks. |
| ![Conversations Sidebar](.github/assets/image3.png) | **Sidebar Chat History**: Conveniently manage your conversations grouped by calendar history. Supports one-click thread renaming, archiving, and deletion. OpenCode developmental streams are clearly badged with a distinct blue `OC` icon. |
| ![OpenCode Settings](.github/assets/image4.png) | **OpenCode General Settings**: Easily toggle developer mode, verify/restart the local server engine using interactive status controls, customize custom service ports, and auto-discover provider backends. |
| ![API Key Storage Settings](.github/assets/image5.png) | **Flexible API Key Storage & Prompts**: Tailor custom system prompts and switch API credentials storage between Session-Only, persistent Plain Config, or encrypted KWallet. DBus-backed KWallet controls allow selecting secure keyrings on-the-fly. |


---

## Key Features

### Chat & Conversations
- **🌳 Conversation Forking**: Fork any conversation at any message with a single click. Forked sessions display a distinct `[FK]` badge and git-branch icon in the session history sidebar, keeping branching clear and organized.
- **👁️ Unread Message Tracking**: Every session tracks read vs. total messages. Unread counts appear as badges in the sidebar (capped at `99+`), making it easy to spot sessions with new responses.
- **📤 Chat Export**: Export any conversation to `.md` or `.txt` with auto-generated filenames (`<title>_<timestamp>.<ext>`).
- **🧠 User Memory**: Enable persistent memory that's injected into every prompt. Write facts (your name, preferences, context) the AI should always remember — configured once, applied everywhere.
- **🗄️ Custom Chat History Path**: Store chat logs at any absolute directory path. Migration happens automatically when the path changes.
- **🧭 Viewport-Aware Navigation**: Jump between user questions instantly via Up/Down navigation buttons.
- **📊 Token Usage & Cost Diagnostics**: Real-time token counts (input, output, reasoning, cache) and cost estimates on every assistant bubble.
- **⚡ Ultra-Stable Scrolling**: Large `cacheBuffer` values eliminate scroll jitter and auto-snap collisions.

### Provider Ecosystem
- **🔄 21 Provider Support**: OpenAI, Anthropic (Claude), Groq, DeepSeek, MiniMax, Fireworks AI, Google Gemini, OpenRouter, Mistral, Cloudflare Workers AI, NVIDIA NIM, Hugging Face, xAI (Grok), LiteLLM Proxy, Qwen, Moonshot, MiMo, Maritaca, LM Studio, Local (OpenAI-compatible), and Ollama.
- **🔍 Dynamic Model Discovery**: Auto-populates model lists from each provider's API endpoint with a real-time searchable combobox.
- **🔑 3-Way API Key Storage**: Choose between **Session Only** (in-memory), **Plain Config** (`~/.config/kdeaichatrc`), or **Secure KWallet** (DBus-encrypted). Switch instantly with no restart. Includes config file open/reload and KWallet Manager launch buttons.
- **🛡️ Offline & Local AI Priority**: Keyless integration with Ollama, LM Studio, and LiteLLM Proxy for absolute privacy.
- **📎 Multi-Format File Attachments**: Drag-and-drop or paste images, PDFs, CSVs, Word documents, and text files. Supports prompt-less attachment-only submissions.

### Scheduled Automation
- **⏰ Native AI Scheduler (systemd daemon)**: Zero-dependency Python 3 daemon (`kde-ai-scheduler.py`) that runs independently via a systemd user service. Full 5-field cron expression support with step values, ranges, and named weekdays.
- **📋 Full Schedule CRUD**: Dedicated `ScheduleDialog` with create/edit/delete, enable/disable toggles, "Run now" buttons, 6 quick presets, per-schedule provider/model/key configuration, result retention policies, and executed history logs.
- **🔔 Desktop Notifications & Audio Alerts**: Critical failure notifications, completion alerts, configurable notification titles, and unique audio chime on scheduled task execution.
- **⚡ Slash Commands**: Type `/schedule` inside any chat to list or create automated prompts without opening settings.
- **🔄 Daemon Management**: Start/Stop/Reload/Auto-start controls directly in settings with live status badges (green/red pill).

### Internationalization & Accessibility
- **🌐 10 Language Support**: Full localization for English, Arabic, Chinese, French, German, Hindi, Italian, Japanese, Portuguese, Russian, and Spanish. Language selector in settings.
- **🔁 RTL Layout Mirroring**: Automatic right-to-left layout support for Arabic and other RTL languages — chat bubbles and UI components mirror correctly.
- **🛠️ Interactive Setup Guides**: Context-aware guide cards for every settings section (General, Provider, API Storage, Scheduler) that update live based on your selections.

### OpenCode Developer Bridge
- **🛡️ OpenCode Integration**: Establish a local bridge to your OpenCode workspace and interact via the widget. Use MCPs, custom providers, and skills configured in OpenCode — write/debug code, run web searches, execute local dev workflows from your Plasma panel.
- **Clean Short Session IDs**: Both provider and OpenCode sessions use clean, short IDs for better readability in history and diagnostics.

### Quality & Tooling
- **🎨 Custom Popup Canvas Scaling**: Bottom-right drag-to-resize handle with coordinates persisted via KConfigXT.
- **✅ Zero QML Warnings**: Codebase passes `qmllint` with 0 errors and 0 warnings.
- **🧪 CI Pipeline**: GitHub Actions runs Python syntax checks, `ruff` linting, 39 pytest test cases, QML linting, QML unit tests, YAML linting, and Markdown linting on every push.
- **🔒 Security Hardening**: Python KWallet helper eliminates shell-injection vectors. Base64 config serialization prevents bash double-quote issues. DBus filters protect input fields.

---

#### 🎥 Feature Demonstration Video (6-Part Walkthrough)

See **KDE AI Chat** in action! Below is a highly detailed, 6-part sequential video demonstration of the widget's capabilities and end-to-end features:

##### 🎬 Part 0: Introduction & UI Walkthrough
*Overview of the native Qt/QML user interface, directional chat bubble layouts, and scrolling fluidities:*
<video src="https://github.com/user-attachments/assets/f46ac923-6602-4d05-aedc-a6a64f8fa7c8" width="100%" controls></video>

##### 🎬 Part 1: Multi-Provider & Model Selection
*Showcases real-time searchable dropdown lists, dynamic model discovery, and 15+ built-in API providers:*
<video src="https://github.com/user-attachments/assets/6e2c8050-630a-4f1d-8efb-2d562754149f" width="100%" controls></video>

##### 🎬 Part 2: 3-Way API Key Storage
*Detailed walk-through of the flexible credentials vault setups — Session Only, persistent Plain Config, and secure DBus KWallet:*
<video src="https://github.com/user-attachments/assets/a85601cf-f7ae-43ca-9c06-6eb78595d651" width="100%" controls></video>

##### 🎬 Part 3: Document & File Attachments
*Demonstration of prompt-less and multi-format file attachment parsing with drag-and-drop:*
<video src="https://github.com/user-attachments/assets/8b93e6da-b40b-46f9-88f8-18be440bb6af" width="100%" controls></video>

##### 🎬 Part 4: OpenCode Developer Bridge
*Connecting the local OpenCode execution bridge to render structured choice buttons, code previews, and token usage diagnostics:*
<video src="https://github.com/user-attachments/assets/c9a62f2b-240d-40ea-b785-e118f43c9780" width="100%" controls></video>

##### 🎬 Part 5: Settings Customizations & Chat Export
*Tinkering with config canvas scaling, custom system prompts, audio chimes, and exporting threads to Markdown or text:*
<video src="https://github.com/user-attachments/assets/3c65c3e9-b96d-482c-a471-9c54c5abc9fb" width="100%" controls></video>

---

## Recent Development Highlights

### 📌 Conversation Forking
Fork any conversation at any point. Forked sessions display a distinct `FK` badge in the history sidebar, keeping branched conversations clearly separated from the original thread. Permits editing older messages without losing context.

### 👁️ Unread Message Tracking
Each session tracks read vs. total message count. Sessions with unread responses display a count badge in the sidebar (capped at `99+`), making it easy to spot conversations with new AI responses at a glance.

### 🧠 User Memory
Enable persistent memory that's injected into the system prompt of every message. Write facts (your name, preferences, context) the AI should always remember — configured once in settings, applied to every conversation.

### 🗄️ Chat History Management
- **Custom storage path**: Choose any absolute directory for chat history. The widget auto-migrates on path change.
- **History migration**: Seamless background migration when storage path changes — no data loss.

### ⏰ Native AI Scheduler (systemd Daemon)
The scheduling system has matured significantly since its initial v1.2.9 release:
- **Full CRUD dialog**: Create, edit, delete, enable/disable, and trigger schedules instantly.
- **Archived schedules + execution history**: Past runs are logged and retained per configurable policy.
- **Per-schedule configuration**: Each schedule stores its own provider, model, API key, base URL, system prompt, max tokens, and notification settings — fully independent of the active widget config.
- **Target Chat selection**: Route scheduled results to a specific chat session.
- **6 quick cron presets**: Hourly, daily 9am, weekdays, and more.
- **Desktop notifications + audio chimes**: Critical failure notifications, configurable alert titles, and unique sound effects on execution.
- **Slash command integration**: Type `/schedule` in any chat to manage schedules.
- **Live daemon status**: Green/red status pill, Start/Stop/Reload/Auto-start controls.
- **Cron validation**: Front-end validation with human-readable preview.
- **SSE timeout UI**: Configurable timeout for scheduled API calls.

### 🌐 Internationalization (i18n)
- **10 fully localized languages**: English, Arabic, Chinese, French, German, Hindi, Italian, Japanese, Portuguese, Russian, Spanish.
- **Language selector**: Dropdown in settings to change UI language on the fly.
- **RTL layout mirroring**: Automatic right-to-left support for Arabic — chat bubbles, layout direction, and UI components mirror correctly.
- **Modular translation files**: Each language in its own `translations_*.js` file for easy contribution.

### 🔧 Settings & UI Improvements
- **Interactive setup guides**: Context-aware guide cards for General, Provider, API Storage, and Scheduler sections that update live based on selections.
- **Hide redundant URLs**: Major cloud providers' URL fields auto-hide when not needed.
- **OpenCode mode in Provider section**: Mutually exclusive mode checkboxes, cleaner layout.
- **Hide OpenCode bar in empty chats**: Cleaner UI when no OpenCode session is active.
- **Python KWallet helper**: Eliminates shell injection vectors — safer credential management.
- **Clean short session IDs**: Both provider and OpenCode sessions use readable short IDs.
- **ChatBubble extracted as standalone delegate**: Better code modularity and maintainability.

### 🧪 CI & Testing
- **39 Python unit tests**: pytest suite for scheduler and doc extractor, run on every push.
- **QML unit tests**: Integrated `qmltestrunner` execution in CI pipeline.
- **Ruff linting & yamllint & markdownlint**: All enforced in CI.
- **qmllint enforcement**: Zero warnings/errors required for all QML files.

---

## Repository Structure

**KDE AI Chat** is 100% open-source. The repository follows a standard KDE Plasma KPackage layout:

```text
KDE-AI-Chat/
├── org.kde.plasma.kdeaichat/       # Core Widget Package (KPackage structure)
│   ├── metadata.json             # Plasmoid manifest (version, licensing, API specs)
│   └── contents/
│       ├── config/
│       │   ├── config.qml        # Config UI page binder
│       │   └── main.xml          # KConfigXT schema for persistent storage
│       ├── scripts/
│       │   ├── kde-ai-scheduler.py  # Scheduling daemon (systemd service)
│       ├── ui/
│       │   ├── ConfigGeneral.qml # Widget settings panel (sync logic & API keys)
│       │   ├── main.qml          # Widget main interface (popup, SSE streaming)
│       │   ├── ScheduleDialog.qml # Schedule CRUD dialog
│       │   ├── translations.js   # Translation engine (10 languages)
│       │   ├── ProviderData.js   # Provider registry
│       │   ├── doc_extractor.py  # File attachment extraction (PDF, DOCX, images)
│       │   └── kde-ai-kwallet.py # KWallet Python helper
├── tests/                        # Python test suite (39 test cases)
├── docs/                         # Developer & user documentation
├── .github/workflows/ci.yml      # CI pipeline (lint, test, qmllint)
├── .gitignore
├── install.sh                    # One-click developer clean-reinstall script
├── SETUP.md                      # End-user credentials & provider setup guide
├── ARCHITECTURE.md               # Codebase architecture & data flow
├── CONTRIBUTING.md               # Contributor guide
└── SECURITY.md                   # Security policy
```

---

## Installation

You can install **KDE AI Chat** directly via the KDE Store, through your Plasma desktop interface, or build it directly from source for custom developer options.

### Option 1: Web Browser Download (KDE Store)
1. Open the official **[KDE Store Page for KDE AI Chat](https://store.kde.org/p/2360152/)**.
2. Click the **Download** button on the right to download the pre-compiled `.plasmoid` bundle package.
3. Install the package using the native Plasma widget installer or via terminal:
   ```bash
   kpackagetool6 -i /path/to/downloaded-package.plasmoid
   ```

### Option 2: Native Desktop Installation (GUI)
1. Right-click your desktop background or the Plasma panel and select **Add Widgets...**
2. Click **Get New Widgets** -> **Download New Plasma Widgets...**
3. In the search box, search for **"KDE AI Chat"** and click **Install**.

*This automatically fetches and registers the pre-compiled, verified release package from the KDE Store.*

### Option 3: Clone and Install from Source (For Developers)
If you want to run the latest development build or customize the source files:
1. Clone the open-source repository:
   ```bash
   git clone https://github.com/racstan/KDE-AI-Chat.git
   cd KDE-AI-Chat
   ```
2. Run the one-click local installation script:
   ```bash
   ./install.sh
   ```
3. Restart your Plasma shell to apply changes and register the widget:
   ```bash
   systemctl --user restart plasma-plasmashell.service
   ```
4. Right-click your desktop/panel, select **Add Widgets...**, search for **KDE AI Chat**, and drag it onto your screen!

---

## Quality Standards

Every release follows a rigorous QA checklist:
- **Syntax Integrity**: `qmllint` passes with 0 warnings and 0 errors.
- **Security Hardening**: Secure DBus API key storage with input sanitization. Plain config mode uses base64-encoded payloads to prevent shell injection.
- **Process Robustness**: Resizing coordinates persist across sessions; long-running API tasks execute off-thread to keep the Plasma shell fluid.

---

## Build & Publishing Flow (For Developers)

For developers packaging the widget from local sources, building the distribution archive requires zipping the QML package structure:

```bash
# Compress the QML folder into a Plasma-compliant .plasmoid archive
zip -r "dist/org.kde.plasma.kdeaichat.plasmoid" org.kde.plasma.kdeaichat \
  -x "*.git*" "*__pycache__*" "*.DS_Store"
```


## Changelog

For a detailed history of features, bug fixes, and performance updates across all releases, please refer to the dedicated [changelog.md](changelog.md) file.

---

## 🤝 Open to Contributions

KDE AI Chat is built by the community, for the community! We welcome contributions, bug reports, and feature requests.

### 🚀 Planned Roadmap
1. **Elegant UI Enhancements**: Premium visual aesthetics, micro-animations, glassmorphism panels.
2. **Interactive Elements for OpenCode**: Rich interactive layouts inside chat bubbles with code previews, live shell triggers, and compiler feedback.
3. **PDF Export**: Generate formatted, printable PDF reports directly from the sidebar.
4. **Additional Providers**: Community-requested API provider integrations.

---

## 🛠️ System Dependencies & Inline Diagnostics

KDE AI Chat is built strictly using Plasma 6 native libraries. However, specific features (like reading PDF/Word files, or saving credentials securely to KWallet) rely on standard Linux system tools. 

If any tool is missing, the widget **will not crash**. Instead, it uses **intelligent inline diagnostics** to warn you and explain exactly what commands to run to resolve the issue!

### Recommended Optional Packages

| Feature | Required CLI Utility | Debian/Ubuntu | Arch Linux | Fedora |
| :--- | :--- | :--- | :--- | :--- |
| **PDF Attachment Reading** | `pdftotext` | `sudo apt install poppler-utils` | `sudo pacman -S poppler` | `sudo dnf install poppler-utils` |
| **Word Document Reading** | `pandoc` (Optional Fallback) | `sudo apt install pandoc` | `sudo pacman -S pandoc-cli` | `sudo dnf install pandoc` |
| **Secure KWallet Storage** | `qdbus6` or `qdbus` | *Pre-installed* (part of `qt6-tools`) | *Pre-installed* (part of `qt6-base`) | *Pre-installed* (part of `qt6-tools`) |
| **Scheduler Daemon** | `systemctl` (user) | *Pre-installed* | *Pre-installed* | *Pre-installed* |
| **Desktop Notifications** | `notify-send` | `sudo apt install libnotify-bin` | `sudo pacman -S libnotify` | `sudo dnf install libnotify` |
| **Audio Alerts** | `pw-play`/`paplay`/`aplay` | `sudo apt install pipewire-audio` | `sudo pacman -S pipewire` | `sudo dnf install pipewire` |

---

## 🔒 Secure Storage & 🛠️ OpenCode Developer Bridge

### Flexible API Key Storage
KDE AI Chat offers three modes of API key storage to suit any workflow:

| Mode | Where keys are stored | Survives restart? |
|:--|:--|:--|
| **Session Only** | In-memory only | ❌ No |
| **Plain Config** | `~/.config/kdeaichatrc` | ✅ Yes |
| **Secure KWallet** | KDE Wallet via DBus | ✅ Yes (encrypted) |

Switch modes instantly from the settings panel — no restart needed. You can also open the config file, reload keys from disk, or launch KWallet Manager directly from the same panel.

### Custom Chat History Storage Path (New in v1.2.9)
By default, the widget persists your conversation histories inside Plasma's central containment file (`~/.config/plasma-org.kde.plasma.desktop-appletsrc`).
If you prefer to save your chat logs to a custom location (e.g., a shared folder, backup drive, or specific file), you can enter an absolute path under **Chat storage path** in the settings panel (e.g., `~/.config/kdeaichat_history.json`). The widget will automatically synchronize all session records directly to this file, ensuring portability and full local control.

### Secure KWallet Integration
KDE AI Chat integrates natively with your desktop's secure credentials subsystem, **[KWallet](https://apps.kde.org/kwalletmanager5/)**, using secure DBus transactions (`qdbus6 org.kde.kwalletd6`). When active, it safeguards all your sensitive API keys, preventing them from being stored in plain text configuration files.
- See [SETUP.md](SETUP.md) for complete setup instructions and troubleshooting.
- Download & manage KWallet: [KDE Wallet Manager](https://apps.kde.org/kwalletmanager5/)

### OpenCode Developer Bridge
Turn your chat interface into an interactive code execution workspace with the native **[OpenCode](https://opencode.ai/) Bridge**. Enable it with a single toggle in the bottom toolbar to establish a local connection with your OpenCode execution environment, rendering structured decision options, code previews, and token-based diagnostics directly in the chat bubbles.
- Official OpenCode site: [opencode.ai](https://opencode.ai/)
- GitHub repository: [sst/opencode](https://github.com/sst/opencode)
- For instructions on running and managing sessions, see the [OpenCode Developer Bridge Guide](docs/opencode-bridge.md).

---

## Documentation

- [End-User Setup & API Keys Guide](SETUP.md) — Comprehensive guide for all 21 providers, features, and troubleshooting.
- [Architecture Overview](ARCHITECTURE.md) — Codebase architecture, component descriptions, and data flow diagrams.
- [Contributing Guidelines](CONTRIBUTING.md) — How to contribute, code conventions, and pull request process.
- [Security Policy](SECURITY.md) — API key storage security, vulnerability reporting, and hardening details.
- [Changelog](changelog.md) — Full release history.
- [OpenCode Developer Bridge](docs/opencode-bridge.md) — Guide to using the OpenCode integration for local AI coding.
- [Scheduled Prompts User Guide](docs/scheduler-usage.md) — Automating AI prompts with the scheduling system.
- [Translation Guide](docs/translation-guide.md) — Adding or updating language translations.

---

## License

GPL-2.0+ — See `metadata.json` for licensing specs.
