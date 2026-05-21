# KDE AI Chat — Native KDE Plasma 6 AI Chat Widget

Native, highly responsive AI chat widget (plasmoid) for **KDE Plasma 6** and **Qt 6**. It features seamless multi-provider switching, real-time model discovery, session persistence, direct SSE streaming, and secure KWallet integration.

---

![KDE AI Chat Main View](.github/assets/image.png)
![KDE AI Chat Settings](.github/assets/image2.png)
![KDE AI Chat History](.github/assets/image3.png)
![Model Discovery](.github/assets/image4.png)
![OpenCode Server Status](.github/assets/image5.png)

---

## Key Features

- **Multi-Provider Switching**: Native integration with OpenAI, Anthropic (Claude), Groq, DeepSeek, Google Gemini, OpenRouter, Mistral, Cloudflare Workers AI, NVIDIA, Hugging Face, xAI (Grok), LM Studio, and generic local OpenAI-compatible endpoints.
- **Dynamic Model Discovery**: Auto-detects and populates model lists directly from API endpoints, featuring a real-time searchable combobox.
- **Local Priority (OpenCode Mode)**: Special developer-priority mode with server process control (Start/Stop/Kill controls directly from settings).
- **Session History Manager**: Persistence layer supporting creating, renaming, archiving, and deleting chat threads, categorized with elegant date groupings.
- **Premium UX**: Markdown parsing, multi-line auto-resizing text fields, and smooth keyboard shortcuts (Ctrl+Enter to send, arrow keys to navigate history).
- **Secure KWallet Storage**: Secure DBus credential loading to prevent exposing raw API keys in plain text.
- **Popup Canvas Scaling**: Custom bottom-right drag-to-resize handle that persists coordinates natively via KConfigXT backend.
- **Theme Compliant**: Perfectly adapts to Dark and Light modes, supporting custom pinning (Light/Dark/Follow system).

---

## Codebase Quality & Audit Status

As of **May 21, 2026**, the codebase has undergone a comprehensive structural audit and is marked **100% production-ready**:
- **Diagnostic Safety**: The codebase successfully compiles and passes QML structural analysis using the KDE diagnostic suite (`qmllint`) with **zero errors and zero warnings**.
- **Security Hardening**: Secure DBus transactions with DBus filters in `applyLoadedKey` to prevent status warnings from entering input fields.
- **Immaculate Directory**: All pre-production developer notes, scratchpads, and unused file assets (such as `steps.txt`, `PLASMA6_WIDGET_DOCS.md`, and the redundant `apiWorker.mjs` file) have been removed for clean packaging.

---

## Repository Structure

**Kai Chat** is 100% open-source. The repository is organized under a standard KDE Plasma KPackage layout, allowing developers to audit, run diagnostic linters, and build from source:

```text
kai-chat/
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

You can install **Kai Chat** either directly through your desktop interface (recommended for general users) or build it directly from source (for developers and power users).

### Option 1: Native Desktop Installation (Recommended)
1. Right-click your desktop background or the Plasma panel and select **Add Widgets...**
2. Click **Get New Widgets** -> **Download New Plasma Widgets...**
3. In the search box, search for **"Kai Chat"** and click **Install**.

*This automatically fetches and registers the pre-compiled, verified release package from the KDE Store.*

### Option 2: Clone and Install from Source (For Developers)
If you want to run the latest development build or customize the source files:
1. Clone the open-source repository:
   ```bash
   git clone https://github.com/racstan/kai-chat.git
   cd kai-chat
   ```
2. Run the one-click local installation script:
   ```bash
   ./install.sh
   ```
3. Restart your Plasma shell to apply changes and register the widget:
   ```bash
   systemctl --user restart plasma-plasmashell.service
   ```
4. Right-click your desktop/panel, select **Add Widgets...**, search for **Kai Chat**, and drag it onto your screen!

---

## Technical Audit & Quality Control

Every package release is built following a rigorous QA checklist. The code is audited to verify:
- **Syntax Integrity**: Compiles with `qmllint` showing 0 warnings and 0 errors.
- **Security Protocols**: Safe DBus API key storage with input sanitization to protect user credentials.
- **Process Robustness**: Resizing coordinates persist natively across system sessions, and long-running API tasks execute strictly off-thread to ensure the Plasma desktop shell remains 100% fluid.

For detailed analysis, refer to the [Technical Audit Report](file:///home/home/Programming/rachitkdeaichat/audit.md).

---

## Build & Publishing Flow (For Developers)

For developers packaging the widget from local sources, standard procedures are detailed in the [Release Operator Playbook](file:///home/home/Programming/rachitkdeaichat/FORUSER.md). Building the distribution archive requires zipping the QML package structure:

```bash
# Compress the QML folder into a Plasma-compliant .plasmoid archive
zip -r "dist/org.kde.plasma.kdeaichat-v3.1.plasmoid" org.kde.plasma.kdeaichat \
  -x "*.git*" "*__pycache__*" "*.DS_Store"
```

---

## Documentation Guides

- [End-User Setup & API Keys Guide](file:///home/home/Programming/rachitkdeaichat/SETUP.md) — Comprehensive guide on creating accounts and retrieving keys for all 13 providers.
- [Technical Audit & Code Quality Report](file:///home/home/Programming/rachitkdeaichat/audit.md) — Detailed results of the May 2026 quality assurance audit.
- [Release Operator Playbook](file:///home/home/Programming/rachitkdeaichat/FORUSER.md) — Bumping versioning, tag management, and release steps.

---

## License

GPL-2.0+ — See `metadata.json` for licensing specs.
