# KDE AI Chat — Scheduling System Design

> Version: 1.0  
> Status: Implemented  
> Scope: Provider-agnostic, OpenCode-independent, KDE-native

---

## 1. Problem Statement

The widget supports 20+ AI providers (OpenAI, Anthropic, Groq, Gemini, Mistral, Ollama, etc.), all using OpenAI-compatible REST APIs. A scheduling system must work **across all of them uniformly**, without any dependency on OpenCode or any specific provider.

**Hard constraints:**
- ❌ Must NOT depend on OpenCode
- ❌ Must NOT depend on any single provider
- ❌ Must NOT rely solely on QML Timers (stopped when widget is unloaded)
- ✅ Must work while the widget is closed / user is away
- ✅ Must be installable as part of the widget (no separate manual setup)
- ✅ Must be maintainable by contributors (simple, documented, modular)
- ✅ Must integrate naturally with KDE (notifications, theming, file paths)

---

## 2. Architecture Decision

### Chosen Stack

```
┌──────────────────────────────────────────────────────────────────┐
│                    KDE AI Chat Widget (QML)                      │
│  Schedule Manager UI  ←→  File-based IPC  ←→  Results Viewer    │
└──────────────────┬───────────────────────────────────────────────┘
                   │ reads/writes
                   ▼
         ~/.local/share/kdeaichat/
         ├── schedules.json          ← Schedule definitions
         ├── results/                ← AI response outputs
         │   └── {uuid}.json
         └── scheduler.lock          ← PID lock (daemon health check)

┌──────────────────────────────────────────────────────────────────┐
│               kde-ai-scheduler  (Python daemon)                  │
│   Runs as systemd user service — completely independent          │
│   Parses cron expressions → calls provider REST APIs directly    │
│   Writes results → sends KDE desktop notifications               │
└──────────────────────────────────────────────────────────────────┘
```

### Why a Python daemon + file-based IPC?

| Alternative | Why Rejected |
|---|---|
| QML Timer only | Dies when widget closes. Useless for "run at 9am daily" |
| D-Bus custom interface | Requires D-Bus service registration, complex for contributors |
| Node.js sidecar | Extra runtime dependency, overkill for this scope |
| SQLite database | Heavier than needed; JSON is human-readable and git-friendly |
| Pure systemd timers | One timer per schedule = N service files; unmanageable |

**Python daemon wins** because:
- Python is universally available on Linux desktops
- Standard library only (`urllib`, `json`, `re`, `signal`, `os`) — zero pip dependencies
- One systemd service manages all schedules dynamically
- File-based IPC is simple, debuggable, and contributor-friendly
- The widget already ships a Python file (`doc_extractor.py`), establishing precedent

---

## 3. File Layout

```
org.kde.plasma.kdeaichat/
├── contents/
│   ├── ui/
│   │   ├── main.qml
│   │   ├── ConfigGeneral.qml
│   │   ├── ScheduleDialog.qml       ← Schedule CRUD UI (Active, Archived, History tabs)
│   │   └── translations.js
│   ├── scripts/
│   │   └── kde-ai-scheduler.py      ← The daemon
│   └── config/
│       └── main.xml
├── install.sh                        ← Updated: installs systemd service
└── docs/
    └── scheduling-system-design.md   ← This file
```

**Runtime paths (XDG-compliant):**
```
~/.local/share/kdeaichat/
├── schedules.json          ← Schedule definitions + run history
├── scheduler.lock          ← PID lock (daemon health check)
└── pending/
    └── {uuid}-{timestamp}.json  ← Trigger files (daemon → widget)

~/.config/systemd/user/
└── kde-ai-scheduler.service          ← Installed by install.sh
```

---

## 4. Data Models

### 4.1 `schedules.json` — Schedule Definitions

