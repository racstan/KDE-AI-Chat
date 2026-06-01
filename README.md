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

- **📎 Multi-Format Document & File Attachments**: Drag-and-drop or paste images, PDFs, CSVs, Word documents, and text files directly into the input bar, with support for sending prompt-less attachment queries.
- **🔄 17 Provider Support**: Native integration with OpenAI, Anthropic (Claude), Groq, DeepSeek, MiniMax, Fireworks AI, Google Gemini, OpenRouter, Mistral, Cloudflare Workers AI, NVIDIA NIM, Hugging Face, xAI (Grok), LM Studio, Local (OpenAI-compatible), Ollama, and LiteLLM Proxy.
- **🔑 3-Way API Key Storage**: Choose between **Session Only** (keys live in memory), **Plain Config** (saved to `~/.config/kdeaichatrc`), or **Secure KWallet** (native DBus-encrypted storage). Open, reload, or clear the config file directly from the settings panel.
- **📤 Chat Export**: Export any conversation to a timestamped `.md` or `.txt` file. Filenames are automatically pre-filled as `<chat_title>_<timestamp>` for instant saving.

- **🌳 Conversation Forking (Branch Editing)**: Editing any older user message automatically deletes subsequent logs and forks the branch as a fresh request, maintaining clean conversation histories.
- **🧭 Viewport-Aware Navigation**: Jump between user questions instantly via Up/Down navigation buttons that calculate coordinate offsets accurately relative to the active scroll viewport.
- **📊 Token Usage & Cost Diagnostics (Beta)**: Real-time display of token consumption (input, output, reasoning, cache read/write) and prompt costs on assistant bubbles.
- **⚡ Ultra-Stable Scrolling**: Features huge caching (`cacheBuffer`) and mouse wheel/scrollbar interaction hooks to eliminate scroll layout jumping and auto-snap collisions.
- **🛡️ Offline & Local AI Priority**: Keyless out-of-the-box integration with offline local LLM engines (Ollama, LM Studio, LiteLLM Proxy), ensuring absolute privacy.
- **🔍 Dynamic Model Discovery**: Auto-detects and populates model lists directly from API endpoints, featuring a real-time searchable combobox.
- **🛡️ OpenCode Developer Bridge (Beta)**: Establish a local connection bridge to your OpenCode workspace and interact with the widget just like the OpenCode CLI. If you have MCPs, custom providers, or skills configured in OpenCode, you can utilize them directly here—enabling you to write/debug code, run web searches, and execute complex local developer workflows directly from your Plasma panel (active development).
- **🎨 Custom Popup Canvas Scaling**: Bottom-right drag-to-resize handle with coordinates persisted via KConfigXT backend.

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

## What's New in v1.2.9

### 🧭 4-Section Interactive Setup Guides
Every major section of the settings panel now has its own dedicated, context-aware interactive guide card:

- **General Guide** (top of settings): Explains the Appearance dropdown, Notification sound toggle, and OpenCode mode. Dynamically switches to a full OpenCode setup walkthrough (Start Server → Check Server → pick provider/model → Apply) when OpenCode mode is enabled.
- **Provider Guide** (Provider section): Per-provider setup guide that updates live as you change the provider dropdown. Includes the exact URL where you can get your API key for all 17 cloud providers, and step-by-step local server setup for Ollama, LM Studio, LiteLLM, vLLM, and more.
- **API Storage Guide** (API Key Storage section, before the mode selector): Explains the active storage mode with precise button-level instructions — which buttons to click, in which order, for Session-only, Plain config, and KWallet modes.
- **Other Settings Guide** (Other settings section): Explains App name, System prompt, Chat storage path with Browse..., and Reset to defaults.

### 🗄️ Custom Chat History Directory (Beta)
Users can now store chat logs in a custom directory:
- Enter any absolute directory path under **Chat storage path (beta)** in settings, or click **Browse...** to open a native folder picker.
- The widget saves history as `kdeaichat_history.json` inside the chosen directory.
- Defaults to `~/.config`. Resetting to defaults restores this path correctly.

