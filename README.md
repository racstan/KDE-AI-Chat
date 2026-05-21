# Kai Chat — Native KDE Plasma 6 AI Chat Widget

Native, highly responsive AI chat widget (plasmoid) for **KDE Plasma 6** and **Qt 6**. It features seamless multi-provider switching, real-time model discovery, session persistence, direct SSE streaming, and secure KWallet integration.

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

## Repository Structure (GitHub Public Portal)

To optimize distribution, the public GitHub repository serves as the official documentation, setup guide, and issue-tracking portal. The codebase is compiled directly into the production-ready `.plasmoid` distribution package, which is distributed solely through the official **KDE Store** and GitHub Releases.

The tracked files in this repository are:
```text
rachitkdeaichat/
├── README.md                      # Official landing portal and index
├── SETUP.md                       # Comprehensive credentials & provider API key setup guide
├── FORUSER.md                     # Release & packaging runbook (for developers)
├── audit.md                       # Detailed QA technical audit report
└── .gitignore                     # Git tracking safety filter
```

---

## Installation

Installing **Kai Chat** is seamless and does not require manual command-line execution or downloading source files.

### Option 1: Native One-Click Desktop Installation (Recommended)
1. Right-click your desktop background or Plasma panel and select **Add Widgets...**
2. Click **Get New Widgets** at the top, then select **Download New Plasma Widgets...**
3. In the search box, type **Kai Chat**.
4. Click the **Install** button.

*This automatically fetches and registers the verified distribution package from the KDE Store.*

### Option 2: Manual Package Installation
If you prefer to download the compiled `.plasmoid` bundle manually from the [KDE Store](https://store.kde.org/p/2153123) or the GitHub Releases tab:
1. Open your terminal in the directory where you downloaded the `.plasmoid` file.
2. Register the widget with Plasma:
   ```bash
   kpackagetool6 --type Plasma/Applet --install org.kde.plasma.kaichat-v3.1.plasmoid
   ```
3. Restart your Plasma shell to apply the changes:
   ```bash
   systemctl --user restart plasma-plasmashell.service
   ```
4. Add the widget by searching for **Kai Chat** in your Plasma Widget Explorer.

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
zip -r "dist/org.kde.plasma.kaichat-v3.1.plasmoid" org.kde.plasma.kaichat \
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