```json
{
  "version": 1,
  "schedules": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "name": "Daily standup summary",
      "enabled": true,
      "cron": "0 9 * * 1-5",
      "prompt": "Summarize what I should focus on today based on current context.",
      "systemPrompt": "You are a concise productivity assistant.",
      "provider": "openai",
      "baseUrl": "https://api.openai.com/v1",
      "model": "gpt-4o-mini",
      "apiKey": "__FROM_WALLET__",
      "maxTokens": 500,
      "notify": true,
      "notifyTitle": "Daily Standup Ready",
      "saveResults": true,
      "keepResultDays": 30,
      "createdAt": "2026-05-31T08:00:00Z",
      "lastRunAt": "2026-05-31T09:00:00Z",
      "lastRunStatus": "success",
      "nextRunAt": "2026-06-01T09:00:00Z"
    }
  ]
}
```

**Field reference:**

| Field | Type | Description |
|---|---|---|
| `id` | UUID string | Unique identifier, never changes |
| `name` | string | Human-readable label |
| `enabled` | bool | Whether the daemon should run this |
| `cron` | string | Standard 5-field cron expression |
| `prompt` | string | The user message sent to the AI |
| `systemPrompt` | string | Optional override of the global system prompt |
| `provider` | string | Provider key (matches main.xml entries) |
| `baseUrl` | string | API base URL for the provider |
| `model` | string | Model ID string |
| `apiKey` | string | `"__FROM_WALLET__"` = read from KWallet; or plaintext |
| `maxTokens` | int | Response token limit |
| `notify` | bool | Send a KDE desktop notification on completion |
| `notifyTitle` | string | Notification title (defaults to schedule name) |
| `saveResults` | bool | Write AI response to results directory |
| `keepResultDays` | int | Auto-delete results older than N days |
| `lastRunAt` | ISO8601 | Timestamp of last execution |
| `lastRunStatus` | string | `"success"`, `"error"`, `"skipped"` |
| `nextRunAt` | ISO8601 | Calculated by daemon after each run |

### 4.2 `results/{uuid}-{timestamp}.json` — Run Results

```json
{
  "scheduleId": "550e8400-e29b-41d4-a716-446655440000",
  "scheduleName": "Daily standup summary",
  "ranAt": "2026-05-31T09:00:02Z",
  "status": "success",
  "prompt": "Summarize what I should focus on today...",
  "response": "Here's your standup summary for Monday...",
  "provider": "openai",
  "model": "gpt-4o-mini",
  "tokensUsed": 312,
  "durationMs": 1840,
  "error": null
}
```

---

## 5. The Daemon — `kde-ai-scheduler.py`

### Lifecycle

```
systemd start
    ↓
Load schedules.json
    ↓
Calculate next run time for each enabled schedule
    ↓
Main loop (sleep 30s between ticks):
    For each schedule:
        if now >= nextRunAt:
            → call AI API (urllib, no deps)
            → write result JSON
            → send KDE notification (notify-send / D-Bus)
            → update lastRunAt, nextRunAt in schedules.json
    ↓
On SIGHUP: reload schedules.json (hot reload — no restart needed)
On SIGTERM: clean shutdown
```

### Cron Expression Parser

A minimal 5-field cron parser (no external deps) covering the real-world subset needed:

```
minute  hour  day-of-month  month  day-of-week
  0      9          *          *       1-5        (weekdays at 9am)
  0      */4        *          *        *          (every 4 hours)
  30     8          1          *        *          (1st of month at 8:30am)
```

Supported syntax:
- `*` — any value
- `*/n` — every n units
- `a-b` — range
- `a,b,c` — list
- Named weekdays: `mon`, `tue`, `wed`, `thu`, `fri`, `sat`, `sun`

### API Call — Zero External Dependencies

```python
import urllib.request, json

def call_ai(base_url, api_key, model, system_prompt, user_prompt, max_tokens):
    url = base_url.rstrip("/") + "/chat/completions"
    payload = json.dumps({
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user",   "content": user_prompt}
        ],
        "max_tokens": max_tokens,
        "stream": False
    }).encode()
    
    req = urllib.request.Request(url, data=payload, headers={
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    })
    
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read())
    
    return data["choices"][0]["message"]["content"]
```

