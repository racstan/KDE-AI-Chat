# KDE AI Chat — Final Deep Audit

**Date:** 2026-06-04
**Version audited:** 1.3.0
**Repository:** <https://github.com/racstan/KDE-AI-Chat>
**Auditor:** Automated deep code audit

---

## 1. Executive Summary

KDE AI Chat is a KDE Plasma 6 plasmoid providing multi-provider LLM chat on the desktop. While the project demonstrates strong engineering in its CI pipeline, zero-dependency Python layer, and security-conscious key storage, there are remaining issues in code architecture and some security hardening areas.

**High: 1 | Medium: 8 | Low: 4 | Informational: 6**

---

## 2. Project Structure

```
.
├── org.kde.plasma.kdeaichat/
│   ├── metadata.json
│   └── contents/
│       ├── config/
│       │   ├── main.xml                # KConfigXT schema (~70 settings, 327 lines)
│       │   └── config.qml
│       ├── ui/
│       │   ├── main.qml                # Main widget (7,818 lines)
│       │   ├── ConfigGeneral.qml       # Settings panel (5,222 lines)
│       │   ├── ScheduleDialog.qml      # Schedule dialog (1,358 lines)
│       │   ├── doc_extractor.py        # File extraction (279 lines)
│       │   ├── ProviderData.js         # Provider registry (23 lines)
│       │   ├── translations.js         # Translation engine (158 lines)
│       │   └── translations_*.js       # 11 language dictionaries
│       └── scripts/
│           ├── kde-ai-scheduler.py     # Scheduler daemon (573 lines)
│           └── kde-ai-scheduler.service
├── tests/                              # 39 Python tests + 1 QML test
├── docs/                               # 13 documentation files
├── dist/                               # Built .plasmoid packages
├── install.sh
├── .github/workflows/ci.yml
└── README.md
```

---

## 3. Strengths

### 3.1 Zero Runtime Dependencies
All Python code uses only the standard library. No pip packages required.

### 3.2 Comprehensive Documentation
13 well-written docs covering architecture, setup, contributing, security, scheduling, translations, and the OpenCode bridge.

### 3.3 Strong CI Pipeline
Three parallel GitHub Actions jobs covering Python, QML, and general linting.

### 3.4 Three-Tier API Key Storage
The session-only / plain-config / KWallet approach gives users control over their security posture. Now defaults to KWallet (mode 2).

### 3.5 Proper File Permissions
All sensitive files use `0o600`/`0o700` permissions. Atomic writes via tmp file + `os.replace()`.

### 3.6 Good Subprocess Practices
Python code never uses `shell=True`. All subprocess calls use list arguments with timeouts.

### 3.7 Internationalization
11 language dictionaries with a clean translation system.

### 3.8 Accessibility Added
42 `Accessible` annotations added across buttons, inputs, and interactive elements in `main.qml`.

---

## 4. High Severity Issues

### 4.1 Monolithic QML Files

**Severity: HIGH**

| File | Lines | Content |
|------|-------|---------|
| `main.qml` | 7,818 | Entire application lifecycle in one file |
| `ConfigGeneral.qml` | 5,222 | All settings logic in one file |
| `ScheduleDialog.qml` | 1,358 | Only properly extracted component |

The three QML files total **14,398 lines**. `main.qml` contains UI layout, API request logic, session management, scheduling, file attachment, streaming, context management, OpenCode integration, and clipboard handling — all in a single `PlasmoidItem`.

**Impact:**
- Extremely difficult to maintain, review, or debug
- No code reuse — duplicate logic appears in multiple places
- Changes in one area risk breaking unrelated functionality

**Suggestion:** Decompose into focused components following KDE's own widget examples:
```
ui/
├── main.qml                    # Root PlasmoidItem (200 lines)
├── ChatView.qml               # Message list + input
├── MessageBubble.qml           # Individual message rendering
├── SessionSidebar.qml          # Session management
├── ProviderService.js          # API call abstraction
├── SessionManager.js           # Session CRUD logic
├── StreamHandler.js            # SSE/streaming logic
├── ScheduleService.js          # Schedule management
├── ConfigGeneral.qml           # Settings root
├── ProviderConfig.qml          # Provider-specific settings
└── OpenCodeConfig.qml          # OpenCode settings
```

---

## 5. Medium Severity Issues

### 5.1 OpenCode Server Binds to All Interfaces

**Severity: MEDIUM**

The default start command in `main.xml` line 249:
```
nohup opencode serve --port 4096 >/tmp/kdeaichat-opencode.log 2>&1 &
```