### 🛠️ Settings Panel Utilities
Action buttons available in the settings panel:
- **Open Config File** — opens `~/.config/kdeaichatrc` directly in your default text editor.
- **Reload from Config** — manually re-reads the config file and populates all API key fields without restarting.
- **Launch KWallet Manager** — opens the KDE Wallet Manager so you can inspect or manage stored keys.
- **Detect wallets / Create wallet / Sync to KWallet / Refresh from KWallet** — full KWallet key management workflow directly in settings.

### 📤 Chat Export
Export any conversation to a file from the chat toolbar:
- Choose between **Markdown (`.md`)** or **plain text (`.txt`)** output.
- The save dialog is pre-filled with a descriptive filename: `<chat_title>_<timestamp>.<ext>`.

### 🔗 17 Provider Support
Full support for all 17 providers including LiteLLM Proxy:
- Connects to any LiteLLM-compatible proxy server (default: `http://localhost:4000/v1`).
- Enables routing to 100+ LLMs through a single unified interface.

---

## Codebase Quality & Audit Status

As of **May 27, 2026**, the codebase has undergone a comprehensive structural audit and is marked **100% production-ready**:
- **Diagnostic Safety**: The codebase successfully compiles and passes QML structural analysis using the KDE diagnostic suite (`qmllint`) with **zero errors and zero warnings**.
- **Security Hardening**: Secure DBus transactions with DBus filters in `applyLoadedKey` to prevent status warnings from entering input fields. Base64 serialization is used to safely pass configuration payloads through shell commands, preventing all bash double-quote stripping issues.
- **Immaculate Directory**: All pre-production developer notes, scratchpads, and unused file assets have been removed for clean packaging.

---

## Repository Structure

**KDE AI Chat** is 100% open-source. The repository is organized under a standard KDE Plasma KPackage layout, allowing developers to audit, run diagnostic linters, and build from source:

```text
KDE-AI-Chat/
├── org.kde.plasma.kdeaichat/       # Core Widget Package (KPackage structure)
│   ├── metadata.json             # Plasmoid manifest (version, licensing, API specs)
│   └── contents/
│       ├── config/
│       │   ├── config.qml        # Config UI page binder
│       │   └── main.xml          # KConfigXT schema for persistent storage
│       └── ui/
│           ├── ConfigGeneral.qml # Widget settings panel (sync logic & API keys)
│           └── main.qml          # Widget main interface (popup, database & SSE)
├── .gitignore                    # Git file tracking safety guard
├── install.sh                    # One-click developer clean-reinstall script
├── audit.md                      # Detailed technical audit report
└── SETUP.md                      # End-user credentials & provider setup guide
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

## Technical Audit & Quality Control

Every package release is built following a rigorous QA checklist. The code is audited to verify:
- **Syntax Integrity**: Compiles with `qmllint` showing 0 warnings and 0 errors.
- **Security Protocols**: Safe DBus API key storage with input sanitization to protect user credentials. Plain config mode uses base64-encoded payloads to prevent shell injection.
- **Process Robustness**: Resizing coordinates persist natively across system sessions, and long-running API tasks execute strictly off-thread to ensure the Plasma desktop shell remains 100% fluid.

For detailed analysis, refer to the [Technical Audit Report](audit.md).

---

## Build & Publishing Flow (For Developers)

For developers packaging the widget from local sources, building the distribution archive requires zipping the QML package structure:

```bash
# Compress the QML folder into a Plasma-compliant .plasmoid archive
zip -r "dist/org.kde.plasma.kdeaichat-v1.2.9.plasmoid" org.kde.plasma.kdeaichat \
  -x "*.git*" "*__pycache__*" "*.DS_Store"