This works with **every provider in the project** because they all expose OpenAI-compatible `/chat/completions`.

### KDE Notification

```python
import subprocess

def notify(title, body, icon="dialog-information"):
    subprocess.run([
        "notify-send",
        "--app-name=KDE AI Chat",
        "--icon=" + icon,
        "--urgency=normal",
        title,
        body
    ], check=False)
```

### Hot Reload (SIGHUP)

```python
import signal

def handle_sighup(signum, frame):
    global schedules
    schedules = load_schedules()  # re-read file, no restart needed

signal.signal(signal.SIGHUP, handle_sighup)
```

The widget sends `kill -HUP <daemon_pid>` (read from `scheduler.lock`) after saving schedule changes. The daemon reloads instantly.

---

## 6. systemd User Service

**`~/.config/systemd/user/kde-ai-scheduler.service`** (written by `install.sh`):

```ini
[Unit]
Description=KDE AI Chat Scheduler Daemon
Documentation=https://github.com/rachit-k/KDE-AI-Chat
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/share/kdeaichat/kde-ai-scheduler.py
Restart=on-failure
RestartSec=30
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kde-ai-scheduler

[Install]
WantedBy=default.target
```

**Why user service?**
- Runs under the user's account → has access to their API keys and config
- No root/sudo required
- Starts automatically on login via `WantedBy=default.target`
- Logs visible via `journalctl --user -u kde-ai-scheduler`

**Daemon management commands:**
```bash
systemctl --user enable --now kde-ai-scheduler   # start + persist on login
systemctl --user status kde-ai-scheduler         # check status
systemctl --user restart kde-ai-scheduler        # restart after update
journalctl --user -u kde-ai-scheduler -f         # live logs
```

---

## 7. Widget Integration

### 7.1 ScheduleManager.qml — New Tab in Settings

The schedule management UI lives as a new tab in `ConfigGeneral.qml`:

```
Settings
├── General
├── Providers
├── OpenCode
└── Schedules  ← NEW
    ├── [+ New Schedule] button
    ├── Schedule list (name, cron, provider, enabled toggle, run now, delete)
    └── Schedule editor panel (opens on click/new)
        ├── Name field
        ├── Prompt textarea
        ├── Provider dropdown (inherits widget's configured providers)
        ├── Model field
        ├── Cron expression field + human-readable preview
        ├── Notification toggle
        └── Save / Cancel
```

### 7.2 ScheduleResultViewer.qml — In the Main Chat UI

A floating panel or sidebar accessible from the chat header:

```
[Chat]  [History]  [Scheduled Results]  ← new tab
            ↕
    Daily standup summary — 31 May, 09:00
    ─────────────────────────────────────
    "Here's your standup for today: ..."
    [Copy]  [Open in Chat]
```

The "Open in Chat" button loads the result as an assistant message in a new chat session.

### 7.3 QML ↔ Daemon Communication

The widget uses **file-based IPC** — no sockets, no D-Bus custom interface:

| Operation | How |
|---|---|
| Widget saves schedules | Writes `schedules.json`, then `kill -HUP <pid>` from lock file |
| Widget reads results | Reads `results/*.json`, sorted by timestamp |
| Widget checks daemon health | Checks if PID in `scheduler.lock` is alive |
| "Run now" button | Appends a `"triggerNow": true` flag to the schedule entry → daemon picks it up on next tick (≤30s) |
| Daemon writes results | Widget's QML `FileIO` component watches the results directory |

### 7.4 File Watching in QML

```qml
// Poll results directory every 60 seconds while widget is open
Timer {
    id: resultPollTimer
    interval: 60000
    running: true
    repeat: true
    onTriggered: schedulerBridge.refreshResults()
}
```