This binds to `0.0.0.0:4096` by default, potentially exposing the OpenCode server to the network.

**Suggestion:** Add `--host 127.0.0.1` to restrict to localhost:
```
nohup opencode serve --host 127.0.0.1 --port 4096 >/tmp/kdeaichat-opencode.log 2>&1 &
```

### 5.2 Scheduler Polling Spawns Python Every 5 Seconds

**Severity: MEDIUM**

`schedulerPollTimer` spawns a Python subprocess every 5 seconds to check for pending trigger files. This is I/O-heavy and wasteful.

**Suggestion:** Replace with one of:
- **inotify** via a lightweight C helper or `inotifywait` to watch the pending directory
- **DBus signal** from the scheduler daemon when a trigger is written
- **Longer poll interval** (30-60s) with immediate check on widget focus

### 5.3 Massive Code Duplication

**Severity: MEDIUM**

Several patterns are duplicated extensively:

| Pattern | Occurrences |
|---------|-------------|
| Provider config if/else chains | 20+ branches each |
| OpenCode session creation | 2 functions (~50 lines each) |
| `walletBulkReadCommand()` | 2 files |
| Immutable array update pattern | Dozens of instances |
| Cloudflare URL with placeholder | 5 locations |

**Suggestion:** Extract shared logic into JS modules like `ProviderService.js`.

### 5.4 No Error Boundaries in QML Rendering

**Severity: MEDIUM**

`convertMarkdownToHtml()` and `parseMessageBlocks()` use complex regex operations. If they throw during rendering, the entire QML delegate crashes with no recovery.

**Suggestion:** Wrap rendering in try/catch:
```qml
Text {
    text: {
        try { return convertMarkdownToHtml(modelData.content) }
        catch (e) { return modelData.content }
    }
}
```

### 5.5 Silent Error Swallowing

**Severity: MEDIUM**

One empty catch block remains in `ConfigGeneral.qml` line 2974:
```qml
} catch(e) {}
```

**Suggestion:** At minimum, log the error.

### 5.6 No Performance Caching

**Severity: MEDIUM**

- `convertMarkdownToHtml()` runs complex regex on every message render — no caching
- `parseMessageBlocks()` also runs on every render without caching
- `openCodeBaseUrl()` is called 15+ times throughout the file instead of being computed once
- All 10 translation dictionaries are loaded at startup regardless of active language

**Suggestion:** Add memoization:
```javascript
var _markdownCache = ({})
function cachedMarkdownToHtml(md) {
    if (!_markdownCache[md]) _markdownCache[md] = convertMarkdownToHtml(md)
    return _markdownCache[md]
}
```

### 5.7 Temp File Leak in doc_extractor.py

**Severity: MEDIUM**

`doc_extractor.py` line 236 creates temp files for clipboard images but never deletes them:
```python
with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp_file:
    tmp_file.write(img_bytes)
    temp_path = tmp_file.name
```

**Suggestion:** Track created temp files and clean them up in a finally block.

### 5.8 Year 2036 Bug in ScheduleDialog

**Severity: MEDIUM**

`ScheduleDialog.qml` line 879:
```qml
from: 2026
to: 2035
```

**Suggestion:** Use dynamic year range:
```qml
from: new Date().getFullYear()
to: new Date().getFullYear() + 10
```

---

## 6. Low Severity Issues

### 6.1 Non-Cryptographic Session ID Generation

**Severity: LOW**

`makeSessionId()` uses `Math.random()` with 6-char alphanumeric IDs. Not a security risk since these are local identifiers, not auth tokens.

### 6.2 No Input Validation on Configuration Fields

**Severity: LOW**

- No API key format checking (e.g., `sk-` prefix for OpenAI)
- No URL validation on provider endpoints
- No maximum message length enforcement
- Free-text model names sent directly to APIs

### 6.3 No Rate Limiting on Message Sending

**Severity: LOW**

Users can rapidly queue many messages. The queuing system only checks if `loading` is true, but doesn't limit queue depth.

### 6.4 Session ID Shown in UI

**Severity: LOW**

`"ID: " + root.currentSessionId` displayed at 9px font (line 5158) is technical noise.

### 6.5 Emoji in System Messages

**Severity: LOW**

System messages use emoji (`▶️`, `⏸️`, `⚠️`, `ℹ️`) which may not render on all systems or fonts.

---

## 7. Informational Findings

### 7.1 No Hardcoded Secrets
Clean scan — no API keys, tokens, or credentials found in the repository.

