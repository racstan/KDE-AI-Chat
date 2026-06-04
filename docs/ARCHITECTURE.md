# KDE AI Chat — Architecture Overview

This document describes the internal architecture of the KDE AI Chat plasmoid for developers and contributors.

## High-Level Architecture

KDE AI Chat is a **KDE Plasma 6 widget (plasmoid)** built with **QML** and **JavaScript**, with supplementary **Python 3** scripts for document extraction and scheduling.

```
┌─────────────────────────────────────────────────────┐
│                  Plasma Desktop Shell                │
│  ┌───────────────────────────────────────────────┐  │
│  │         KDE AI Chat Plasmoid                  │  │
│  │  ┌─────────────────────┐ ┌──────────────────┐ │  │
│  │  │   main.qml          │ │ ConfigGeneral.qml│ │  │
│  │  │   (Chat UI, SSE,    │ │ (Settings,       │ │  │
│  │  │    Sessions, Bridge) │ │  Providers,      │ │  │
│  │  └─────────────────────┘ │  KWallet,         │ │  │
│  │                          │  OpenCode,        │ │  │
│  │  ┌─────────────────────┐ │  Scheduler)      │ │  │
│  │  │ ScheduleDialog.qml  │ └──────────────────┘ │  │
│  │  │ (Schedule CRUD UI)  │                      │  │
│  │  └─────────────────────┘                      │  │
│  └───────────────────────────────────────────────┘  │
│                         │ IPC                        │
│  ┌───────────────────────────────────────────────┐  │
│  │  doc_extractor.py  │  kde-ai-scheduler.py     │  │
│  │  (File extraction) │  (Cron daemon + systemd) │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Package Structure

```
org.kde.plasma.kdeaichat/           # KDE KPackage root
├── metadata.json                   # Plasmoid manifest
└── contents/
    ├── config/
    │   ├── main.xml                # KConfigXT schema (~70 settings)
    │   └── config.qml              # Settings tab registration
    ├── ui/
    │   ├── main.qml                # Core chat widget
    │   ├── ConfigGeneral.qml       # Settings panel
    │   ├── ScheduleDialog.qml      # Schedule editor
    │   ├── translations.js         # Translation engine
    │   ├── translations_*.js       # 11 language dictionaries
    │   └── doc_extractor.py        # File attachment extraction
    └── scripts/
        └── kde-ai-scheduler.py     # Scheduling daemon
```

## Core Components

### 1. `main.qml` — Main Widget Interface

The primary UI file. It handles:

- **Chat Display**: Renders message bubbles with Markdown support, model labels, timestamps.
- **SSE Streaming**: Uses `XMLHttpRequest` with `onprogress` events for real-time AI response streaming.
- **Session Management**: Create, switch, rename, archive, delete sessions via in-memory array persisted through KConfigXT.
- **OpenCode Bridge**: REST API client connecting to the local OpenCode server (`/v1/session`, `/v1/event` SSE, etc.).
- **Conversation Forking**: Editing a past user message truncates subsequent messages and re-sends.
- **Schedule Injection**: Polls `~/.local/share/kdeaichat/pending/` for trigger files from the scheduler daemon.
- **File Attachments**: Drag-and-drop and paste support invoking `doc_extractor.py`.
- **Token Diagnostics**: Real-time token usage and cost display on assistant bubbles.
- **Chat Export**: Export conversations as Markdown or plain text via a download dialog.

### 2. `ConfigGeneral.qml` — Settings Panel

The configuration UI registered as `KCM.SimpleKCM`. It handles:

- **Provider Selection**: Dropdown of 21 AI providers with per-provider URL, API key, and model fields.
- **3-Way Key Storage**: Session-only, plain config file, or KWallet (DBus) storage.
- **KWallet Operations**: Detect wallets, create folders, read/write/delete keys via `qdbus6`.
- **Model Discovery**: REST API calls to `/v1/models` endpoints for dynamic model listing.
- **OpenCode Configuration**: Server URL, provider/model selection, start/stop commands, auto-start.
- **Scheduler Management**: Enable/disable, auto-start, run history viewing.
- **Appearance**: Light/dark/system theme selection.
- **Interactive Guides**: Context-aware setup guides for each section.

### 3. `ScheduleDialog.qml` — Schedule Editor

A full CRUD UI for managing scheduled AI prompts:

- Create, edit, and delete scheduled prompts (single-run or recurring).
- Configure cron-based recurrence (minutes, hours, days, weeks, months).
- Set execution limits for recurring schedules.
- View run history (up to 100 entries) and clear it.
- Archive/restore schedules without deleting them.

### 4. `translations.js` — Translation Engine

Loads 11 language dictionaries and provides the `translate()` function. Features:

- Dynamic pattern matching for provider-specific fields (key, URL, model labels).
- Falls back to English when a translation key is missing.
- Language selection via config or system locale detection.

### 5. `doc_extractor.py` — File Attachment Extractor

A Python 3 script invoked for file and clipboard content extraction:

- **PDF**: Uses `pdftotext` (poppler-utils).
- **Word documents**: Uses `pandoc` with fallback to direct XML parsing.
- **Images**: Returns base64-encoded image data for inline display.
- **Text files**: Reads CSV, JSON, XML, YAML, JS, TS, PY, SH, HTML, CSS and plain text.
- **Clipboard**: Detects file URIs, images, or text from Wayland (`wl-paste`) or X11 (`xclip`).

### 6. `kde-ai-scheduler.py` — Scheduling Daemon

A Python 3 systemd user service that:

- Reads `~/.local/share/kdeaichat/schedules.json` for schedule definitions.
- Parses cron expressions (5-field standard format).
- Runs every 15 seconds (tick interval) checking for due schedules.
- Writes pending trigger JSON files to `~/.local/share/kdeaichat/pending/`.
- Supports single-run and recurring tasks with execution limits.
- Maintains a run history (up to 100 entries) inside `schedules.json`.
- Responds to SIGHUP to reload schedules without restart.

### 7. `config.qml` — Settings Tab Registration

Simple mapping file that registers `ConfigGeneral.qml` as the settings UI page for the plasmoid. Required by the KDE Plasma configuration framework.

## Data Flow

### Chat Message Flow (Normal Mode)

```
User types message
       │
       ▼
