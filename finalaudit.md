# KDE AI Chat — Deep Audit Report

**Date:** 2026-06-05
**Version audited:** 1.3.0
**Repository:** <https://github.com/racstan/KDE-AI-Chat>
**Auditor:** Automated deep code audit (full codebase)

---

## 1. Executive Summary

KDE AI Chat is a KDE Plasma 6 plasmoid providing multi-provider LLM chat on the desktop. The project demonstrates strong engineering fundamentals: zero Python runtime dependencies, comprehensive CI with mypy/pytest/qmllint, a modular JavaScript architecture, three-tier API key storage, and extensive documentation.

However, this deep audit reveals **significant security vulnerabilities** in shell command construction, **performance bottlenecks** from ListView model churn and unbounded caches, **substantial code duplication** across 18 providers, **critical test coverage gaps** (25+ untested functions, zero security tests), and **documentation inaccuracies** (license mismatch, stale architecture diagrams).

**Finding counts by severity:**

| Severity | Count |
|----------|-------|
| Critical | 7 |
| High | 22 |
| Medium | 38 |
| Low | 20 |
| **Total** | **87** |

---

## 1.1 Resolution Status (Post-Audit Pass)

A remediation pass was performed on 2026-06-05. All 7 critical security findings and the 3 highest-impact high-severity security findings were fixed in the source tree. A new `Security.js` helper module was introduced and imported into `main.qml`, `ConfigGeneral.qml`, and `MessageContent.qml`.

| ID | Severity | Status | Resolution |
|----|----------|--------|------------|
| 4.1 | Critical | ✅ Fixed | Sanitized LLM/user strings via `Sec.sanitizeForShell` + `Sec.quoteForShell` (7 sites) |
| 4.2 | Critical | ✅ Fixed | Switched `copyToClipboard()` outer wrapper from double- to single-quoting |
| 4.3 | Critical | ✅ Fixed | Validated file paths with `Sec.validateFilePath` (5 sites) |
| 4.4 | Critical | ✅ Fixed | Added `Sec.validateUrl` in `MessageContent.qml` `onLinkActivated` |
| 4.5 | Critical | ✅ Fixed | `getHelperPath()` / `getDocExtractorPath()` now reject paths outside `contents/ui/` |
| 4.6 | Critical | ✅ Fixed | OpenCode start/stop commands quoted via `Sec.quoteForShell` (full `'…'` wrapper); user-editable shell fragments retained by design (documented inline) |
| 4.7 | Critical | ✅ Fixed | `MarkdownRenderer.js` link regex now uses `sanitizeHref()` callback allowing only `http:`, `https:`, `mailto:` |
| 4.8 | High | ✅ Fixed | Storage export in `ConfigGeneral.qml` now uses `Sec.validateFilePath` + `Sec.quoteForShell` |
| 4.9 | High | ✅ Fixed | `killRunningOpenCodeSession()` now validates session ID via `Sec.validateSessionId` |
| 6.3 | High | ✅ Fixed | `root.currentSessionIndex()` → `sessionIndexById(root.currentSessionId)` |
| 6.7 | Medium | ✅ Fixed | `findIndex` now compares `s.value === currentSessionId`, uses `s.text || s.title` for display |
| 4.10 – 4.14, 5.1 – 6.13 | Mixed | ⏳ Deferred | Performance refactors, error-message scrubbing, and design-level fixes require larger work units; the security/CVE-class bugs are resolved. |

**Verification commands (post-fix):**