---

## 8. Security Considerations

### API Key Handling

The daemon must access API keys. Priority order:

1. **KWallet** (when `apiKey == "__FROM_WALLET__"`): The daemon uses `kwallet-query` CLI or D-Bus to read the key at runtime
2. **Plaintext in schedules.json** (fallback): Acceptable since file permissions are `600` (user-only)
3. **Environment variable**: `KDE_AI_APIKEY_<PROVIDER>` — allows secrets managers

```python
def resolve_api_key(schedule):
    if schedule["apiKey"] == "__FROM_WALLET__":
        return kwallet_query(schedule["provider"])
    return schedule["apiKey"]
```

### File Permissions

`install.sh` sets:
```bash
chmod 700 ~/.local/share/kdeaichat/
chmod 600 ~/.local/share/kdeaichat/schedules.json
chmod 600 ~/.local/share/kdeaichat/results/*.json
```

---

## 9. `install.sh` Changes

The existing `install.sh` needs additions:

```bash
# 1. Copy daemon to data directory
mkdir -p ~/.local/share/kdeaichat/results/
cp contents/scripts/kde-ai-scheduler.py ~/.local/share/kdeaichat/
chmod +x ~/.local/share/kdeaichat/kde-ai-scheduler.py
chmod 700 ~/.local/share/kdeaichat/

# 2. Install systemd user service
mkdir -p ~/.config/systemd/user/
cat > ~/.config/systemd/user/kde-ai-scheduler.service << 'EOF'
[Unit]
Description=KDE AI Chat Scheduler Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=%h/.local/share/kdeaichat/kde-ai-scheduler.py
Restart=on-failure
RestartSec=30

[Install]
WantedBy=default.target
EOF

# 3. Enable and start the service
systemctl --user daemon-reload
systemctl --user enable --now kde-ai-scheduler

echo "✓ KDE AI Chat Scheduler installed and running."
```

---

## 10. Contributor Guide

### Adding a Feature to the Scheduler

The daemon is intentionally small (~300 lines). Key areas:

| File | Responsibility |
|---|---|
| `kde-ai-scheduler.py` | Cron parsing, API calls, file writes, notifications |
| `ScheduleManager.qml` | Create/edit/delete schedule definitions |
| `ScheduleResultViewer.qml` | Display past results inside the widget |
| `schedules.json` | The source of truth (human-editable) |

### Cron Expression Validation

Provide real-time feedback in the UI as the user types a cron expression.  
The QML side can call a helper endpoint or do basic regex validation client-side.

### Testing the Daemon

```bash
# Run directly (not via systemd) for development
python3 ~/.local/share/kdeaichat/kde-ai-scheduler.py --debug

# Check logs
journalctl --user -u kde-ai-scheduler -f

# Force immediate run of a schedule (set triggerNow in schedules.json)
# The daemon picks it up within 30 seconds
```

---

## 11. Milestones

| Phase | Deliverable | Files Affected |
|---|---|---|
| **P1** | Core daemon with cron parsing + API calls | `kde-ai-scheduler.py` |
| **P2** | systemd service + install.sh integration | `install.sh`, `.service` |
| **P3** | Schedule Manager UI (settings tab) | `ScheduleManager.qml`, `ConfigGeneral.qml` |
| **P4** | Result Viewer UI (chat panel) | `ScheduleResultViewer.qml`, `main.qml` |
| **P5** | KWallet integration for API keys | `kde-ai-scheduler.py` |
| **P6** | i18n: add scheduling strings to `translations.js` | `translations.js` |

---

## 12. What This Is NOT

To keep scope clear:

- ❌ Not a full workflow automation engine (use n8n/Zapier for that)
- ❌ Not a multi-machine scheduler
- ❌ Not dependent on OpenCode, Claude, or any specific provider
- ❌ Not using `pip` or any external Python packages
- ❌ Not requiring root or system-level permissions
