# KDE AI Chat — Final Deep Audit

**Date:** 2026-06-04
**Version audited:** 1.3.0
**Repository:** <https://github.com/racstan/KDE-AI-Chat>
**Auditor:** Automated deep code audit

---

## 1. Executive Summary

KDE AI Chat is a KDE Plasma 6 plasmoid providing multi-provider LLM chat on the desktop. The project shows strong engineering with good CI, zero-dependency Python layer, and security-conscious key storage. Most critical and high-severity issues have been resolved; remaining issues are primarily architectural and resource-management related.

**High: 1 | Medium: 3 | Low: 5 | Informational: 6**

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
Session-only / plain-config / KWallet approach. Now defaults to KWallet (mode 2).

### 3.5 Proper File Permissions
All sensitive files use `0o600`/`0o700` permissions. Atomic writes via tmp file + `os.replace()`.

### 3.6 Good Subprocess Practices
Python code never uses `shell=True`. All subprocess calls use list arguments with timeouts.

### 3.7 Internationalization
11 language dictionaries with a clean translation system.

### 3.8 Accessibility Added
42 `Accessible` annotations across buttons, inputs, and interactive elements in `main.qml`.

### 3.9 Error Resilience Added
`convertMarkdownToHtml()` and `parseMessageBlocks()` now wrapped in try/catch with fallback. Performance caching (`_markdownCache`, `_blocksCache`) implemented.

---

## 4. High Severity Issues

### 4.1 Monolithic QML Files

**Severity: HIGH**

| File | Lines |
|------|-------|
| `main.qml` | 7,818 |
| `ConfigGeneral.qml` | 5,222 |
| `ScheduleDialog.qml` | 1,358 |

The three QML files total **14,398 lines**. `main.qml` contains UI layout, API request logic, session management, scheduling, file attachment, streaming, context management, OpenCode integration, and clipboard handling — all in a single `PlasmoidItem`.

**Suggestion:** Decompose into focused components:
```
ui/
├── main.qml                    # Root PlasmoidItem
├── ChatView.qml               # Message list + input
├── MessageBubble.qml           # Individual message rendering
├── SessionSidebar.qml          # Session management
├── ProviderService.js          # API call abstraction
├── SessionManager.js           # Session CRUD logic
├── StreamHandler.js            # SSE/streaming logic
├── ScheduleService.js          # Schedule management
```

---

## 5. Medium Severity Issues

### 5.1 Scheduler Polling Spawns Python Every 5 Seconds

**Severity: MEDIUM (Optimized)**

`schedulerPollTimer` spawns a Python subprocess every 5 seconds to check for pending trigger files.

**Status:** Resolved / Optimized. Increased the interval to 30 seconds and configured it to run only when the plasmoid is expanded to save resources.

### 5.2 Massive Code Duplication

**Severity: MEDIUM**

Provider config if/else chains (20+ branches each), OpenCode session creation (2 near-identical functions), `walletBulkReadCommand()` duplicated across files, and Cloudflare URL placeholder in 5 locations.

**Suggestion:** Extract shared logic into JS modules.

### 5.3 Temp File Leak in doc_extractor.py

**Severity: MEDIUM (Fixed)**

Line 238 creates temp files for clipboard images but never deletes them.

**Status:** Fixed. Wrapped temporary file creation and extraction within a `try...finally` block, ensuring that the temporary file path is deleted with `os.remove()` as soon as the base64-encoded content is read.

---

## 6. Low Severity Issues (Fixed)

### 6.1 Non-Cryptographic Session ID Generation

**Severity: LOW (Fixed)**

`makeSessionId()` previously used `Math.random()` with 6-char alphanumeric IDs.

**Status:** Fixed. Updated session and fork ID generators to use Qt's native cryptographically strong `Qt.createUuid()` helper.

### 6.2 No Input Validation on Configuration Fields

**Severity: LOW (Fixed)**

Previously lacked API key format checking, URL validation, or maximum message length enforcement.

**Status:** Fixed. Added validation in `validateProviderConfig` to check for `http://` or `https://` schema on custom URLs, verify key prefixes (`sk-` for OpenAI, `sk-ant-` for Anthropic), and enforced a 100,000-character maximum message limit in `sendMessage()`.