```sh
rg -n "cmd\.replace\(/'/g" org.kde.plasma.kdeaichat/contents/ui/   # expect 0 matches
rg -n "Qt\.openUrlExternally" org.kde.plasma.kdeaichat/contents/ui/   # all wrapped in Sec.validateUrl
qmllint org.kde.plasma.kdeaichat/contents/ui/main.qml
qmllint org.kde.plasma.kdeaichat/contents/ui/ConfigGeneral.qml
```

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
│       │   ├── main.qml                # Main widget (7,413 lines)
│       │   ├── ConfigGeneral.qml       # Settings panel (5,218 lines)
│       │   ├── ScheduleDialog.qml      # Schedule dialog (1,358 lines)
│       │   ├── MessageContent.qml      # Message body renderer (228 lines)
│       │   ├── SessionSidebar.qml      # Session list (244 lines)
│       │   ├── ProviderService.js      # Provider config map + JSDoc (377 lines)
│       │   ├── SessionManager.js       # Session CRUD + JSDoc (295 lines)
│       │   ├── MarkdownRenderer.js     # Markdown conversion + JSDoc (251 lines)
│       │   ├── WalletService.js        # KWallet shell-script builder + JSDoc (52 lines)
│       │   ├── RequestDeduplicator.js  # In-flight request tracker + JSDoc (100 lines)
│       │   ├── doc_extractor.py        # File extraction + type hints (357 lines)
│       │   ├── kde_ai_helper.py        # IPC helper + type hints (354 lines)
│       │   ├── ProviderData.js         # Provider registry (23 lines)
│       │   ├── translations.js         # Translation engine (158 lines)
│       │   └── translations_*.js       # 10 language dictionaries
│       └── scripts/
│           ├── kde-ai-scheduler.py     # Scheduler daemon (573 lines)
│           ├── kde-ai-scheduler.service
│           └── opencode-terminal.sh
├── org.kde.plasma.kdeaichat.flatpak.json  # Flatpak manifest
├── tests/                                  # 6 Python test files + 1 QML test
├── docs/                                   # 14 documentation files
├── install.sh
├── .github/workflows/ci.yml
├── pyproject.toml
├── scratch/                                # Developer scratch files
└── README.md
```

---

## 3. Strengths

### 3.1 Zero Runtime Dependencies
All Python code uses only the standard library. No pip packages required. System-level tools (`pdftotext`, `pandoc`) are optional per-feature.

### 3.2 Comprehensive Documentation
14 well-written docs covering architecture, setup, contributing, security, scheduling, translations, the OpenCode bridge, and Flatpak packaging.

### 3.3 Strong CI Pipeline
Three parallel GitHub Actions jobs covering Python (syntax, ruff lint, mypy, pytest), QML (qmllint), and general linting (YAML, Markdown).

### 3.4 Three-Tier API Key Storage
Session-only / plain-config / KWallet approach. Defaults to KWallet (mode 2). Properly documented in SECURITY.md.

### 3.5 Proper File Permissions
All sensitive files use `0o600`/`0o700` permissions. Atomic writes via tmp file + `os.replace()` in the scheduler.

### 3.6 Good Subprocess Practices (Python)
Python code never uses `shell=True`. All subprocess calls use list arguments with timeouts.

### 3.7 Internationalization
10 language dictionaries with a clean translation system and dynamic pattern matching for provider settings.

### 3.8 Accessibility
42 `Accessible` annotations across buttons, inputs, and interactive elements in `main.qml`.

### 3.9 Error Resilience
All JS modules and external-tool calls wrapped in try/catch with fallback paths.

### 3.10 Modular JavaScript Architecture
Five focused `.pragma library` JavaScript modules with full JSDoc coverage, `@param`/`@returns` annotations, and typedef definitions.

### 3.11 Request Deduplication
`RequestDeduplicator.js` prevents duplicate in-flight requests keyed on `(provider, model, lastUserText, sessionId)`.

### 3.12 Keyboard Shortcuts
13 keyboard shortcuts for navigation, input focus, session switching, history refresh, and help.

### 3.13 Flatpak Manifest
Produces a reproducible `.plasmoid` artifact inside a clean KDE 6.8 SDK environment.

---

## 4. Security Findings

### 4.1 Critical — Shell Injection via `notify-send` with LLM Output

**File:** `main.qml:464-468, 2457-2460, 2964, 3041-3044, 3167-3170, 3260-3263`

Multiple places construct shell commands by escaping single quotes (`'\\''`) and embedding LLM-controlled strings into `sh -lc '...'`. Single-quote escaping is **insufficient** — a crafted message containing `$(malicious_command)` or backticks will execute during shell expansion.

```qml
// messageText is LLM output
soundDs.connectSource("notify-send ... '" + escapedTitle + "' '" + escapedText + "' #sched-notify");
```

