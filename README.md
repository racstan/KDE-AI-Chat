# KDE AI Chat — Native KDE Plasma 6 AI Chat Widget

[![KDE Store](https://img.shields.io/badge/KDE%20Store-Download-blue?style=for-the-badge&logo=kde)](https://store.kde.org/p/2360152/) [![GitHub Release](https://img.shields.io/github/v/release/racstan/KDE-AI-Chat?style=for-the-badge&color=success)](https://github.com/racstan/KDE-AI-Chat/releases)

Native, highly responsive AI chat widget (plasmoid) for **KDE Plasma 6** and **Qt 6**. It features seamless multi-provider switching, real-time model discovery, session persistence, direct SSE streaming, flexible API key storage, and native chat export. Available to download on the [KDE Store](https://store.kde.org/p/2360152/).

---

## 🚀 Cool & Important Features

### 🔄 Multi-Provider Hub & Searchable Models
*   **21 Providers Supported**: OpenAI, Anthropic (Claude), Groq, DeepSeek, Google Gemini, OpenRouter, Mistral, Cloudflare Workers AI, NVIDIA NIM, Hugging Face, xAI (Grok), LiteLLM Proxy, Qwen, Moonshot, MiMo, Maritaca, MiniMax, Fireworks AI, LM Studio, Local (OpenAI-compatible), and Ollama.
*   **Dynamic Model Discovery**: Auto-populates available models directly from each provider's API endpoint. Includes a real-time searchable combobox for instant model switching.

### ⏰ Native AI Scheduler (systemd Daemon)
*   **Cron-Scheduled Tasks**: A zero-dependency Python 3 daemon (`kde-ai-scheduler.py`) runs independently via a systemd user service. Supports standard 5-field cron expressions with step values (`*/5`), ranges, and named weekdays.
*   **Start / Stop / Reload Lifecycle Controls**:
    *   **Master ON/OFF Switch**: Starts (registers with systemd) and completely stops the daemon processes.
    *   **Restart / Force Start Button**: If the daemon is active, acts as a quick restart trigger. If the daemon has crashed or was stopped externally, it forces the systemd daemon to bootstrap.
*   **Full CRUD Manager**: Dedicated settings section with live daemon status (green/red pill), presets, and a robust CRUD dialog to configure custom prompts, providers, models, system overrides, and execution logs.
*   **Notifications & Alerts**: Displays KDE system notifications and plays custom audio chimes upon task execution or critical diagnostic failures.
*   **Slash Command Integration**: Type `/schedule` directly in any chat to view or manage active automated prompt schedules.

### 🧠 Extremely Low Memory Footprint
*   **Total RAM Usage: ~50-85 MB**:
    *   **QML/Plasma Widget**: ~40-70 MB (depending on Plasma caching).
    *   **Python Daemon**: ~10-15 MB.
    *   This is a fraction of the weight of Electron-based apps or open browser tabs, making it ideal to keep pinned to your panel all day!

### 🔑 3-Way API Key Storage
*   **Session Only**: Stores keys strictly in-memory (discarded when the widget closes).
*   **Plain Config**: Persists keys inside local configurations (`~/.config/kdeaichatrc`).
*   **Secure KWallet (DBus Encrypted)**: Integrates natively with KDE Wallet (`qdbus6 org.kde.kwalletd6`) for fully encrypted, secure key storage. Includes inline buttons to open the config directory or launch KWallet Manager directly.

### 🌐 Internationalization (i18n) & RTL Mirroring
*   **10 Languages**: Full localization support for English, Arabic, Chinese, French, German, Hindi, Italian, Japanese, Portuguese, Russian, and Spanish.
*   **Right-To-Left (RTL)**: Automatic layout mirroring and directional alignment for Arabic and other RTL language environments.

### 📎 Drag-and-Drop File Attachments
*   Drop or paste files (Images, PDFs, CSVs, Word documents, text) directly into the prompt bar. Uses system CLI helpers like `pdftotext` and `pandoc` to parse documents off-thread. Supports attachment-only prompts.

---

## ✨ New Features (v1.3.0)

### 🌳 Conversation Forking
*   **Branch Chats Instantly**: Split your active conversation into a new chat at any message with a single click.
*   **FK Badge & git-branch Icon**: A `git-branch` button appears on every message bubble. Forked conversations are created with a custom `fork-XXXXXX` ID, automatically prefixed with `[FK]`, and marked with a distinct purple `FK` badge in the history pane.

### 👁️ Unread Message Tracking (Background Execution)
*   **Non-Interruptive Scheduled Executions**: Scheduled messages are now executed entirely in the background without stealing active chat window focus or disrupting your workflow.
*   **Sidebar Counts**: Every chat session tracks read vs. total messages. Unread message counts are highlighted as badges in the sidebar (capped at `99+`), making it easy to identify threads with new responses. Reading/opening the chat immediately resets the count.

### 🗄️ Custom Chat History Path & Migration
*   **Flexible Storage**: Enter any custom absolute path in settings to store your conversation history (rather than the default Plasma desktop config).
*   **Auto-Migration**: Changing the storage directory automatically migrates all existing history and sessions to the new location in the background without any data loss.

---

## 🧪 Beta & Experimental Features

### 🔌 OpenCode Developer Bridge (Beta)
*   **Interactive Workspace Link**: Toggle OpenCode bridge mode to establish a local connection with your OpenCode execution engine. Renders interactive choice buttons, inline terminal/code block previews, and compilation feedback directly in chat bubbles.
*   **MCP Skills**: Execute agentic commands, web searches, and local shell actions natively driven by developer-focused models (e.g. `deepseek-coder`).

### 🧠 User Memory Injection (Beta)
*   **Persistent AI Memory**: Save key context, facts, or development preferences in the settings panel. The widget dynamically injects this user profile into the system prompt of every message across all sessions.

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

##### 🎬 Video Walkthrough (6-Part Series)

See **KDE AI Chat** in action! Below is a highly detailed, 6-part sequential video demonstration of the widget's capabilities and end-to-end features:

*   [Part 0: Introduction & UI Walkthrough](https://github.com/user-attachments/assets/f46ac923-6602-4d05-aedc-a6a64f8fa7c8) - Overview of the native Qt/QML user interface, directional chat bubble layouts, and scrolling fluidities.
*   [Part 1: Multi-Provider & Model Selection](https://github.com/user-attachments/assets/6e2c8050-630a-4f1d-8efb-2d562754149f) - Showcases real-time searchable dropdown lists, dynamic model discovery, and 15+ built-in API providers.
*   [Part 2: 3-Way API Key Storage](https://github.com/user-attachments/assets/a85601cf-f7ae-43ca-9c06-6eb78595d651) - Detailed walk-through of the flexible credentials vault setups — Session Only, persistent Plain Config, and secure DBus KWallet.
*   [Part 3: Document & File Attachments](https://github.com/user-attachments/assets/8b93e6da-b40b-46f9-88f8-18be440bb6af) - Demonstration of prompt-less and multi-format file attachment parsing with drag-and-drop.
*   [Part 4: OpenCode Developer Bridge](https://github.com/user-attachments/assets/c9a62f2b-240d-40ea-b785-e118f43c9780) - Connecting the local OpenCode execution bridge to render structured choice buttons, code previews, and token usage diagnostics.
*   [Part 5: Settings Customizations & Chat Export](https://github.com/user-attachments/assets/3c65c3e9-b96d-482c-a471-9c54c5abc9fb) - Tinkering with config canvas scaling, custom system prompts, audio chimes, and exporting threads to Markdown or text.

---

## 🛠️ System Dependencies

The widget uses intelligent inline diagnostics to warn you if a dependency is missing and explains exactly what commands to run.

| Feature | Required CLI Utility | Debian/Ubuntu | Arch Linux | Fedora |
| :--- | :--- | :--- | :--- | :--- |
| **PDF Reading** | `pdftotext` | `sudo apt install poppler-utils` | `sudo pacman -S poppler` | `sudo dnf install poppler-utils` |
| **Word Doc Reading** | `pandoc` | `sudo apt install pandoc` | `sudo pacman -S pandoc-cli` | `sudo dnf install pandoc` |
| **Secure KWallet** | `qdbus6` or `qdbus` | *Pre-installed* (part of `qt6-tools`) | *Pre-installed* (part of `qt6-base`) | *Pre-installed* (part of `qt6-tools`) |
| **Scheduler Daemon** | `systemctl` (user) | *Pre-installed* | *Pre-installed* | *Pre-installed* |
| **Desktop Alerts** | `notify-send` | `sudo apt install libnotify-bin` | `sudo pacman -S libnotify` | `sudo dnf install libnotify` |
| **Audio Alerts** | `pw-play` / `paplay` | `sudo apt install pipewire-audio` | `sudo pacman -S pipewire` | `sudo dnf install pipewire` |

---

## 📦 Installation

### Option 1: Native Desktop Installation (GUI)
1. Right-click your desktop or Plasma panel and select **Add Widgets...**
2. Click **Get New Widgets** -> **Download New Plasma Widgets...**
3. Search for **"KDE AI Chat"** and click **Install**.

### Option 2: Clone and Install from Source (For Developers)
1. Clone the repository:
   ```bash
   git clone https://github.com/racstan/KDE-AI-Chat.git
   cd KDE-AI-Chat
   ```
2. Run the one-click local installation script:
   ```bash
   ./install.sh
   ```
3. Restart your Plasma shell to load the widget:
   ```bash
   systemctl --user restart plasma-plasmashell.service
   ```

---

## Repository Structure

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
├── install.sh                    # One-click developer clean-reinstall script
├── SETUP.md                      # End-user credentials & provider setup guide
├── ARCHITECTURE.md               # Codebase architecture & data flow
├── CONTRIBUTING.md               # Contributor guide
└── SECURITY.md                   # Security policy
```

---

## 🤝 Contributing

We welcome contributions, bug reports, and pull requests! Refer to [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines, testing workflows (including running the 39 python tests and QML linting), and style rules.

### 🚀 Planned Roadmap
1. **Premium UI/UX**: Overhaul styling with modern glassmorphism panels and responsive layout transitions.
2. **Interactive OpenCode Cards**: Code execution widgets, live terminal feedback, and interactive compiler boards.
3. **PDF Export**: Generate formatted, printable PDF logs of chats.
4. **Additional Providers**: Add community-requested local/remote models.

---

## License

GPL-2.0+ — See `metadata.json` for details.
