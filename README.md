# KDE AI Chat — Native KDE Plasma 6 AI Chat Widget

[![KDE Store](https://img.shields.io/badge/KDE%20Store-Download-blue?style=for-the-badge&logo=kde)](https://store.kde.org/p/2360152/) [![GitHub Release](https://img.shields.io/github/v/release/racstan/KDE-AI-Chat?style=for-the-badge&color=success)](https://github.com/racstan/KDE-AI-Chat/releases)

Native, highly responsive AI chat widget (plasmoid) for **KDE Plasma 6** and **Qt 6**. It features seamless multi-provider switching, real-time model discovery, session persistence, direct SSE streaming, flexible API key storage, native chat export, and a built-in AI scheduler daemon. Available to download on the [KDE Store](https://store.kde.org/p/2360152/).

---

## 🚀 Cool & Important Features

### 🔄 Multi-Provider Hub & Searchable Models
*   **21 Providers Supported**: OpenAI, Anthropic (Claude), Groq, DeepSeek, Google Gemini, OpenRouter, Mistral, Cloudflare Workers AI, NVIDIA NIM, Hugging Face, xAI (Grok), LiteLLM Proxy, Qwen, Moonshot, MiMo, Maritaca, MiniMax, Fireworks AI, LM Studio, Local (OpenAI-compatible), and Ollama.
*   **Dynamic Model Discovery**: Auto-populates available models directly from each provider's API endpoint. Includes a real-time searchable combobox for instant model switching.

### ⏰ Native AI Scheduler (systemd Daemon)
*   **Cron-Scheduled Tasks**: A zero-dependency Python 3 daemon (`kde-ai-scheduler.py`) runs independently via a systemd user service. Supports standard 5-field cron expressions with step values (`*/5`), ranges, and named weekdays.
*   **Start / Stop / Restart Controls**: Full daemon lifecycle management in Settings — no terminal required. Toggle the master ON/OFF switch, or use Restart / Force Start / Stop buttons.
*   **Background Execution**: Scheduled messages run completely in the background without switching chats or stealing focus.
*   **Full CRUD Manager**: Dedicated settings section with live daemon status (Active/Stopped), presets, and a robust dialog to configure custom prompts, providers, models, system overrides, and execution logs.
*   **Notifications & Alerts**: Displays KDE system notifications and plays custom audio chimes upon task execution or critical diagnostic failures.
*   **Slash Command Integration**: Type `/schedule` directly in any chat to view or manage active automated prompt schedules.

### 🧠 Extremely Low Memory Footprint
*   **Total RAM Usage: ~50-90 MB**:
    *   **QML/Plasma Widget**: ~40-70 MB (depending on Plasma caching).
    *   **Python Scheduler Daemon**: ~10-25 MB (only when running).
    *   This is a fraction of the weight of Electron-based apps or open browser tabs — ideal to keep pinned to your panel all day!
*   **Live Memory Monitor**: A built-in beta memory panel in Settings shows real-time RAM usage for each component (Plasma Widget, Scheduler Daemon, OpenCode). Refresh any time with a button click.

### 🔑 3-Way API Key Storage
*   **Session Only**: Stores keys strictly in-memory (discarded when the widget closes).
*   **Plain Config**: Persists keys inside local configurations (`~/.config/kdeaichatrc`).
*   **Secure KWallet (DBus Encrypted)**: Integrates natively with KDE Wallet (`qdbus6 org.kde.kwalletd6`) for fully encrypted, secure key storage. Includes inline buttons to open the config directory or launch KWallet Manager directly.

### 🌐 Internationalization (i18n) & RTL Mirroring
*   **11 Languages**: Full localization support for English, Arabic, Chinese, French, German, Hindi, Italian, Japanese, Portuguese, Russian, and Spanish.
*   **Right-To-Left (RTL)**: Automatic layout mirroring and directional alignment for Arabic and other RTL language environments.

### 📎 Drag-and-Drop File Attachments
*   Drop or paste files (Images, PDFs, CSVs, Word documents, text) directly into the prompt bar. Uses system CLI helpers like `pdftotext` and `pandoc` to parse documents off-thread. Supports attachment-only prompts.

---

## ✨ New Features (v1.3.0)

### 🌿 Conversation Forking
*   **Fork Chats Instantly**: Split your active conversation at any message with a single click — a fork button appears on every message bubble.
*   **FK Badge**: Forked conversations are created with a `fork-XXXXXX` ID and marked with a distinct purple **FK** badge in the history sidebar.
*   **Parent Chat Link**: Forked chats display a purple banner at the top linking back to the original chat, with a **"Go to Original Chat"** button for quick navigation.

### 👁️ Unread Message Tracking (Background Execution)
*   **Non-Interruptive Executions**: Scheduled messages run in the background without switching chats or stealing focus.
*   **Sidebar Counts**: Every chat session tracks read vs. total messages. Unread message counts are highlighted as badges in the sidebar (capped at `99+`). Opening the chat immediately resets the count.

### 🗄️ Custom Chat Storage Path
*   **Flexible Storage**: Select any folder to save your chat history (e.g. a Syncthing or cloud-synced directory). Chats are stored as `kdeaichat_history.json` in the chosen folder.
*   **Auto-Export on Path Change**: Switching the storage folder automatically exports all your current chats to the new location with no data loss.
*   **Export Now Button**: Manually trigger a chat export to the configured path at any time from Settings.
*   **Open Folder / Clear Path**: Open the storage folder in your file manager, or reset to default storage in one click.

---

## 🧪 Beta & Experimental Features

### 🔌 OpenCode Developer Bridge (Beta)
*   **Interactive Workspace Link**: Toggle OpenCode bridge mode to establish a local connection with your OpenCode execution engine. Renders interactive choice buttons, inline terminal/code block previews, and compilation feedback directly in chat bubbles.
*   **MCP Skills**: Execute agentic commands, web searches, and local shell actions natively driven by developer-focused models (e.g. `deepseek-coder`).

### 🧠 User Memory Injection (Beta)
*   **Persistent AI Memory**: Save key context, facts, or development preferences in the settings panel. The widget dynamically injects this user profile into the system prompt of every message across all sessions.

### 📊 Live Memory Monitor (Beta)
*   **Real-time RAM Breakdown**: Press **Refresh** in Settings → Other Settings → Memory Usage to see live RSS memory for each component: Plasma Widget (plasmashell), Scheduler Daemon, and OpenCode server. Color-coded indicators show whether usage is healthy or elevated.

---

### 📸 Showcase & Feature Walkthrough

#### 🖼️ Screenshot Gallery & Walkthrough

| Screenshot | Feature & Explanation |
| :--- | :--- |
| ![Live Chat UI](.github/assets/image.png) | **Premium Native Chat UI**: Features a beautiful, high-performance conversational interface with rich Markdown support rendered instantly with smooth layout scrolling. |
| ![OpenCode Bridge](.github/assets/image2.png) | **OpenCode Developer Bridge**: Build an interactive execution link between the chat widget and your local OpenCode workspace. |
| ![Conversations Sidebar](.github/assets/image3.png) | **Sidebar Chat History**: Conveniently manage conversations. Supports renaming, archiving, and deletion. OpenCode streams are badged with a distinct blue `OC` icon. |
| ![OpenCode Settings](.github/assets/image4.png) | **OpenCode General Settings**: Toggle developer mode, verify/restart the local server engine, and auto-discover provider backends. |
| ![API Key Storage Settings](.github/assets/image5.png) | **Flexible API Key Storage & Prompts**: Switch credentials storage between Session-Only, Plain Config, or encrypted KWallet. |

---

##### 🎬 Video Walkthrough (6-Part Series)

*   [Part 0: Introduction & UI Walkthrough](https://github.com/user-attachments/assets/f46ac923-6602-4d05-aedc-a6a64f8fa7c8)
*   [Part 1: Multi-Provider & Model Selection](https://github.com/user-attachments/assets/6e2c8050-630a-4f1d-8efb-2d562754149f)
*   [Part 2: 3-Way API Key Storage](https://github.com/user-attachments/assets/a85601cf-f7ae-43ca-9c06-6eb78595d651)
*   [Part 3: Document & File Attachments](https://github.com/user-attachments/assets/8b93e6da-b40b-46f9-88f8-18be440bb6af)
*   [Part 4: OpenCode Developer Bridge](https://github.com/user-attachments/assets/c9a62f2b-240d-40ea-b785-e118f43c9780)
*   [Part 5: Settings Customizations & Chat Export](https://github.com/user-attachments/assets/3c65c3e9-b96d-482c-a471-9c54c5abc9fb)

---

## 🛠️ System Dependencies

| Feature | Required CLI Utility | Debian/Ubuntu | Arch Linux | Fedora |
| :--- | :--- | :--- | :--- | :--- |
| **PDF Reading** | `pdftotext` | `sudo apt install poppler-utils` | `sudo pacman -S poppler` | `sudo dnf install poppler-utils` |
| **Word Doc Reading** | `pandoc` | `sudo apt install pandoc` | `sudo pacman -S pandoc-cli` | `sudo dnf install pandoc` |
| **Secure KWallet** | `qdbus6` or `qdbus` | *Pre-installed* | *Pre-installed* | *Pre-installed* |
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
│       │   ├── translations.js   # Translation engine (11 languages)
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
1. **Chat Search**: Full-text search across all conversations and sessions.
2. **PDF Export**: Generate formatted, printable PDF logs of chats.
3. **Message Reactions / Ratings**: Thumbs up/down rating on AI responses for local feedback tracking.
4. **Prompt Templates**: Save and reuse frequently used prompts with one click.
5. **Token Counter**: Show estimated token count for the current chat context.
6. **Additional Providers**: Add community-requested local/remote models.

---

## License

GPL-2.0+ — See `metadata.json` for details.