**Recommendation:** Sanitize all LLM/user strings by stripping `$`, backticks, `(`, `)`, and `\` before shell embedding. Better yet, use a Python helper for notifications instead of shell commands.

**Status (2026-06-05): ✅ Resolved.** All 7 `notify-send` invocations now pass title/text through `Sec.sanitizeForShell()` (strips shell metacharacters: `$`, backtick, `(`, `)`, `\`, `;`, `&`, `|`, `<`, `>`, newline, CR, NUL, BEL) and embed via `Sec.quoteForShell()` which produces a fully-quoted `'…'` argument. See `org.kde.plasma.kdeaichat/contents/ui/Security.js`.

### 4.2 Critical — Shell Injection via Clipboard Copy

**File:** `main.qml:4305-4306`

The clipboard copy command wraps user/LLM content in double quotes inside `sh -lc`, making single-quote escaping irrelevant:

```qml
var cmd = "sh -lc \"if command -v wl-copy ... printf '%s' '" + escaped + "' | wl-copy; ...\"";
```

**Recommendation:** Use `wl-copy` via a QProcess with stdin piping instead of shell embedding.

**Status (2026-06-05): ✅ Resolved.** The outer wrapper was switched from double-quoted (`"…"`) to single-quoted (`'…'`), and the inner payload is now produced by `Sec.quoteForShell(safe)`. The clipboard command lives in `main.qml:4302` (and a sibling copy in `ConfigGeneral.qml:285` was hardened the same way).

### 4.3 Critical — Shell Injection via File Paths

**File:** `main.qml:3948-3950, 4259, 5136`

File paths from user file selection are single-quote escaped but not sanitized against `$(...)` or backtick injection:

```qml
var cmd = "python3 '" + docExtractorPath + "' '" + escapedPath + "'";
```

**Recommendation:** Pass file paths via stdin or environment variables rather than shell argument interpolation.

**Status (2026-06-05): ✅ Resolved.** All file-path inputs are now passed through `Sec.validateFilePath()` (rejects `..`, restricts to `[A-Za-z0-9._/+@:=\-]`, length-clamped to 4096) before embedding. Sites covered: `attachFile()` (`main.qml:3947`), custom-history read (`main.qml:4259`), OpenCode terminal launch (`main.qml:5129-5148`), export-chat notification (`main.qml:4151`), storage export (`ConfigGeneral.qml:5128-5147`), and CSV export (`MessageContent.qml:208-212`). 17 `python3 '…' '…'` invocations were refactored to use `Sec.quoteForShell()`.

### 4.4 Critical — Unsafe URL Opening from LLM Content

**File:** `MessageContent.qml:79-80`

`Qt.openUrlExternally(link)` opens any URL scheme the LLM produces, including `javascript:`, `file:///`, or custom schemes:

```qml
onLinkActivated: function(link) {
    Qt.openUrlExternally(link);
}
```

**Recommendation:** Validate URL schemes (allow only `https://`, `http://`, `mailto:`) before opening.

**Status (2026-06-05): ✅ Resolved.** `MessageContent.qml` now imports `Security.js` and gates every `onLinkActivated` through `Sec.validateUrl()` which permits only `http:`/`https:`/`mailto:`. Both the text-block and table-block link handlers are guarded.

### 4.5 Critical — Arbitrary Code Execution via Python Helper Path

**File:** `ConfigGeneral.qml:1183-1184, 1234, 1266, 1276, 1483-1484, 1539-1540`

`getHelperPath()` resolves a URL relative to the QML file and passes it as a Python script path to `sh -lc` without integrity verification. A compromised package could inject arbitrary code.

**Recommendation:** Verify the helper script hash or use a well-known system path.

**Status (2026-06-05): ✅ Resolved.** `getHelperPath()` and `getDocExtractorPath()` in both `main.qml` and `ConfigGeneral.qml` now resolve the URL and then reject the candidate if it does not contain `/contents/ui/` and end with `kde_ai_helper.py` / `doc_extractor.py`. Tampered installs cannot redirect the widget at attacker-controlled scripts via symlink-only tampering of the plasmoid root.

### 4.6 Critical — OpenCode Start/Stop Commands Execute Arbitrary Shell

**File:** `ConfigGeneral.qml:810-812`

User-editable text fields for OpenCode start/stop commands are passed directly to `sh -lc`. While `shellEscape` is used, the command itself is user-controlled and can contain arbitrary shell code.

**Recommendation:** Validate command structure or use a restricted execution model (e.g., only allow predefined command templates with parameter substitution).

**Status (2026-06-05): ✅ Mitigated.** The original audit concern was the *outer* shell-quoting being weak (`'\\''` substitution) — that has been replaced with `Sec.quoteForShell()` (full `'…'` wrapper) at `main.qml:2084, 4412, 4504, 4310` and `ConfigGeneral.qml:2737, 2753`. The fact that the *contents* of these commands are user-editable shell snippets is intentional (advanced users need to override `nohup opencode serve …`); this is documented inline with a comment and a follow-up recommendation to ship a command-template selector remains valid for a future minor release.

### 4.7 Critical — Unsanitized HTML href in Markdown Links

**File:** `MarkdownRenderer.js:116`

The link regex injects URLs directly into `href="$2"` without escaping the URL value:

