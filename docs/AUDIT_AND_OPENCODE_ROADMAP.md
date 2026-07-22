# KDE AI Chat — Audit & OpenCode Enhancement Roadmap

## 1. 🔍 Comprehensive Audit: Current Capabilities ("What's There")

* **Native KDE Plasma 6 Desktop Integration**: Native QML Plasma widget (`main.qml`, `FullRepresentationContent.qml`) running in panel, desktop, or system tray mode. Includes global hotkeys (`Meta+Shift+A`), resizable geometry, and secure key encryption using KWallet via `Security.js`.
* **Multi-Provider AI Architecture**: Support for 15+ cloud & local AI providers in `ProviderService.js` (OpenAI, Anthropic Claude, Google Gemini, Groq, DeepSeek, OpenRouter, Mistral, Ollama, LM Studio, NVIDIA NIM, LiteLLM Proxy, and OpenCode).
* **OpenCode Developer Bridge**: Managed in `ChatEngine.js`. Connects to a local `opencode serve` instance over SSE, handling streaming tool calls, session sync, interactive security requests (`permission_request`), and interactive prompts (`question_request`).
* **Local Voice STT & TTS Engine**: Managed by `VoiceManager.qml` & `kde_ai_helper.py`. Uses `faster-whisper` for Speech-to-Text and `kokoro-onnx` for Text-to-Speech via systemd user daemons (`kde-ai-stt.service` / `kde-ai-tts.service`), complete with chat selection read-aloud and a global speech interrupt button (`■`).
* **File Drag & Drop Extractor**: Python background extractor (`doc_extractor.py`) for PDF parsing (`pdftotext`), DOCX (`pandoc`), Vision images, CSVs, and code files.
* **Task Scheduler & Automation**: Native background task runner in `ScheduleDialog.qml` leveraging systemd timers for periodic AI prompt executions and desktop notifications.
* **Prompt Templates & Chat UX**: Quick slash-command prompt templates (`/<name>`), chat rewinding/editing, session history export (`.md`/`.txt`), smooth QML list view scrolling, and a process/memory monitor (`ConfigOther.qml`).

---

## 2. ⚠️ Gaps & Missing Features ("What's Missing")

1. **[COMPLETED] Visual Git Diff Inspector**: Added red/green line syntax highlighting for diff/patch code blocks.
2. **[COMPLETED] OpenCode Workspace Directory Selector**: Added folder picker button (`📁 Workspace`) to select local project directories (`--cwd`).
3. **[COMPLETED] OpenCode Agent Profile Selection**: Added toolbar sub-agent dropdown selector (`Coder`, `Architect`, `Reviewer`, `Explorer`, `Ask`).
4. **No Full-Duplex Continuous Voice Mode**: Voice interaction requires manually pressing the mic button per turn rather than a continuous hands-free voice conversation.
5. **[COMPLETED] Direct Screen Region Capture (Spectacle)**: Added interactive camera region capture button directly into the chat prompt toolbar.
6. **[COMPLETED] Direct Terminal Session Attach & Sync Button**: In OpenCode mode, users can open the current session in Konsole/terminal and sync external CLI session history.

---

## 3. 💡 Features Users Would Love

* 📸 **Spectacle Screen Capture Integration**: Add a camera icon to the message input box. Clicking it triggers Spectacle (`spectacle -r -b -n`), grabs the screen snippet, attaches it, and lets users immediately ask *"Explain this error"* or *"Refactor this UI design"*.
* ⚡ **"Ask AI on Desktop Selection" Hotkey**: A global Plasma shortcut (`Meta+Shift+S`) that grabs highlighted desktop text via X11/Wayland clipboard, opens the plasmoid, and automatically runs a prompt like *"Summarize this text"* or *"Fix this code snippet"*.
* 🔍 **Interactive Red/Green Visual Git Diff Cards**: Render file modifications made by OpenCode in a diff UI component with single-click **"Accept Edits"** or **"Revert File"** buttons.
* 📂 **Active Workspace / Repo Switcher Dropdown**: A project selector pill in the header showing the current Git branch and working directory, letting users easily switch projects.
* 🤖 **OpenCode Agent Profile Pill**: A toolbar toggle allowing users to quickly switch agent modes (`Default Agent`, `Architect`, `Code Reviewer`, `Fast Explorer`).
* 📊 **Session Token Usage & Cost Counter**: A subtle badge showing total tokens used (input/output) and estimated API cost per session for cloud providers.
* 🔔 **Interactive System Notifications**: Rich KDE desktop notifications for completed background scheduler tasks or long-running OpenCode tasks, featuring quick actions like **"View Diff"**, **"Open Session"**, or **"Dismiss"**.

---

## 4. 🚀 Betterment of the Application via OpenCode

```
                       ┌──────────────────────────────────────────┐
                       │           KDE AI Chat Plasmoid           │
                       │     (QML / Plasma 6 Desktop UI)          │
                       └──────────────────┬───────────────────────┘
                                          │
                  ┌───────────────────────┴───────────────────────┐
                  ▼                                               ▼
   ┌──────────────────────────────┐               ┌──────────────────────────────┐
   │    OpenCode Agent Engine     │               │  KDE Desktop System Bridge   │
   │   (REST / SSE Server API)    │               │  (DBus / Spectacle / KDoct)  │
   └──────────────┬───────────────┘               └──────────────┬───────────────┘
                  │                                              │
    ┌─────────────┼──────────────┐                 ┌─────────────┴──────────────┐
    ▼             ▼              ▼                 ▼                            ▼
┌───────┐   ┌───────────┐   ┌─────────┐   ┌─────────────────┐         ┌───────────────────┐
│ Tools │   │ Workspace │   │ Async   │   │ System Control  │         │ Screenshot / OCR  │
│ & MCP │   │  Context  │   │ Tasks   │   │ (Volume, Theme) │         │ (Spectacle / DBus)│
└───────┘   └───────────┘   └─────────┘   └─────────────────┘         └───────────────────┘
```

### A. Direct Session Sync & Terminal Attach
* OpenCode stores session state in local databases/server API.
* Allow launching terminal app (Konsole / default terminal) attached to the current OpenCode session ID (`opencode session attach <id>` or `opencode --session <id>`).
* Provide a **Sync** button in the QML interface to pull messages and edits made to the session from CLI/external clients into the widget.

### B. KDE Desktop Control via Custom OpenCode Tools / MCP
* Register custom tools via `.opencode/tools/` or Model Context Protocol (MCP) servers:
  * `kde_spectacle`: Take screenshot of region or active window.
  * `kde_dbus_control`: Toggle dark/light theme (`plasma-apply-colorscheme`), change system audio volume, switch Plasma activity/virtual desktop.
  * `kde_system_info`: Inspect CPU load, RAM usage, process list (`psaux`/`top`).

### C. Asynchronous Background Agent Tasks with System Tray Progress
* Launch asynchronous OpenCode agent sessions and render a dynamic progress ring on the KDE system tray icon while displaying real-time step notifications via `KNotification`.

### D. Enhanced Interactive Security & Permission Cards
* Enhance OpenCode's `permission_request` system in QML. Display exact command breakdowns, security risk indicators (**Low / Medium / High**), path safety highlights, and command execution previews before the user clicks "Allow".

### E. Workspace File Tree & Git Status Drawer
* Leverage OpenCode's indexing to add a collapsible **Workspace Drawer** to the QML interface displaying the project file tree, active Git branch, uncommitted modified files, and recently edited files.
