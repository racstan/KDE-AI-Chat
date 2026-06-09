# KDE AI Chat — Audit Report (Part 2)

## 🟠 Priority 3 — HIGH: FullRepresentation.qml Unqualified Calls

FullRepresentation.qml calls several functions **without `root.` prefix** that are
defined on the parent `root` object. These work because QML resolves identifiers up
the object tree to the PlasmoidItem.

### P3-A: `debugLog()` called without `root.` prefix

| Lines | Call |
|---|---|
| 175, 177, 2003, 2010, 2027, 2028 | `debugLog(...)` |

**Status:** Works because QML walks up to root. Low risk, but should be `root.debugLog()`.

### P3-B: `base64Encode()` / `getHelperPath()` called without `root.`

| Lines | Function |
|---|---|
| 1210, 2577, 2613 | `base64Encode(...)` |
| 1211, 2578, 2614 | `getHelperPath()` |

**Status:** Works via QML scope resolution. Low risk but fragile.

**Fix applied:** Prefixed all 6 call sites with `root.`:
```diff
-let b64Payload = base64Encode(JSON.stringify(payload));
-let cmd = "python3 " + Sec.quoteForShell(getHelperPath()) + ...
+let b64Payload = root.base64Encode(JSON.stringify(payload));
+let cmd = "python3 " + Sec.quoteForShell(root.getHelperPath()) + ...
```

**STATUS: ✅ FIXED** (at lines 1210-1211, 2577-2578, 2613-2614)

### P3-C: `schedulerDs`, `schedulerPollTimer` called without `root.`

| Lines | Object |
|---|---|
| 1144, 1272 | `schedulerPollTimer.triggered()` |
| 1212, 2579, 2615 | `schedulerDs.connectSource(...)` |

**Status:** Works via QML property alias resolution on root. Not a bug.

---

## 🟡 Priority 4 — MEDIUM: Streaming Display Architecture

### P4-A: Streaming Bubble → Permanent Message Transition Broken

The streaming response display in `FullRepresentation.qml:590-628` renders a
"live" bubble based on `root.streamingResponse` and `root.streamingContent`. This is
**architecturally sound**.

**However:** Because `flushStreamingBuffer()` was broken (P1-A), the transition from
streaming bubble → permanent message bubble **never happened**:

1. While streaming: text appears in the streaming bubble ✅
2. When streaming ends: `flushStreamingBuffer()` fails → streaming bubble disappears,
   but no message is added to `root.messages` → **response vanishes** ❌

**Fix:** Resolved by P1-A fix. ✅

---

## 🟡 Priority 5 — MEDIUM: OpenCode Connectivity

### P5-A: OpenCode Server Discovery Chain

The OpenCode integration chain:
1. `doOpenCodeRequest()` → `ensureOpenCodeServerRunning()` → health check → auto-start
2. `ensureCurrentOpenCodeSession()` → POST `/session` → get remote session ID
3. POST `/session/{id}/message` → send user message
4. `ensureOpenCodeEventStream()` → GET `/event` (SSE) → `handleOpenCodeEvent()`

**Root cause of "OpenCode unreachable" reports:** `finishOpenCodeRequest()` in
`MainNetwork.js:30` calls `flushStreamingBuffer()`. If this throws (P1-A), the function
aborts before resetting `root.loading = false`, leaving the app stuck with `loading = true`
and no way to send more messages.

**Fix:** Resolved by P1-A fix. ✅

### P5-B: OpenCode Base URL Configuration

Verified: `root.openCodeBaseUrlVal` correctly defaults to `http://127.0.0.1:4096`.
Not a bug. ✅

---

## 🟡 Priority 6 — MEDIUM: Scheduler Issues

### P6-A: Scheduler Poll Mechanism

The `schedulerPollTimer` correctly polls every 3 seconds while expanded. All called
functions (`root.getHelperPath()`, `root.injectScheduledMessage()`, `root.createSession()`)
have working proxies in main.qml. ✅

**If schedules aren't working, check:**
1. Is `kde-ai-scheduler.service` enabled? (`systemctl --user status kde-ai-scheduler.service`)
2. Is the Python helper script accessible? (`python3 <helperPath> poll_pending_triggers`)
3. Is KWallet blocking injection? (see P6-B)

### P6-B: KWallet Blocks Schedule Injection

When `keyStorageMode === 2` (KWallet), the schedule injection in
`MainScheduler.js:52-78` requires KWallet keys to be loaded first. If KWallet is locked
or the password dialog is dismissed, the schedule silently fails to execute.

**Status:** By design — the error path correctly sends a desktop notification.

---

## 🟢 Priority 7 — LOW: Code Quality

### P7-A: `copyToClipboard` Wrong Signature in MainDataSources.qml

```javascript
// MainDataSources.qml:65-67 (BEFORE fix)
function copyToClipboard(textValue) {
    return MainDatabase.copyToClipboard(root, textValue);  // WRONG: extra 'root' arg
}
```

`MainDatabase.copyToClipboard(textValue)` only takes one parameter. The extra `root`
shifts the actual text to the second parameter position.

**Impact:** None currently — this wrapper was never called externally. Dead code.

**STATUS: ✅ FIXED** — removed the extra `root` parameter.

### P7-B: Duplicate Function Definitions

`copyToClipboard` is defined in multiple places:
- `MainDatabase.js:2704` — full implementation
- `MainDataSources.qml:65` — wrapper (now fixed)
- `ConfigGeneral.qml:473` — separate copy for config page
- `ConfigGeneralLogic.js:143` — separate copy for config logic

The config-page copies are independent and correct for their own scope.

---

See `audit3.md` for the complete fix summary and verification checklist.