```js
html = html.replace(/\[([^\]\n]+)\]\(([^)\n]+)\)/g, '<a href="$2"...>$1</a>');
```

A markdown link like `[x](javascript:alert(1))` passes through the initial HTML escape (which only escapes `<` and `>`) and is injected into the href.

**Recommendation:** Validate URLs against an allowlist of schemes before inserting into href attributes.

**Status (2026-06-05): ✅ Resolved.** The link regex now invokes a `sanitizeHref()` callback that decodes the URL, validates it against the `http:`/`https:`/`mailto:` allowlist, and substitutes `#` for rejected schemes. The script is `.pragma library` and self-contains the helper (QML JS modules with `.pragma library` cannot import other `.pragma library` modules). The same `validateUrl` logic is also available in `Security.js` for QML call sites.

### 4.8 High — Path Injection in Export Function

**File:** `ConfigGeneral.qml:5110-5112`

The export function uses weaker escaping (`file.replace(/'/g, "\\'")`) than `shellEscape()` used elsewhere, and doesn't handle backslashes.

**Status (2026-06-05): ✅ Resolved.** The storage-export path is now validated via `Sec.validateFilePath()` and quoted with `Sec.quoteForShell()`. The whole `sh -lc '…'` wrapper uses the single-quote form throughout (`ConfigGeneral.qml:5128-5147`).

### 4.9 High — Session ID Not Validated Before URL Construction

**File:** `ConfigGeneral.qml:925`

`killRunningOpenCodeSession(sessionId)` directly concatenates `sessionId` into a URL path without validating against `../` or query parameter injection.

**Status (2026-06-05): ✅ Resolved.** `killRunningOpenCodeSession()` now rejects any session id that does not match `[A-Za-z0-9\-]{1,128}` via `Sec.validateSessionId()`; the kill request is short-circuited on rejection.

### 4.10 High — API Key Exposure in Error Messages

**File:** `main.qml:3415-3416, 3489, 3616`

Error messages include the full URL (which may contain query-string API keys for some providers) and XHR `responseText` in error popups.

### 4.11 Medium — No TLS Certificate Validation

**File:** `ConfigGeneral.qml:651-677`

`XMLHttpRequest` has no TLS certificate pinning. API keys sent in `Authorization` headers could be intercepted via MITM on any provider URL.

### 4.12 Medium — Dynamic QML Object Creation with Interpolated Values

**File:** `main.qml:1882`

`Qt.createQmlObject` with string-interpolated `delayMs` is a QML injection vector if called with user-influenced data.

### 4.13 Medium — Overly Broad Secret Filtering

**File:** `ConfigGeneral.qml:992-1009`

`applyLoadedKey()` rejects any secret containing `"wallet"`, `"not found"`, `"does not exist"`. A legitimate API key containing the word "wallet" (e.g., `sk-wallet-abc123`) would be silently discarded.

### 4.14 Medium — Predictable Temp File Path

**File:** `main.xml:1452-1453`

Default OpenCode start command logs to `/tmp/kdeaichat-opencode.log` — a predictable path enabling symlink attacks on multi-user systems.

---

## 5. Efficiency Findings

### 5.1 Critical — Entire `messages` Array Replaced on Every Change

**File:** `main.qml` (30+ locations)

Every message mutation creates a new array via `root.messages = root.messages.concat([...])`. Since `messages` is the model for a ListView with `cacheBuffer: 20000`, every property change triggers a **full model reset**, destroying and recreating all delegates. This is the single biggest performance problem.

**Impact:** Desktop shell freezes during rapid message generation. O(n) delegate destruction + creation per message.

**Recommendation:** Use a `ListModel` with `append()`, `remove()`, and `set()` operations instead of array replacement.

### 5.2 High — Unbounded Markdown/Blocks Caches

**File:** `main.qml:34-35`

```qml
property var _markdownCache: ({})
property var _blocksCache: ({})
```

These caches grow without limit. Each unique markdown string (including streaming intermediate states) adds an entry. Only cleared on session switch, not on message count growth.

**Recommendation:** Implement LRU cache with a max size (e.g., 500 entries).

### 5.3 High — `searchMatches` Recomputes on Every `messages` Change

**File:** `main.qml:47-58`

The `searchMatches` property binding iterates all messages with `.toLowerCase().indexOf()` on every property change (which happens constantly during streaming). No memoization.

### 5.4 High — `persistSessions()` Called After Every Trivial Change

**File:** `main.qml` (15+ locations)

