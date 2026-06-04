# KDE AI Chat — Final Deep Audit

**Date:** 2026-06-04
**Version audited:** 1.3.0
**Repository:** <https://github.com/racstan/KDE-AI-Chat>
**Auditor:** Automated deep code audit

---

## 1. Executive Summary

KDE AI Chat is a KDE Plasma 6 plasmoid providing multi-provider LLM chat on the desktop. While the project demonstrates strong engineering in its CI pipeline, zero-dependency Python layer, and security-conscious key storage, there are significant issues in code architecture, security hardening, accessibility, and test coverage that should be addressed.

**Critical findings: 3 | High: 5 | Medium: 8 | Low: 7 | Informational: 6**

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
├── tests/                              # 39 Python tests
├── docs/                               # 13 documentation files
├── dist/                               # Built .plasmoid packages
├── install.sh
├── .github/workflows/ci.yml
└── README.md
```

---

## 3. Strengths

### 3.1 Zero Runtime Dependencies
All Python code uses only the standard library. No pip packages required. This eliminates supply chain attack vectors and simplifies deployment dramatically.

### 3.2 Comprehensive Documentation
13 well-written docs covering architecture, setup, contributing, security, scheduling, translations, and the OpenCode bridge. The `SECURITY.md` and `ARCHITECTURE.md` are particularly noteworthy.

### 3.3 Strong CI Pipeline
Three parallel GitHub Actions jobs covering Python (syntax, ruff lint, pytest), QML (qmllint), and general linting (yamllint, markdownlint). This is above average for a plasmoid project.

### 3.4 Three-Tier API Key Storage
The session-only / plain-config / KWallet approach gives users control over their security posture. KWallet integration via DBus is well-implemented with proper error handling.

### 3.5 Proper File Permissions
All sensitive files (schedules, pending triggers, lock files) use `0o600`/`0o700` permissions. Atomic writes via tmp file + `os.replace()` prevent corruption.

### 3.6 Good Subprocess Practices
Python code never uses `shell=True`. All subprocess calls use list arguments with timeouts. This is textbook-correct.

### 3.7 Internationalization
11 language dictionaries with a clean translation system and a documented contributor guide for adding new languages.

---

## 4. Critical Issues

### 4.1 Shell Injection via `exec(base64.b64decode(...))` Pattern

**Severity: CRITICAL**

The codebase extensively uses a pattern where Python code is constructed as strings in QML/JS, base64-encoded, and executed via shell:

```javascript
// main.qml — multiple locations (lines 220, 272, 397, 411, 669, 3008, 4314, 4596, 6169, 7631, 7665)
var py = ["import json, os", "p = os.path.expanduser('~/.local/share/kdeaichat/schedules.json')", ...].join("\n");
var b64Py = base64Encode(py);
var cmd = "python3 -c \"import base64; exec(base64.b64decode('" + b64Py + "').decode('utf-8'))\"";
schedulerDs.connectSource("sh -lc '" + cmd.replace(/'/g, "'\\''") + "'");
```

**Why this is dangerous:**
- Base64 is encoding, not security — it's trivially reversible
- User-controlled data (session IDs, schedule names, error messages, message text) flows into these Python code strings
- The `shellEscape()` function only escapes single quotes — it does not protect against injection when the content is inside an `exec()` call
- This pattern appears in **15+ locations** across `main.qml` and `ConfigGeneral.qml`

**Specific injection vectors:**
1. `sessionId` — flows into Python code at lines 218, 3006
2. `schedId` — schedule IDs used in Python code strings
3. `validationError` — error messages written to schedule history
4. `messageText` — user messages passed to `notify-send` shell commands

**Suggestion:** Replace the `exec(base64.b64decode(...))` pattern with a proper Python helper script that accepts arguments via stdin or command-line parameters. The QML side should invoke a fixed Python script with sanitized arguments, never construct Python code strings dynamically.

### 4.2 Hardcoded Developer Paths

**Severity: CRITICAL**

Multiple files contain hardcoded paths specific to the developer's machine:

| File | Line | Hardcoded Path |
|------|------|----------------|
| `ConfigGeneral.qml` | 1166 | `/home/home/.config/kdeaichatrc` |
| `ConfigGeneral.qml` | 1212 | `/home/home/.config/kdeaichatrc` |
| `ConfigGeneral.qml` | 1242 | `/home/home/.config/kdeaichatrc` |
| `ConfigGeneral.qml` | 1253 | `/home/home/.config/kdeaichatrc` |
| `main.qml` | 5219 | `file:///home/home/Documents/` |
| `main.qml` | 5261 | `/home/home/Programming/rachitkdeaichat/.opencode-session` |
| `main.qml` | 5268 | `/home/home/Programming/rachitkdeaichat/.opencode-session` |

**Impact:** The widget will fail on any system where the username is not `home`. This is a showstopper for distribution.

**Suggestion:** Replace all hardcoded paths with dynamic resolution:
```javascript
// Use Qt's standard paths
var homeDir = Qt.resolvedUrl("~").toString().replace("file://", "")
// Or use the existing os.path.expanduser() pattern in Python
```

### 4.3 Undefined Function Reference

**Severity: CRITICAL**

`findSessionIndex()` is called at lines 3694 and 3821 in `main.qml` but is **not defined anywhere** in the codebase. The actual function is `sessionIndexById()`. This causes runtime errors when these code paths are executed.

**Suggestion:** Either rename the calls to `sessionIndexById()` or add an alias function.

---

## 5. High Severity Issues

### 5.1 Debug Logging Exposes API Keys

**Severity: HIGH**

Console.log statements in production code leak sensitive data:

| File | Line | What it logs |
|------|------|--------------|
| `ConfigGeneral.qml` | 1115 | Full KWallet shell command (reveals wallet name and key names) |
| `ConfigGeneral.qml` | 1807 | KWallet stdout — **may contain API key values from bulk read** |
| `ConfigGeneral.qml` | 1808 | KWallet stderr |

Total of **26 console.log/warn/error statements** across QML files should be removed or gated behind a debug flag.

**Suggestion:** Remove all `console.log` statements from production code. If debug logging is needed, use a flag:
```javascript
property bool debugMode: false
function debugLog(...args) { if (debugMode) console.log("[KAI-DEBUG]", ...args) }
```

### 5.2 Default Key Storage is Plaintext

**Severity: HIGH**

In `main.xml` line 268, `keyStorageMode` defaults to `1` (plain config). API keys are stored unencrypted in `~/.config/kdeaichatrc`. While KWallet mode exists, the default is insecure for shared systems or users who don't change defaults.

**Suggestion:** Change the default to `2` (KWallet) or `0` (session-only). If KWallet is unavailable, fall back to session-only with a clear warning.

### 5.3 Monolithic QML Files

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

### 5.4 Zero Accessibility Support

**Severity: HIGH**

No `Accessible` annotations found anywhere in the codebase. The entire UI is invisible to screen readers.

**Missing:**
- No `Accessible.name` on any interactive element
- No `Accessible.role` declarations
- No keyboard navigation indicators for the chat bubble list
- Color-only information without alternative visual cues

**Suggestion:** Add `Accessible` properties to all interactive elements:
```qml
ToolButton {
    icon.name: "document-send"
    Accessible.name: qsTr("Send message")
    Accessible.description: qsTr("Send the current message to the AI provider")
}
```

### 5.5 No QML/JS Unit Tests

**Severity: HIGH**

The QML layer (14,398 lines) has **zero automated tests**. CI has an optional `qmltestrunner` step but it's not enforced. The JS modules (`ProviderData.js`, `translations.js`) also have no tests.

**Suggestion:** Add QML tests using Qt's `TestCase`:
```qml
import QtTest 1.0
TestCase {
    name: "SessionManagerTests"
    function test_createSession() { ... }
    function test_deleteSession() { ... }
}
```

---

## 6. Medium Severity Issues

### 6.1 OpenCode Server Binds to All Interfaces

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

### 6.2 Scheduler Polling Spawns Python Every 5 Seconds

**Severity: MEDIUM**

`schedulerPollTimer` (line 4582) spawns a Python subprocess every 5 seconds to check for pending trigger files. This is I/O-heavy and wasteful.

**Suggestion:** Replace with one of:
- **inotify** via a lightweight C helper or `inotifywait` to watch the pending directory
- **DBus signal** from the scheduler daemon when a trigger is written
- **Longer poll interval** (30-60s) with immediate check on widget focus

### 6.3 Massive Code Duplication

**Severity: MEDIUM**

Several patterns are duplicated extensively:

| Pattern | Occurrences | Locations |
|---------|-------------|-----------|
| Anthropic API version header | 3 | Lines 951, 3246, 3539 |
| Provider config if/else chains | 20+ branches each | `currentProviderConfig()`, `providerHasConfigoredKey()` |
| OpenCode session creation | 2 | `ensureCurrentOpenCodeSession()` and `ensureOpenCodeSessionForChatId()` (~50 lines each) |
| `walletBulkReadCommand()` | 2 | Both `ConfigGeneral.qml` and `main.qml` |
| Immutable array update pattern | Dozens | `root.sessions = updated[idx] = s; ... root.sessions = updated` |
| Cloudflare URL with placeholder | 5 | Across main.xml, main.qml, ConfigGeneral.qml |

**Suggestion:** Extract shared logic into JS modules:
```javascript
// ProviderService.js
function getProviderConfig(provider) { ... }
function buildRequest(provider, model, messages) { ... }
```

### 6.4 No Error Boundaries in QML Rendering

**Severity: MEDIUM**

`convertMarkdownToHtml()` (line 3857) and `parseMessageBlocks()` (line 4024) use complex regex operations. If they throw during rendering, the entire QML delegate crashes with no recovery.

**Suggestion:** Wrap rendering in try/catch:
```qml
Text {
    text: {
        try { return convertMarkdownToHtml(modelData.content) }
        catch (e) { return modelData.content } // fallback to plain text
    }
}
```

### 6.5 Silent Error Swallowing

**Severity: MEDIUM**

Several catch blocks are empty, hiding potential issues:

| File | Line | Context |
|------|------|---------|
| `main.qml` | 1350 | SSE event parsing: `catch (eventError) {}` |
| `main.qml` | 3603 | Anthropic error parsing: `catch (e2) {}` |
| `main.qml` | 3848 | `stopStreaming()`: `catch (e) {}` |
| `main.qml` | 323 | Session JSON parse: `catch(e) { return []; }` |

**Suggestion:** At minimum, log the error. Better: display a user-facing warning for data corruption cases.

### 6.6 No Performance Caching

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

### 6.7 Temp File Leak in doc_extractor.py

**Severity: MEDIUM**

`doc_extractor.py` lines 236-238 create temp files for clipboard images but never delete them:
```python
with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp_file:
    tmp_file.write(img_bytes)
    temp_path = tmp_file.name
# temp_path is returned but never cleaned up
```

**Suggestion:** Track created temp files and clean them up in a finally block or provide a cleanup mechanism.

### 6.8 Year 2036 Bug in ScheduleDialog

**Severity: MEDIUM**

`ScheduleDialog.qml` lines 879-880:
```qml
from: 2026
to: 2035
```

The date picker will break in 2036.

**Suggestion:** Use dynamic year range:
```qml
from: new Date().getFullYear()
to: new Date().getFullYear() + 10
```

---

## 7. Low Severity Issues

### 7.1 Non-Cryptographic Session ID Generation

**Severity: LOW**

`makeSessionId()` uses `Math.random()` with 6-char alphanumeric IDs (36^6 = ~2.18 billion possibilities). Not a security risk since these are local identifiers, not auth tokens.

### 7.2 No Input Validation on Configuration Fields

**Severity: LOW**

- No API key format checking (e.g., `sk-` prefix for OpenAI)
- No URL validation on provider endpoints
- No maximum message length enforcement
- Free-text model names sent directly to APIs

### 7.3 No Rate Limiting on Message Sending

**Severity: LOW**

Users can rapidly queue many messages. The queuing system (line 2563) only checks if `loading` is true, but doesn't limit queue depth.

### 7.4 Hardcoded Sound File Paths

**Severity: LOW**

Sound paths like `/usr/share/sounds/ocean/stereo/service-login.oga` may not exist on non-KDE or non-standard installations.

### 7.5 Export Path Uses Developer's Home

**Severity: LOW**

`main.qml` line 5219: `exportFileDialog.currentFile = "file:///home/home/Documents/"` should use `Qt.resolvedUrl("~/Documents")`.

### 7.6 Session ID Shown in UI

**Severity: LOW**

`"ID: " + root.currentSessionId` displayed at 9px font (line 5111) is technical noise that should be hidden or placed behind a debug toggle.

### 7.7 Emoji in System Messages

**Severity: LOW**

System messages use emoji (`▶️`, `⏸️`, `⚠️`, `ℹ️`) which may not render on all systems or fonts.

---

## 8. Informational Findings

### 8.1 No Hardcoded Secrets
Clean scan — no API keys, tokens, or credentials found in the repository.

### 8.2 Zero Network-Facing Services
The scheduler daemon has zero network exposure. Communication is exclusively via filesystem.

### 8.3 Proper Atomic Writes
Sensitive files use tmp file + `os.replace()` pattern to prevent corruption.

### 8.4 Good Signal Handling
The scheduler daemon properly handles SIGHUP (reload) and SIGTERM (cleanup with lock file removal).

### 8.5 Comprehensive Error Handling in Python
Both Python scripts have thorough try/except blocks, timeout handling, and structured error responses.

### 8.6 Well-Designed Scheduler Schema
The schedules.json schema is well-thought-out with versioning, history tracking, and run limits.

---

## 9. Suggestions from Industry Best Practices

### 9.1 Adopt KDE Component Architecture

Following KDE's own Plasma widget tutorial (<https://develop.kde.org/docs/plasma/widget/>), widgets should decompose into focused QML components. The default KDE widgets at `/usr/share/plasma/plasmoids/` demonstrate this pattern — even complex widgets like the system tray use 10+ separate QML files.

### 9.2 Implement a Service Layer Pattern

Extract all API communication into a dedicated JavaScript module:

```javascript
// ChatService.js
.pragma library

function sendMessage(provider, apiKey, model, messages, callback) {
    var xhr = new XMLHttpRequest()
    // ... centralized request logic
}
```

This follows the Qt recommendation to separate business logic from UI declarations.

### 9.3 Add Type Annotations

Both Python and JavaScript benefit from type annotations:
- **Python:** Add type hints and enable `mypy` in CI
- **JavaScript:** Add JSDoc annotations for better IDE support and documentation

### 9.4 Implement Proper Logging

Replace `console.log` with a structured logging approach:
```javascript
property int logLevel: 0  // 0=none, 1=error, 2=warn, 3=info, 4=debug
function log(level, ...args) {
    if (level <= logLevel) console.log("[KAI]", ...args)
}
```

### 9.5 Add Integration Tests

The Python test suite is good but could be expanded:
- Add tests for PDF extraction (requires `poppler-utils` in CI)
- Add tests for the scheduler's file-based IPC end-to-end
- Add snapshot tests for QML rendering

### 9.6 Consider Flatpak Packaging

KDE recommends Flatpak for widget distribution. This would sandbox the widget and ensure all dependencies are available. See: <https://develop.kde.org/docs/packaging/flatpak/>

### 9.7 Use Qt.labs.platform for File Dialogs

Replace hardcoded paths with Qt's platform-aware dialogs:
```qml
import Qt.labs.platform 1.1
FileDialog {
    folder: StandardPaths.writableLocation(StandardPaths.DocumentsLocation)
}
```

### 9.8 Implement Request Deduplication

Multiple rapid API calls to the same endpoint should be deduplicated. Currently, switching providers while a request is in-flight can result in orphaned responses.

### 9.9 Add Keyboard Shortcuts

Common actions (send message, new session, toggle sidebar) should have keyboard shortcuts. This improves accessibility and power-user experience.

### 9.10 Implement Message Search

With sessions potentially containing hundreds of messages, a search function (Ctrl+F style) would significantly improve usability.

---

## 10. Summary Table

| # | Issue | Severity | Category | File(s) |
|---|-------|----------|----------|---------|
| 1 | Shell injection via `exec(base64.b64decode(...))` | CRITICAL | Security | main.qml, ConfigGeneral.qml |
| 2 | Hardcoded developer paths (`/home/home/...`) | CRITICAL | Portability | ConfigGeneral.qml, main.qml |
| 3 | Undefined function `findSessionIndex()` | CRITICAL | Bug | main.qml:3694, 3821 |
| 4 | Debug logging exposes API keys | HIGH | Security | ConfigGeneral.qml:1115, 1807 |
| 5 | Default key storage is plaintext | HIGH | Security | main.xml:268 |
| 6 | Monolithic QML files (14,398 lines in 3 files) | HIGH | Architecture | main.qml, ConfigGeneral.qml |
| 7 | Zero accessibility support | HIGH | Accessibility | All QML files |
| 8 | No QML/JS unit tests | HIGH | Testing | — |
| 9 | OpenCode server binds to all interfaces | MEDIUM | Security | main.xml:249 |
| 10 | Scheduler polling spawns Python every 5s | MEDIUM | Performance | main.qml:4582 |
| 11 | Massive code duplication | MEDIUM | Maintainability | Multiple files |
| 12 | No error boundaries in QML rendering | MEDIUM | Reliability | main.qml |
| 13 | Silent error swallowing | MEDIUM | Reliability | main.qml |
| 14 | No performance caching | MEDIUM | Performance | main.qml |
| 15 | Temp file leak in doc_extractor | MEDIUM | Resource leak | doc_extractor.py:236 |
| 16 | Year 2036 bug in date picker | MEDIUM | Bug | ScheduleDialog.qml:879 |
| 17 | Non-cryptographic session IDs | LOW | Security | main.qml:142 |
| 18 | No input validation on config fields | LOW | Validation | ConfigGeneral.qml |
| 19 | No rate limiting on messages | LOW | UX | main.qml |
| 20 | Hardcoded sound file paths | LOW | Portability | main.qml:254, 3349, 3636 |
| 21 | Export path uses developer's home | LOW | Portability | main.qml:5219 |
| 22 | Session ID shown in UI | LOW | UX | main.qml:5111 |
| 23 | Emoji in system messages | LOW | UX | main.qml |

---

## 11. Recommended Priority Roadmap

### Phase 1 — Critical Fixes (Week 1)
1. Replace all hardcoded `/home/home/` paths with dynamic resolution
2. Fix `findSessionIndex()` → `sessionIndexById()` references
3. Remove or gate all debug `console.log` statements
4. Change default key storage mode to KWallet (2) or session-only (0)

### Phase 2 — Security Hardening (Week 2-3)
5. Replace `exec(base64.b64decode(...))` pattern with proper Python helper scripts
6. Add `--host 127.0.0.1` to OpenCode default start command
7. Add input validation on API key fields and URLs
8. Implement proper shell escaping for all user data passed to shell commands

### Phase 3 — Architecture (Week 3-5)
9. Decompose `main.qml` into 8-10 focused components
10. Extract API communication into `ChatService.js`
11. Extract session management into `SessionManager.js`
12. Implement caching for markdown rendering and message parsing

### Phase 4 — Quality (Week 5-7)
13. Add QML unit tests for critical flows
14. Add JSDoc annotations to all JS modules
15. Add Python type hints and mypy to CI
16. Replace scheduler polling with inotify or DBus signals

### Phase 5 — Polish (Week 7+)
17. Add `Accessible` properties to all interactive elements
18. Add keyboard shortcuts
19. Add message search
20. Consider Flatpak packaging

---

*End of audit*