main.qml: appendUserMessage()
       │
       ▼
main.qml: sendMessageByIndex()
       │
       ▼
XMLHttpRequest POST → AI Provider API (/chat/completions)
       │
       ▼
SSE stream via onprogress → updateAssistantStreamingContent()
       │
       ▼
Messages displayed in chat view
       │
       ▼
persistSessions() → KConfigXT (+ optional customHistoryPath)
```

### Chat Message Flow (OpenCode Bridge Mode)

```
User types message
       │
       ▼
main.qml: ensureCurrentOpenCodeSession() → POST /v1/session
       │
       ▼
main.qml: doOpenCodeRequest() → POST /v1/session/{id}/message
       │
       ▼
SSE events via /v1/event → handleOpenCodeEvent()
  ├─ message.part.updated → Streaming token updates
  ├─ question.asked → Renders interactive question buttons
  ├─ permission.asked → Renders permission approve/deny buttons
  └─ session.idle → finishOpenCodeRequest()
```

### Schedule Trigger Flow

```
kde-ai-scheduler.py (tick every 15s)
       │
       ▼
Cron match? → Write pending/*.json
       │
       ▼
main.qml: pollTimer → Read pending/ directory
       │
       ▼
injectScheduledMessage() → appendUserMessage() → sendMessageByIndex()
```

## Configuration System

All persistent settings use **KConfigXT** defined in `contents/config/main.xml` (~70 entries). Settings are stored in `~/.config/kdeaichatrc` by default.

Key configuration groups:
- **Provider settings**: URL, API key, model for each of 21 providers
- **OpenCode settings**: Server URL, provider, model, auto-start, start/stop commands
- **KWallet settings**: Wallet name, storage mode
- **Scheduler settings**: Enabled, auto-start
- **UI settings**: Appearance mode, popup dimensions, notification sound, zoom
- **Chat settings**: System prompt, custom history path, language

## IPC Mechanisms

| Mechanism | Purpose |
|-----------|---------|
| **KConfigXT** | Widget settings persistence |
| **DBus (qdbus6)** | KWallet read/write operations |
| **Pending files** | Scheduler → Widget communication |
| **stdout/stderr** | Python script output to QML `DataSource` |
| **XMLHttpRequest** | AI provider and OpenCode REST API calls |
| **SSE (EventSource)** | Real-time streaming from OpenCode server |

## Security Architecture

See [SECURITY.md](SECURITY.md) for details on:

- 3-Way API key storage (session, config file, KWallet)
- Base64 encoding for shell command payloads
- DBus input sanitization via `applyLoadedKey()`
- File permission hardening for scheduler data