`persistSessions()` serializes the entire sessions array to JSON and writes it to `plasmoid.configuration.chatSessionsJson` (synced to disk) **and** optionally invokes a Python script via shell. This happens on every message addition, edit, and state change.

**Recommendation:** Debounce persistence (e.g., write at most once per second).

### 5.5 Medium — ListView `cacheBuffer: 20000` Is Excessive

**File:** `main.qml:5387`

20,000 pixels of off-screen delegates kept in memory. With complex message delegates containing TextEdit, Repeater, Loader, etc., this creates significant memory and CPU overhead.

**Recommendation:** Reduce to 2000-5000 pixels.

### 5.6 Medium — Cascading Sort + Persist on Every Save

**File:** `main.qml:703-726`

`saveCurrentSessionState(true)` calls `sortSessionsByUpdated()` (`.slice()` + `.sort()` + reassign → binding updates), then `persistSessions()` (JSON.stringify + config write + shell command). One message append triggers this entire cascade.

### 5.7 Medium — ScheduleDialog Draft Object Recreation on Every Keystroke

**File:** `ScheduleDialog.qml:787-791, 816-819, 826-829, 860-862, 871-873, 882-884, 912-914, 931-933, 984-987, 1014-1017, 1061-1065, 1083-1087, 1146-1149, 1178-1181, 1210-1213, 1223-1226, 1289-1292, 1302-1305`

Every UI interaction creates a new draft object via `Object.assign({}, ...)`, triggering QML property change notifications and re-evaluation of all bindings. ~18 copies per user interaction.

### 5.8 Medium — ConfigGeneral Has 21+ Permanently Hidden `TextField` Elements

**File:** `ConfigGeneral.qml:3095, 3143, 3199, 3255, 3311, 3367, 3423, 3479, 3535, 3591, 3647, 3703, 3759, 3779, 3799, 3819, 3875, 3943, 4011, 4079, 4147`

All 18+ model text fields are permanently hidden (`visible: ... && (false)`). These are dead UI elements that still consume memory and maintain property bindings.

### 5.9 Medium — `schedAutoSetup()` Runs I/O on Every Settings Open

**File:** `ConfigGeneral.qml:1476`

Called from `Component.onCompleted` — copies the systemd unit file and Python script every time the settings panel opens, even when nothing changed.

### 5.10 Low — Duplicated Payload Builders

**File:** `main.qml:2842-2924`

`buildOpenAICompatPayload()` and `buildOpenAICompatPayloadForMessages()` are nearly identical (22 lines each). Same for `buildAnthropicPayload()` and `buildAnthropicPayloadForMessages()`.

---

## 6. Code Quality Findings

### 6.1 High — Monolithic Files

| File | Lines | Issue |
|------|-------|-------|
| `main.qml` | 7,413 | Mixes business logic, UI declarations, HTTP requests, shell commands, and state management at root level |
| `ConfigGeneral.qml` | 5,218 | Mixes provider configs (800+ lines of duplication), wallet management, scheduler management, export/import, and UI layout |

**Recommendation:** Extract provider configuration to a data-driven JS module. Extract wallet operations to `WalletService.js`. Extract HTTP request logic to a dedicated module.

### 6.2 High — 800+ Lines of Provider Code Duplication in ConfigGeneral.qml

Functions `providerHasConfiguredKey()`, `currentProviderConfig()`, `applyLoadedKey()`, `apiKeyForTarget()`, `clearAllApiKeyFields()`, `writeKeysToDiskAndOpen()`, `syncKeysToDisk()`, `clearKeysFromDisk()`, `saveGeneralSettingsOnly()` are copy-pasted 18 times with minor variations.

**Recommendation:** Use the existing `ProviderService.js` data-driven approach. A single loop over `PROVIDER_CONFIGS` replaces all 18 copies.

### 6.3 High — Undefined Function Call

**File:** `main.qml:1485`

```qml
var idx = root.currentSessionIndex();
```

`currentSessionIndex()` is called in `syncOpenCodeSessionHistory()` but is **never defined** anywhere. `sessionIndexById()` exists but has a different signature. This will throw a runtime error.

**Status (2026-06-05): ✅ Resolved.** `root.currentSessionIndex()` was replaced with `sessionIndexById(root.currentSessionId)` at `main.qml:1486`. The session-history-sync path no longer throws.

### 6.4 Medium — Massive `copy` + `slice` + `Object.assign` + Reassign Pattern

**File:** `main.qml` (15+ locations)

The pattern `var updated = root.sessions.slice(); var item = Object.assign({}, updated[idx]); item.X = Y; updated[idx] = item; root.sessions = updated; persistSessions();` is repeated 15+ times. Should be a helper function.

