# KDE AI Chat — Native KDE Plasma 6 AI Chat Widget

[![KDE Store](https://img.shields.io/badge/KDE%20Store-Download-blue?style=for-the-badge&logo=kde)](https://store.kde.org/p/2360152/) [![GitHub Release](https://img.shields.io/github/v/release/racstan/KDE-AI-Chat?style=for-the-badge&color=success)](https://github.com/racstan/KDE-AI-Chat/releases)

KDE AI Chat is a native, highly responsive desktop widget (plasmoid) built for KDE Plasma 6 and Qt 6. Designed as a lightweight, resource-efficient alternative to web wrappers and Electron applications, it integrates directly into the Plasma workspace. It provides multi-provider LLM support, native secure credentials storage, a background automation scheduler, local developer bridge integration, and offline-first data management.

---

## Technical Architecture and Design Philosophy

*   **Native Qt/QML Integration:** Built using Kirigami and Qt Quick Components. The widget automatically inherits active system themes, fonts, colors, rendering scales, and borders.
*   **Resource Efficiency:** Standalone operation consumes very low memory (typically 40–70 MB), avoiding the CPU and RAM overhead of Chromium/Electron runtimes.
*   **Privacy and Local Control:** Local history storage (stored in `~/.config` or custom paths) and keyless local integrations (Ollama, LM Studio) ensure data never leaves the system.

---

## Feature Details

### Multi-Provider Engine & Model Discovery
*   **21 Providers Supported:** Built-in integration for OpenAI, Anthropic (Claude), Google Gemini, DeepSeek, Groq, OpenRouter, Mistral, Cloudflare Workers AI, NVIDIA NIM, Hugging Face, xAI (Grok), LiteLLM Proxy, Qwen, Moonshot, MiMo, Maritaca, MiniMax, Fireworks AI, LM Studio, Ollama, and local OpenAI-compatible endpoints.
*   **Dynamic Endpoint Discovery:** Automatically queries host endpoints to discover available models for each provider.
*   **Searchable Model Selectors:** Includes a real-time searchable combobox to instantly filter and switch models in the active session.

### Chat Sidebar & Session History
*   **Native Sidebar:** Sidebar panel groups conversations chronologically (Today, Yesterday, Last Week, etc.).
*   **Session Operations:** Controls to rename, archive, or permanently delete chats.
*   **Badges:** 
    *   Blue `OC` badge indicates active OpenCode bridge sessions.
    *   Purple `FK` badge denotes a conversation split from a fork point.
    *   Numeric badges display unread background message counts, clearing immediately when the chat is opened.

### Chat Exporting
*   **Native File Export:** Export any active chat conversation to a local file. The widget saves the dialogue format cleanly as either a Markdown (`.md`) file or plaintext (`.txt`) file.
*   **Smart Naming Preset:** Automatically pre-fills the save dialog filename with the active chat session's title and the current date/time stamp for organized storage.
*   **Full Unicode Support:** Exports preserve all UTF-8 characters, custom code formatting, code blocks, system guidelines, and user prompts accurately.

### Text Formatting & Custom Markdown Parser
*   **Instant RichText Layouts:** Uses a custom, optimized, regular-expression-based JavaScript parser to convert standard Markdown to HTML.
*   **Zero UI Lag:** Offloads Qt's default Markdown layout builder to sub-millisecond RichText parsing, preventing desktop shell freezing during long code block streams.
*   **Formatting Support:** Renders bold, italics, headers, lists, links, inline code, and syntax-highlighted pre-formatted code block sections cleanly.

### Navigation and Scrolling Controls
*   **Quick Jump Buttons:** Toolbar navigation shortcuts are available to jump directly to the **First Message** (top of the thread) or **Last Message** (bottom of the thread) instantly.
*   **Prompt-by-Prompt Cycling:** Dedicated one message above and one message below arrow buttons let you navigate prompt-by-prompt through the viewport to trace conversation history easily.
*   **Clear Conversation:** A single-click clear button resets the active session, clearing the viewport and starting a fresh chat instance.
*   **Responsive Scroll Locking:** Intelligently locks scroll-to-bottom during active AI response generation, allowing users to scroll up freely to inspect earlier replies without snap fighting.
*   **Typing Metrics (Beta):** Real-time indicator displaying character and token estimation counts based on text length in the chat input.

### Branch Message Editing
*   **Non-Linear Editing:** Modifying any previous user prompt in the chat history automatically branches the conversation by deleting all subsequent dialogue lines and resubmitting from that specific timestamp, preventing context contamination.

### Conversation Forking (Beta)
*   **Message-Level Splitting:** Click the branch icon on any message bubble to fork the conversation into a new chat.
*   **Source Referencing:** Forked chats feature a banner pointing back to the parent chat, handling deleted parents gracefully.

### Drag-and-Drop File Attachments
*   **Off-Thread Parsing:** Paste or drag PDFs, CSVs, DOCX, and text files directly into the chat input.
*   **Tool-Based Extraction:** Integrates with local helpers (`pdftotext`, `pandoc`) to process and inject document content.
*   **Attachment-Only Inputs:** Allows submitting image/document queries without requiring typed text.

### Secure 3-Way Credentials Management
*   **Session-Only Storage:** Keys reside only in temporary volatile memory and discard on widget close.
*   **Plaintext Config:** Saves directly into local config files (`~/.config/kdeaichatrc`).
*   **Encrypted KWallet Vault:** Interacts via DBus commands (`org.kde.kwalletd6`) to store credentials inside the secure KDE Wallet system.

### Native AI Scheduler (systemd Daemon)
*   **Zero-Dependency Python Daemon:** Background daemon parses 5-field cron syntax (`kde-ai-scheduler.py`).
*   **Independent Context:** Runs schedule prompts against any API, keeping settings independent from the UI.
*   **GUI Control:** Stop, restart, or configure auto-start hooks directly in the widget settings.
*   **CRUD Schedule Manager:** Dialog for managing schedules with presets, API settings, and retention rules.
*   **Slash Command:** Type `/schedule` in chat to review execution stats.

### OpenCode Developer Bridge
*   **Local Workspace Integration:** Toggle OpenCode mode to establish an interactive connection between the widget and your local OpenCode environment. Renders interactive choice buttons, inline terminal/code block previews, and execution feedback directly within chat bubbles.
*   **External TUI Handling:** Note that MCPs, developer skills, agentic execution tools, and advanced workspace actions must be handled and managed through the native OpenCode TUI interface rather than directly within the plasmoid.

### User Memory Injection
*   **Persistent Facts:** Save custom developer guidelines or system info to append to the system prompt.

### i18n & RTL Mirroring (Beta)
*   **11 Language Dictionaries (Beta):** English, Arabic, Chinese, French, German, Hindi, Italian, Japanese, Portuguese, Russian, and Spanish.
*   **RTL Mirroring:** Mirrors layout interface elements dynamically when RTL languages are active.

---

## Showcase

### Screenshot Gallery

| Screenshot | Feature and Explanation |
| :--- | :--- |
| ![Live Chat UI](.github/assets/image.png) | **Native Chat UI**: conversational interface with rich Markdown support rendered instantly with smooth layout scrolling. |
| ![OpenCode Bridge](.github/assets/image2.png) | **OpenCode Developer Bridge**: Build an interactive execution link between the chat widget and your local OpenCode workspace. |
| ![Conversations Sidebar](.github/assets/image3.png) | **Sidebar Chat History**: manage conversations. Supports renaming, archiving, and deletion. |
| ![OpenCode Settings](.github/assets/image4.png) | **OpenCode General Settings**: Toggle developer mode, verify/restart the local server engine, and auto-discover provider backends. |
| ![API Key Storage Settings](.github/assets/image5.png) | **Flexible API Key Storage & Prompts**: Switch credentials storage between Session-Only, Plain Config, or encrypted KWallet. |

---

## System Dependencies

| Feature | Required CLI Utility | Debian/Ubuntu | Arch Linux | Fedora |
| :--- | :--- | :--- | :--- | :--- |
| **PDF Reading** | `pdftotext` | `sudo apt install poppler-utils` | `sudo pacman -S poppler` | `sudo dnf install poppler-utils` |
| **Word Doc Reading** | `pandoc` | `sudo apt install pandoc` | `sudo pacman -S pandoc-cli` | `sudo dnf install pandoc` |
| **Secure KWallet** | `qdbus6` or `qdbus` | *Pre-installed* | *Pre-installed* | *Pre-installed* |
| **Scheduler Daemon** | `systemctl` (user) | *Pre-installed* | *Pre-installed* | *Pre-installed* |
| **Desktop Alerts** | `notify-send` | `sudo apt install libnotify-bin` | `sudo pacman -S libnotify` | `sudo dnf install libnotify` |
| **Audio Alerts** | `pw-play` / `paplay` | `sudo apt install pipewire-audio` | `sudo pacman -S pipewire` | `sudo dnf install pipewire` |

---

## Installation

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
2. Run the local installation script:
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
├── SECURITY.md                   # Security policy
└── README.md                     # This file
```

---

## Contributing

Refer to [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines, testing workflows (including running the 39 python tests and QML linting), and style rules.

### Planned Roadmap
1. **Chat Search**: Full-text search across all conversations and sessions.
2. **PDF Export**: Generate formatted, printable PDF logs of chats.
3. **Message Reactions / Ratings**: Thumbs up/down rating on AI responses for local feedback tracking.
4. **Prompt Templates**: Save and reuse frequently used prompts with one click.
5. **Token Counter**: Show estimated token count for the current chat context.
6. **Additional Providers**: Add community-requested local/remote models.

---

## License

GPL-2.0+ — See `metadata.json` for details.
