# KDE AI Chat — Final Deep Audit

**Date:** 2026-06-04
**Version audited:** 1.3.0
**Repository:** <https://github.com/racstan/KDE-AI-Chat>
**Auditor:** Automated deep code audit

---

## 1. Executive Summary

KDE AI Chat is a KDE Plasma 6 plasmoid providing multi-provider LLM chat on the desktop. While the project demonstrates strong engineering in its CI pipeline, zero-dependency Python layer, and security-conscious key storage, there are significant issues in code architecture, security hardening, accessibility, and test coverage that should be addressed.

**Critical findings: 0 | High: 5 | Medium: 8 | Low: 6 | Informational: 6**

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



## 4. High Severity Issues

### 4.1 Debug Logging Exposes API Keys
### 4.2 Default Key Storage is Plaintext
### 4.3 Monolithic QML Files
### 4.4 Zero Accessibility Support
### 4.5 No QML/JS Unit Tests

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
### 5.3 Massive Code Duplication
### 5.4 No Error Boundaries in QML Rendering
### 5.5 Silent Error Swallowing
### 5.6 No Performance Caching
### 5.7 Temp File Leak in doc_extractor.py
### 5.8 Year 2036 Bug in ScheduleDialog

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

## 6. Low Severity Issues

### 6.1 Non-Cryptographic Session ID Generation
### 6.2 No Input Validation on Configuration Fields
### 6.3 No Rate Limiting on Message Sending
### 6.4 Hardcoded Sound File Paths
### 6.5 Session ID Shown in UI
### 6.6 Emoji in System Messages

**Severity: LOW**

System messages use emoji (`▶️`, `⏸️`, `⚠️`, `ℹ️`) which may not render on all systems or fonts.

---

## 7. Informational Findings

### 7.1 No Hardcoded Secrets
### 7.2 Zero Network-Facing Services
### 7.3 Proper Atomic Writes
### 7.4 Good Signal Handling
### 7.5 Comprehensive Error Handling in Python
### 7.6 Well-Designed Scheduler Schema
The schedules.json schema is well-thought-out with versioning, history tracking, and run limits.

---

## 8. Suggestions from Industry Best Practices

### 8.1 Adopt KDE Component Architecture
### 8.2 Implement a Service Layer Pattern
### 8.3 Add Type Annotations
### 8.4 Implement Proper Logging
### 8.5 Add Integration Tests
### 8.6 Consider Flatpak Packaging
### 8.7 Use Qt.labs.platform for File Dialogs
### 8.8 Implement Request Deduplication
### 8.9 Add Keyboard Shortcuts
### 8.10 Implement Message Search

With sessions potentially containing hundreds of messages, a search function (Ctrl+F style) would significantly improve usability.

---

## 9. Summary Table

| # | Issue | Severity | Category | File(s) |
|---|-------|----------|----------|---------|
| 1 | Debug logging exposes API keys | HIGH | Security | ConfigGeneral.qml:1115, 1807 |
| 2 | Default key storage is plaintext | HIGH | Security | main.xml:268 |
| 3 | Monolithic QML files (14,398 lines in 3 files) | HIGH | Architecture | main.qml, ConfigGeneral.qml |
| 4 | Zero accessibility support | HIGH | Accessibility | All QML files |
| 5 | No QML/JS unit tests | HIGH | Testing | — |
| 6 | OpenCode server binds to all interfaces | MEDIUM | Security | main.xml:249 |
| 7 | Scheduler polling spawns Python every 5s | MEDIUM | Performance | main.qml:4582 |
| 8 | Massive code duplication | MEDIUM | Maintainability | Multiple files |
| 9 | No error boundaries in QML rendering | MEDIUM | Reliability | main.qml |
| 10 | Silent error swallowing | MEDIUM | Reliability | main.qml |
| 11 | No performance caching | MEDIUM | Performance | main.qml |
| 12 | Temp file leak in doc_extractor | MEDIUM | Resource leak | doc_extractor.py:236 |
| 13 | Year 2036 bug in date picker | MEDIUM | Bug | ScheduleDialog.qml:879 |
| 14 | Non-cryptographic session IDs | LOW | Security | main.qml:142 |
| 15 | No input validation on config fields | LOW | Validation | ConfigGeneral.qml |
| 16 | No rate limiting on messages | LOW | UX | main.qml |
| 17 | Hardcoded sound file paths | LOW | Portability | main.qml:254, 3349, 3636 |
| 18 | Session ID shown in UI | LOW | UX | main.qml:5111 |
| 19 | Emoji in system messages | LOW | UX | main.qml |

---

## 10. Recommended Priority Roadmap

### Phase 1 — Critical Fixes (Week 1)
1. Remove or gate all debug `console.log` statements
2. Change default key storage mode to KWallet (2) or session-only (0)

### Phase 2 — Security Hardening (Week 2-3)
3. Add `--host 127.0.0.1` to OpenCode default start command
4. Add input validation on API key fields and URLs
5. Implement proper shell escaping for all user data passed to shell commands

### Phase 3 — Architecture (Week 3-5)
6. Decompose `main.qml` into 8-10 focused components
7. Extract API communication into `ChatService.js`
8. Extract session management into `SessionManager.js`
9. Implement caching for markdown rendering and message parsing

### Phase 4 — Quality (Week 5-7)
10. Add QML unit tests for critical flows
11. Add JSDoc annotations to all JS modules
12. Add Python type hints and mypy to CI
13. Replace scheduler polling with inotify or DBus signals

### Phase 5 — Polish (Week 7+)
14. Add `Accessible` properties to all interactive elements
15. Add keyboard shortcuts
16. Add message search
17. Consider Flatpak packaging

---

*End of audit*