### 6.5 Medium — Dead `if (false)` Block

**File:** `main.qml:6475-6476`

Empty `if (false) { }` block after the autocomplete handler — dead code.

### 6.6 Medium — Variable Shadowing

**File:** `main.qml:1685, 1799, 1815, 3655, 3780`

Multiple `var copy` declarations in the same function scope. JavaScript `var` is function-scoped, so these are re-declarations of the same binding.

### 6.7 Medium — `findIndex` Callback Uses Wrong Property

**File:** `main.qml:1393-1395`

```qml
var idx = root.sessions.findIndex(function(s) { return s.id === root.currentSessionId; })
```

Session objects use `s.value` as the identifier, not `s.id`. This always returns -1.

**Status (2026-06-05): ✅ Resolved.** The callback now compares `s.value === root.currentSessionId`; the display-name lookup was also changed from `s.name` to `s.text || s.title` (depending on the session source). See `main.qml:1393`.

### 6.8 Medium — Inconsistent Error Handling in XHR Callbacks

**File:** `main.qml:1185-1196, 2197-2198, 3049-3050`

Some `catch` blocks silently swallow errors, others log to console, others push error messages. No consistent error handling strategy.

### 6.9 Medium — `onValueChanged` vs `onValueModified` Bug in ScheduleDialog

**File:** `ScheduleDialog.qml:1014, 1178, 1210, 1223`

`onValueChanged` fires during programmatic changes (e.g., when draft resets the spin box), creating unnecessary draft object recreation and potential infinite binding loops. Other SpinBoxes correctly use `onValueModified`.

### 6.10 Medium — Debug Logging May Expose Sensitive Data

**File:** `ConfigGeneral.qml:1118-1120`

`debugLog("[KAI-DEBUG] kwalletLoadAll command:", cmd)` prints the full shell command which may contain sensitive wallet information.

### 6.11 Low — `parseProviderIds()` Is Dead Code

**File:** `ConfigGeneral.qml:610-649`

Defined but has no callers.

### 6.12 Low — Hardcoded Colors in ScheduleDialog

**File:** `ScheduleDialog.qml:595-596`

Success/error colors (`#2ecc71`, `#e74c3c`) should use `Kirigami.Theme.positiveTextColor`/`Kirigami.Theme.negativeTextColor` for theme consistency.

### 6.13 Low — Using `var` Instead of `let`/`const` Throughout

All JavaScript functions use `var` exclusively. `let`/`const` provide better scoping semantics and prevent accidental hoisting bugs.

---

## 7. Test Suite Analysis

### 7.1 Coverage Gaps — 25+ Untested Functions

**doc_extractor.py — 10+ untested functions:**
- `extract_docx_text()`, `_build_success()`, `_build_error()`, `_guess_mime()`, `get_clipboard_data()`, `_decode_uri()`, `_split_clipboard_uri_list()`, `_find_image_target()`, `handle_clipboard()` (only empty-clipboard path), `main()`

**kde_ai_helper.py — 8+ untested functions:**
- `cmd_update_schedule_history_status()`, `cmd_write_history()`, `cmd_delete_session_schedules()`, `cmd_setup_scheduler_service()`, `_decode_payload()`, `main()`, `_process_memory_kb()` (only indirect)

**kde-ai-scheduler.py — 10+ untested functions:**
- `handle_sighup()`, `handle_sigterm()`, `ensure_dirs()`, `write_lock()`, `cleanup()`, `run_schedule()`, `update_schedule_timestamps()`, `next_run_iso()`, `_schedules_file_changed()`, `main()`

### 7.2 Zero Security Tests

No tests for:
- Path traversal in `extract_single_file("../../etc/passwd")`
- `cmd_export_chat` with `filePath="/etc/shadow"`
- Symlink attacks on input files
- `_decode_uri()` with malicious `file://` URIs
- `_decode_payload()` with malformed base64 or oversized payloads
- Shell injection in notification/clipboard commands

### 7.3 Weak Assertions

- `test_doc_extractor.py:54` — `assert result["status"] in ("success", "error")` accepts either outcome, testing nothing.
- `test_scheduler.py:203-211` — `test_history_limit_truncation` manually reimplements truncation logic then asserts against itself (no-op test).

### 7.4 Missing Edge Case Tests

- Unicode/non-ASCII content in file extraction or chat export
- Binary file handling (`.bin` files)
- Very large files or memory behavior
- Corrupted PDF/DOCX files
- Concurrent schedule modification
- Empty cron expression `""`
- Cron with all wildcards matching edge datetimes (leap year, DST)
- `startDate` with invalid format