```


## Changelog

For a detailed history of features, bug fixes, and performance updates across all releases, please refer to the dedicated [changelog.md](changelog.md) file.

---

## 🤝 Open to Contributions & Future Roadmap

**KDE AI Chat** is built by the community, for the community! We are highly open to contributions, bug reports, and collaborative feature enhancements to shape the best native Linux AI experience.

### 🚀 What We're Working On Next
We are planning multiple active development rounds to implement new requested features:
1. **Elegant UI Enhancements**: Redefining QML layouts with premium modern visual aesthetics, sleek micro-animations, glassmorphism card panels, and smooth scroll interfaces.
2. **Interactive Elements for OpenCode**: Introducing rich interactive layouts inside chat bubbles to render code previews, live shell triggers, and interactive compiler feedback widgets.
3. **Scheduled Chats & Prompt Automation**: Implementing a robust scheduling calendar to automate recurrent prompts, execute off-hour diagnostics, and trigger timed workflows.
4. **PDF Export**: Extending the chat export utility to generate formatted, printable PDF reports directly from the sidebar.

---

## 🛠️ System Dependencies & Inline Diagnostics

KDE AI Chat is built strictly using Plasma 6 native libraries. However, specific features (like reading PDF/Word files, or saving credentials securely to KWallet) rely on standard Linux system tools. 

If any tool is missing, the widget **will not crash**. Instead, it uses **intelligent inline diagnostics** to warn you and explain exactly what commands to run to resolve the issue!

### Recommended Optional Packages

| Feature | Required CLI Utility | Debian/Ubuntu | Arch Linux | Fedora |
| :--- | :--- | :--- | :--- | :--- |
| **PDF Attachment Reading** | `pdftotext` | `sudo apt install poppler-utils` | `sudo pacman -S poppler` | `sudo dnf install poppler-utils` |
| **Word Document Reading** | `pandoc` (Optional Fallback) | `sudo apt install pandoc` | `sudo pacman -S pandoc-cli` | `sudo dnf install pandoc` |
| **Secure KWallet Storage** | `qdbus6` or `qdbus` | *Pre-installed* (part of `qt6-tools` / `qttools`) | *Pre-installed* (part of `qt6-base` / `qttools`) | *Pre-installed* (part of `qt6-tools` / `qttools`) |

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
- For complete setup instructions and troubleshooting, refer to the [KWallet Secure Storage Guide](user_manual.md#3-secure-storage-kwallet-vs-plain-configs).
- Download & manage KWallet: [KDE Wallet Manager](https://apps.kde.org/kwalletmanager5/)

### OpenCode Developer Bridge
Turn your chat interface into an interactive code execution workspace with the native **[OpenCode](https://opencode.ai/) Bridge**. Enable it with a single toggle in the bottom toolbar to establish a local connection with your OpenCode execution environment, rendering structured decision options, code previews, and token-based diagnostics directly in the chat bubbles.
- Official OpenCode site: [opencode.ai](https://opencode.ai/)
- GitHub repository: [sst/opencode](https://github.com/sst/opencode)
- For instructions on running and managing sessions, see the [OpenCode Developer Bridge Guide](user_manual.md#5-opencode-developer-bridge-guide).

---

## Documentation Guides

- [User Operations Manual & FAQ](user_manual.md) — Dynamic step-by-step operating workflows, local setups, and detailed troubleshooting solutions.
- [End-User Setup & API Keys Guide](SETUP.md) — Comprehensive guide on creating accounts and retrieving keys for all supported providers.
- [Technical Audit & Code Quality Report](audit.md) — Detailed results of the May 2026 quality assurance audit.
- [Architecture Overview](ARCHITECTURE.md) — Codebase architecture, component descriptions, and data flow diagrams.
- [Contributing Guidelines](CONTRIBUTING.md) — How to contribute, code conventions, and pull request process.
- [Security Policy](SECURITY.md) — API key storage security, vulnerability reporting, and hardening details.
- [OpenCode Developer Bridge](docs/opencode-bridge.md) — Guide to using the OpenCode integration for local AI coding.
- [Scheduled Prompts User Guide](docs/scheduler-usage.md) — Automating AI prompts with the scheduling system.
- [Translation Guide](docs/translation-guide.md) — Adding or updating language translations.

---

## License

GPL-2.0+ — See `metadata.json` for licensing specs.