### 7.2 Zero Network-Facing Services
The scheduler daemon has zero network exposure. Communication is exclusively via filesystem.

### 7.3 Proper Atomic Writes
Sensitive files use tmp file + `os.replace()` pattern to prevent corruption.

### 7.4 Good Signal Handling
The scheduler daemon properly handles SIGHUP (reload) and SIGTERM (cleanup with lock file removal).

### 7.5 Comprehensive Error Handling in Python
Both Python scripts have thorough try/except blocks, timeout handling, and structured error responses.

### 7.6 Well-Designed Scheduler Schema
The schedules.json schema is well-thought-out with versioning, history tracking, and run limits.

---

## 8. Suggestions from Industry Best Practices

### 8.1 Adopt KDE Component Architecture
Following KDE's own Plasma widget tutorial (<https://develop.kde.org/docs/plasma/widget/>), widgets should decompose into focused QML components.

### 8.2 Implement a Service Layer Pattern
Extract all API communication into a dedicated JavaScript module using `.pragma library`.

### 8.3 Add Type Annotations
Add Python type hints (enable `mypy` in CI) and JSDoc annotations for JS modules.

### 8.4 Implement Proper Logging
Replace remaining `console.log` with a structured logging approach gated by a log level flag.

### 8.5 Add Integration Tests
Expand the Python test suite with PDF extraction tests and end-to-end scheduler IPC tests.

### 8.6 Consider Flatpak Packaging
KDE recommends Flatpak for widget distribution. See: <https://develop.kde.org/docs/packaging/flatpak/>

### 8.7 Use Qt.labs.platform for File Dialogs
Use Qt's platform-aware dialogs with `StandardPaths` instead of hardcoded paths.

### 8.8 Implement Request Deduplication
Multiple rapid API calls to the same endpoint should be deduplicated.

### 8.9 Add Keyboard Shortcuts
Common actions (send message, new session, toggle sidebar) should have keyboard shortcuts.

### 8.10 Implement Message Search
A search function (Ctrl+F style) would significantly improve usability for long conversations.

---

## 9. Summary Table

| # | Issue | Severity | Category | File(s) |
|---|-------|----------|----------|---------|
| 1 | Monolithic QML files (14,398 lines in 3 files) | HIGH | Architecture | main.qml, ConfigGeneral.qml |
| 2 | OpenCode server binds to all interfaces | MEDIUM | Security | main.xml:249 |
| 3 | Scheduler polling spawns Python every 5s | MEDIUM | Performance | main.qml |
| 4 | Massive code duplication | MEDIUM | Maintainability | Multiple files |
| 5 | No error boundaries in QML rendering | MEDIUM | Reliability | main.qml |
| 6 | Silent error swallowing | MEDIUM | Reliability | ConfigGeneral.qml:2974 |
| 7 | No performance caching | MEDIUM | Performance | main.qml |
| 8 | Temp file leak in doc_extractor | MEDIUM | Resource leak | doc_extractor.py:236 |
| 9 | Year 2036 bug in date picker | MEDIUM | Bug | ScheduleDialog.qml:879 |
| 10 | Non-cryptographic session IDs | LOW | Security | main.qml:155 |
| 11 | No input validation on config fields | LOW | Validation | ConfigGeneral.qml |
| 12 | No rate limiting on messages | LOW | UX | main.qml |
| 13 | Session ID shown in UI | LOW | UX | main.qml:5158 |
| 14 | Emoji in system messages | LOW | UX | Multiple files |

---

## 10. Recommended Priority Roadmap

### Phase 1 — Architecture (Week 1-2)
1. Decompose `main.qml` into 8-10 focused components
2. Extract API communication into `ChatService.js`
3. Extract session management into `SessionManager.js`
4. Implement caching for markdown rendering and message parsing

### Phase 2 — Security Hardening (Week 2-3)
5. Add `--host 127.0.0.1` to OpenCode default start command
6. Add input validation on API key fields and URLs
7. Implement proper shell escaping for all user data passed to shell commands

### Phase 3 — Quality (Week 3-5)
8. Add error boundaries around QML rendering
9. Address remaining silent error swallowing
10. Add Python type hints and mypy to CI
11. Replace scheduler polling with inotify or DBus signals

### Phase 4 — Polish (Week 5+)
12. Fix temp file cleanup in doc_extractor.py
13. Replace hardcoded year range in ScheduleDialog
14. Add keyboard shortcuts
15. Add message search
16. Consider Flatpak packaging

---

*End of audit*