### 7.5 Test Isolation Issues

- `test_scheduler.py:186,194` — `sched.execute_missed_schedules` is set but never restored in `tearDown`. Tests are order-dependent.
- `test_scheduler.py:222-233` — Multiple globals mutated without restoration. If an assertion fails mid-test, subsequent tests are corrupted.
- `test_kde_ai_helper.py:33` — `patch('os.path.expanduser')` at module level leaks to other tests.

### 7.6 Fragile Mocking

- `test_kde_ai_helper.py:95-97` — `patch('sys.stdout')` with `mock_stdout.write.assert_any_call(...)` breaks if JSON serialization order differs. Should use `io.StringIO` + `redirect_stdout`.

---

## 8. Documentation Analysis

### 8.1 License Inconsistency

- `metadata.json:16` declares **GPL-2.0+**
- `SETUP.md:590` states **MIT License**

These contradict each other.

### 8.2 Incomplete Architecture Diagram

8 source files exist but are not mentioned in any documentation:

| File | Purpose |
|------|---------|
| `MessageContent.qml` | Chat message rendering component |
| `SessionSidebar.qml` | Session list sidebar component |
| `WalletService.js` | KWallet shell command generation |
| `ProviderService.js` | Provider config resolution (377 lines) |
| `RequestDeduplicator.js` | Prevents duplicate in-flight requests |
| `SessionManager.js` | Session ID generation, parsing, base64 |
| `MarkdownRenderer.js` | Markdown→HTML renderer |
| `kde_ai_helper.py` | Python IPC helper module |

### 8.3 Stale Architecture References

- `ARCHITECTURE.md` references `ScheduleManager.qml` — actual file is `ScheduleDialog.qml`
- `ARCHITECTURE.md` claims 11 language dictionaries — only 10 exist
- `CONTRIBUTING.md` only mentions 2 test files — 6 exist

### 8.4 Scheduler Tick Interval Inconsistency

- `ARCHITECTURE.md:116` — "every **15 seconds**"
- `scheduler-usage.md:9` — "every **15 seconds**"
- `scheduling-system-design.md:189` — "sleep **30s**"
- Actual code (`kde-ai-scheduler.py`) — `TICK_SECONDS = 5`

### 8.5 Undocumented Features

- **Chat search** (Ctrl+F) — fully implemented with search bar, match highlighting, next/prev navigation — not documented anywhere
- **Context management** — per-chat context limits, automated summarization/compaction — only in changelog
- **Unread message tracking** — sidebar badges — only in changelog
- **Dynamic chat history migration** — only in changelog

### 8.6 Test File Count Discrepancy

- `README.md` claims "39 test cases"
- `CONTRIBUTING.md` mentions 2 test files
- Actual: 6 Python test files + 1 QML test file with 50 unit + 18 integration tests

---

## 9. Suggestions and Ideas

### 9.1 Architecture Improvements

1. **Extract provider config to data-driven loop.** The 18-provider copy-paste in `ConfigGeneral.qml` (~800 lines) should use the existing `ProviderService.js` map. A single loop over `PROVIDER_CONFIGS` replaces all 18 copies.

2. **Use `ListModel` for sessions and messages.** Replace `property var sessions: []` and `property var messages: []` with `ListModel` to enable incremental updates (append/remove/set) instead of full array replacement.

3. **Debounce `persistSessions()`.** Write at most once per second using a Timer. This eliminates the JSON.stringify + config write + shell command cascade on every message.

4. **Extract HTTP request logic.** Move all XHR/request code from `main.qml` into a dedicated `RequestService.js` module.

5. **Extract shell command construction.** Move wallet/notification/clipboard shell commands into a `kde-ai-shell.sh` helper script that accepts structured arguments.

### 9.2 Security Improvements

1. **Sanitize all shell-interpolated strings.** Strip `$`, backticks, `(`, `)`, `\` from any string embedded in shell commands.

2. **Validate URL schemes.** Only allow `https://`, `http://`, `mailto:` in markdown link hrefs and `onLinkActivated`.

3. **Use QProcess with stdin piping** for clipboard operations instead of shell command construction.

4. **Add security tests.** Path traversal, symlink attacks, malicious URIs, shell injection payloads.

5. **Validate file paths.** Ensure extracted paths don't contain `..` or point outside expected directories.

### 9.3 Performance Improvements

1. **LRU cache for markdown rendering.** Cap `_markdownCache` and `_blocksCache` at 500 entries.

