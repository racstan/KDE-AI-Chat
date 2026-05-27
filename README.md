# KDE AI Chat — Native KDE Plasma 6 AI Chat Widget

[![KDE Store](https://img.shields.io/badge/KDE%20Store-Download-blue?style=for-the-badge&logo=kde)](https://store.kde.org/p/2360152/) [![GitHub Release](https://img.shields.io/github/v/release/racstan/KDE-AI-Chat?style=for-the-badge&color=success)](https://github.com/racstan/KDE-AI-Chat/releases)

Native, highly responsive AI chat widget (plasmoid) for **KDE Plasma 6** and **Qt 6**. It features seamless multi-provider switching, real-time model discovery, session persistence, direct SSE streaming, flexible API key storage, and native chat export. Available to download on the [KDE Store](https://store.kde.org/p/2360152/).

---

### 📸 Showcase & Feature Walkthrough

#### 🎥 Feature Demonstration Video (Two-Part Walkthrough)

See **KDE AI Chat** in action! Below is a detailed walkthrough of the widget's capabilities, split into two sequential parts. Viewers are advised to watch the continuation in **Part 2** immediately after finishing **Part 1**:

##### 🎬 Part 1: Core Interface, Model Selection & Secure Key Setup
*Showcases interactive provider and model switching, local offline prioritizing, and secure native KWallet integration:*

<video src="https://github.com/user-attachments/assets/b0af2ca7-f556-469e-a136-3006f8ee582f" width="100%" controls></video>

##### 🎬 Part 2: OpenCode Developer Bridge, Document Attachments & Scaling Customization
*Continuation detailing chat session management, document and multi-format attachment analysis, settings tuning, and local OpenCode developer execution:*

<video src="https://github.com/user-attachments/assets/32d8b39e-7357-4543-ab97-7834031f5f40" width="100%" controls></video>

---

#### 🖼️ Screenshot Gallery & Walkthrough

| Screenshot | Feature & Explanation |
| :--- | :--- |
| ![Model Switcher & API Config](.github/assets/image.png) | **Providers & Models Dropdown**: Use any provider from our extensive list with your custom API keys, or run offline local models through local engines (Ollama, LM Studio, LiteLLM Proxy). For persistent saving of API keys, utilize the secure native **KWallet** storage backend, save to a plain config file, or keep them in-session only — your choice! |
| ![OpenCode Mode & Bridge Integration](.github/assets/image2.png) | **OpenCode Bridge**: Build an interactive execution bridge between the chat widget and your local OpenCode environment. Simply toggle the **OpenCode** selector to make it the default conversation mode. Start the local OpenCode server, click refresh, and select your preferred providers and model weights. |
| ![Session History Management](.github/assets/image3.png) | **Conversations Sidebar**: Efficiently manage all your active chats in the sidebar history panel. Supports renaming, archiving, and deleting threads in a click. OpenCode developmental chats are visually styled differently so you can tell them apart at a glance! |
| ![Widget Customizations](.github/assets/image4.png) | **Widget Settings Panel**: Custom tuning, custom system prompt templates, theme overrides (Dark/Light follow system), audio chime notifications, and dynamic scaling controls. We highly recommend users look after this panel to tinker and play with each custom option! |
| ![About & Contributing Page](.github/assets/image5.png) | **About KDE AI Chat**: Showcases licensing, version metrics, and project credits. We are fully open to contributions and community feedback to expand Plasmoid AI integrations! |


---

## Key Features

- **📎 Multi-Format Document & File Attachments**: Drag-and-drop or paste images, PDFs, CSVs, Word documents, and text files directly into the input bar, with support for sending prompt-less attachment queries.
- **🔄 15+ Provider Support**: Native integration with OpenAI, Anthropic (Claude), Groq, DeepSeek, MiniMax, Fireworks AI, Google Gemini, OpenRouter, Mistral, Cloudflare Workers AI, NVIDIA NIM, Hugging Face, xAI (Grok), LM Studio, Local (OpenAI-compatible), Ollama, and **LiteLLM Proxy**.
- **🔑 3-Way API Key Storage**: Choose between **Session Only** (keys live in memory), **Plain Config** (saved to `~/.config/kdeaichatrc`), or **Secure KWallet** (native DBus-encrypted storage). Open, reload, or clear the config file directly from the settings panel.
- **📤 Chat Export**: Export any conversation to a timestamped `.md` or `.txt` file. Filenames are automatically pre-filled as `<chat_title>_<timestamp>` for instant saving.
- **💬 Directional Chat Bubbles**: User messages appear **right-aligned** in the live chat UI with a distinct bubble colour, while AI responses and system messages are left-aligned — just like any modern messaging app. Exported files mirror this layout too.
- **🌳 Conversation Forking (Branch Editing)**: Editing any older user message automatically deletes subsequent logs and forks the branch as a fresh request, maintaining clean conversation histories.
- **🧭 Viewport-Aware Navigation**: Jump between user questions instantly via Up/Down navigation buttons that calculate coordinate offsets accurately relative to the active scroll viewport.
- **📊 Token Usage & Cost Diagnostics**: Real-time display of token consumption (input, output, reasoning, cache read/write) and prompt costs on assistant bubbles.
- **⚡ Ultra-Stable Scrolling**: Features huge caching (`cacheBuffer`) and mouse wheel/scrollbar interaction hooks to eliminate scroll layout jumping and auto-snap collisions.
- **🛡️ Offline & Local AI Priority**: Keyless out-of-the-box integration with offline local LLM engines (Ollama, LM Studio, LiteLLM Proxy), ensuring absolute privacy.
- **🔍 Dynamic Model Discovery**: Auto-detects and populates model lists directly from API endpoints, featuring a real-time searchable combobox.
- **🎨 Custom Popup Canvas Scaling**: Bottom-right drag-to-resize handle with coordinates persisted via KConfigXT backend.

---

## What's New Since v1.2.6

The following features have been added after the v1.2.6 release and are available in the latest development build:

### 🗄️ Flexible API Key Storage (3-Way Mode)
Replaced the old KWallet on/off toggle with a full **3-mode key storage selector**:
- **Session Only** — keys are kept purely in memory and discarded when the widget is closed.
- **Plain Config** — keys are saved persistently to `~/.config/kdeaichatrc` and auto-loaded on startup.
- **Secure KWallet** — keys are stored in and loaded from your desktop's secure credentials vault via DBus.

Settings are **automatically persisted** as you type — no need to click Apply to save your configuration changes.

### 🛠️ Settings Panel Utilities
New action buttons in the settings panel:
- **Open Config File** — opens `~/.config/kdeaichatrc` directly in your default text editor.
- **Reload from Config** — manually re-reads the config file and populates all API key fields without restarting.
- **Launch KWallet Manager** — opens the KDE Wallet Manager so you can inspect or manage stored keys.
- **Clear Chat** — wipes the active conversation with one click directly from the settings panel.

### 📤 Chat Export
Export any conversation to a file from the chat toolbar:
- Choose between **Markdown (`.md`)** or **plain text (`.txt`)** output.
- The save dialog is pre-filled with a descriptive filename: `<chat_title>_<timestamp>.<ext>`.
- Exported files use full **UTF-8 encoding** and include a formatted header with the export timestamp.
- Messages are cleanly formatted with role labels, timestamps, and proper wrapping.

### 💬 Right-Aligned User Messages (Live Chat UI)
User messages now appear **right-aligned** with a distinct bubble colour directly in the **live chat popup**, mirroring familiar mobile and web chat interfaces. AI responses and system messages remain left-aligned. Exported files also reflect this layout with right-aligned user text blocks.

### 🔗 LiteLLM Proxy Support
**LiteLLM Proxy** has been added as a fully supported provider:
- Connects to any LiteLLM-compatible proxy server (default: `http://localhost:4000/v1`).
- API key is optional — works with keyless local proxy setups.
- Full model discovery, KWallet/plain config key storage, and model selection are all supported.
- Enables routing to 100+ LLMs (GPT, Claude, Gemini, Mistral, etc.) through a single unified interface.

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
├── SETUP.md                      # End-user credentials & provider setup guide
└── FORUSER.md                    # Release and publishing runbook
```

---

## Installation

You can install **KDE AI Chat** either directly through your desktop interface (recommended for general users) or build it directly from source (for developers and power users).

### Option 1: Native Desktop Installation (Recommended)
1. Right-click your desktop background or the Plasma panel and select **Add Widgets...**
2. Click **Get New Widgets** -> **Download New Plasma Widgets...**
3. In the search box, search for **"KDE AI Chat"** and click **Install**.

*This automatically fetches and registers the pre-compiled, verified release package from the KDE Store.*

### Option 2: Clone and Install from Source (For Developers)
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

For developers packaging the widget from local sources, standard procedures are detailed in the [Release Operator Playbook](FORUSER.md). Building the distribution archive requires zipping the QML package structure:

```bash
# Compress the QML folder into a Plasma-compliant .plasmoid archive
zip -r "dist/org.kde.plasma.kdeaichat-v1.2.7.plasmoid" org.kde.plasma.kdeaichat \
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

## 🔒 Secure Storage & 🛠️ OpenCode Developer Bridge

### Flexible API Key Storage
KDE AI Chat offers three modes of API key storage to suit any workflow:

| Mode | Where keys are stored | Survives restart? |
|:--|:--|:--|
| **Session Only** | In-memory only | ❌ No |
| **Plain Config** | `~/.config/kdeaichatrc` | ✅ Yes |
| **Secure KWallet** | KDE Wallet via DBus | ✅ Yes (encrypted) |

Switch modes instantly from the settings panel — no restart needed. You can also open the config file, reload keys from disk, or launch KWallet Manager directly from the same panel.

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
- [Release Operator Playbook](FORUSER.md) — Bumping versioning, tag management, and release steps.

---

## License

GPL-2.0+ — See `metadata.json` for licensing specs.