### 6.3 No Rate Limiting on Message Sending

**Severity: LOW (Fixed)**

Previously users could rapidly queue many messages without limits.

**Status:** Fixed. Implemented a queue limit of 5 pending messages in `sendMessage()`.

### 6.4 Session ID Shown in UI

**Severity: LOW (Fixed)**

`"ID: " + root.currentSessionId` displayed at 9px font was technical noise.

**Status:** Fixed. Removed the label displaying the session ID from the UI header block.

### 6.5 Emoji in System Messages

**Severity: LOW (Fixed)**

System messages previously used emojis (`▶️`, `⏸️`, `⚠️`, `ℹ️`) which may not render on all systems.

**Status:** Fixed. Replaced all emojis in chat notifications, warnings, and dialog instruction labels with text-based identifiers.

---

## 7. Informational Findings

### 7.1 No Hardcoded Secrets
Clean scan — no API keys, tokens, or credentials found in the repository.

### 7.2 Zero Network-Facing Services
The scheduler daemon has zero network exposure.

### 7.3 Proper Atomic Writes
Sensitive files use tmp file + `os.replace()` pattern.

### 7.4 Good Signal Handling
The scheduler daemon properly handles SIGHUP (reload) and SIGTERM (cleanup).

### 7.5 Comprehensive Error Handling in Python
Both Python scripts have thorough try/except blocks with timeouts.

### 7.6 Well-Designed Scheduler Schema
Versioned schema with history tracking and run limits.

---

## 8. Suggestions from Industry Best Practices

### 8.1 Adopt KDE Component Architecture
Decompose into focused QML components per KDE widget conventions.

### 8.2 Implement a Service Layer Pattern
Extract API communication into a dedicated JS module using `.pragma library`.

### 8.3 Add Type Annotations
Add Python type hints (enable `mypy` in CI) and JSDoc for JS modules.

### 8.4 Add Integration Tests
Expand test suite with PDF extraction and end-to-end scheduler IPC tests.

### 8.5 Consider Flatpak Packaging
KDE recommends Flatpak for widget distribution.

### 8.6 Implement Request Deduplication
Deduplicate rapid API calls to the same endpoint.

### 8.7 Add Keyboard Shortcuts
Common actions should have keyboard shortcuts for power users.

### 8.8 Implement Message Search
Ctrl+F style search for long conversations.

---

## 9. Summary Table

| # | Issue | Severity | Category | File(s) | Status |
|---|-------|----------|----------|---------|--------|
| 1 | Monolithic QML files (14,398 lines) | HIGH | Architecture | main.qml, ConfigGeneral.qml | Open |
| 2 | Scheduler polling spawns Python every 5s | MEDIUM | Performance | main.qml | Optimized (Runs only when expanded, 30s interval) |
| 3 | Massive code duplication | MEDIUM | Maintainability | Multiple files | Open |
| 4 | Temp file leak in doc_extractor | MEDIUM | Resource leak | doc_extractor.py:238 | Fixed (Cleaned in finally block) |
| 5 | Non-cryptographic session IDs | LOW | Security | main.qml:161 | Fixed (Now uses Qt.createUuid()) |
| 6 | No input validation on config fields | LOW | Validation | ConfigGeneral.qml | Fixed (Added URL schema and key prefix validation) |
| 7 | No rate limiting on messages | LOW | UX | main.qml | Fixed (Added queue limit of 5 and max length check) |
| 8 | Session ID shown in UI | LOW | UX | main.qml:5190 | Fixed (Removed label from header) |
| 9 | Emoji in system messages | LOW | UX | Multiple files | Fixed (Replaced with text-based labels/warnings) |

---

## 10. Recommended Priority Roadmap

### Phase 1 — Architecture
1. Decompose `main.qml` into 8-10 focused components
2. Extract shared logic into JS modules (reduce code duplication)
3. Replace scheduler polling with inotify or DBus signals

### Phase 2 — Quality & Polish
4. Add keyboard shortcuts
5. Add message search

### Phase 3 — Future
7. Add Python type hints and mypy to CI
8. Implement request deduplication
9. Consider Flatpak packaging

---

*End of audit*