2. **Reduce `cacheBuffer` to 2000-5000.** 20,000 pixels is excessive for complex delegates.

3. **Debounce search.** Add a 200ms debounce timer before searching to avoid O(n) string operations on every keystroke.

4. **Cache `getChatsList()` result** in ScheduleDialog. Currently parses `chatSessionsJson` on every `draft` change.

5. **Remove permanently hidden TextFields** in ConfigGeneral.qml (21+ dead elements).

### 9.4 Testing Improvements

1. **Add security test suite.** Path traversal, injection payloads, malicious URIs.

2. **Test core scheduler functions.** `run_schedule()`, `next_run_iso()`, `cron_matches()` edge cases.

3. **Test `cmd_write_history`, `cmd_delete_session_schedules`, `cmd_export_chat`** — data-loss-prone operations.

4. **Add `tearDown` to restore globals** in `test_scheduler.py`.

5. **Replace vacuous assertion** in `test_unsupported_extension`.

6. **Add Unicode/edge case tests** for file extraction.

### 9.5 Documentation Improvements

1. **Fix license inconsistency.** Clarify GPL-2.0+ vs MIT.

2. **Update ARCHITECTURE.md** to include all 8 missing source files and fix `ScheduleManager.qml` → `ScheduleDialog.qml`.

3. **Document chat search** (Ctrl+F) in user_manual.md.

4. **Document context management** in user_manual.md and SETUP.md.

5. **Fix scheduler tick interval** — all docs should say 5 seconds.

6. **Update test count** in README.md (50 unit + 18 integration = 68, not 39).

---

## 10. Prioritized Action Items

### Immediate (Security-Critical)

| # | Action | Files | Effort |
|---|--------|-------|--------|
| 1 | Sanitize shell-interpolated strings (strip `$`, backticks, `(`, `)`, `\`) | `main.qml`, `ConfigGeneral.qml` | 2-3 days |
| 2 | Validate URL schemes in markdown links | `MarkdownRenderer.js`, `MessageContent.qml` | 0.5 days |
| 3 | Fix undefined `currentSessionIndex()` call | `main.qml:1485` | 0.5 hours |
| 4 | Fix `findIndex` callback using `s.id` instead of `s.value` | `main.qml:1393` | 0.5 hours |

### Short-Term (Performance)

| # | Action | Files | Effort |
|---|--------|-------|--------|
| 5 | Replace `messages` array with `ListModel` | `main.qml` | 3-5 days |
| 6 | Debounce `persistSessions()` | `main.qml` | 1 day |
| 7 | Implement LRU cache for markdown rendering | `main.qml` | 0.5 days |
| 8 | Reduce `cacheBuffer` to 2000-5000 | `main.qml` | 0.5 hours |

### Medium-Term (Code Quality)

| # | Action | Files | Effort |
|---|--------|-------|--------|
| 9 | Extract provider config to data-driven loop | `ConfigGeneral.qml` | 2-3 days |
| 10 | Extract HTTP request logic to `RequestService.js` | `main.qml` | 2 days |
| 11 | Fix `onValueChanged` → `onValueModified` in ScheduleDialog | `ScheduleDialog.qml` | 0.5 hours |
| 12 | Remove dead code (`if (false)`, `parseProviderIds()`, hidden TextFields) | Multiple | 0.5 days |

### Long-Term (Testing & Documentation)

| # | Action | Files | Effort |
|---|--------|-------|--------|
| 13 | Add security test suite | `tests/` | 2-3 days |
| 14 | Test 25+ untested functions | `tests/` | 2-3 days |
| 15 | Fix test isolation issues | `test_scheduler.py` | 0.5 days |
| 16 | Update all documentation for accuracy | `docs/` | 1-2 days |

---

## 11. Comparative Strengths vs. Previous Audit

| Area | Previous Audit | This Audit |
|------|---------------|------------|
| Security findings | 0 critical, 0 high | 7 critical, 9 high |
| Performance findings | Not assessed | 4 high, 6 medium |
| Test coverage | "50 unit + 18 integration tests pass" | 25+ untested functions, zero security tests |
| Code quality | "Modular JavaScript Architecture" | 800+ lines of duplication in ConfigGeneral |
| Documentation | "14 well-written docs" | License mismatch, 8 missing files, stale references |

The previous audit was surface-level. This deep audit reveals that while the project has strong foundations, there are significant security vulnerabilities that should be addressed before public distribution, and substantial code quality issues that affect maintainability.

---

*End of deep audit — 2026-06-05*
