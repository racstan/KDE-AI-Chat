# KDE AI Chat — Lag Audit

> **Goal**: Eliminate all perceived jank — no freezes on send, during AI thinking/streaming, during TTS playback, or on window drag/release.

---

## Architecture Summary

The widget runs entirely on the **Qt/QML main thread**. All JS functions (`MainDatabase.js`, `MainNetwork.js`, etc.) execute synchronously on this thread. Any function that takes >4 ms will cause dropped frames at 60 Hz.

Asynchronous work is done through:
- `XMLHttpRequest` (non-blocking network)
- `P5Support.DataSource` (shell subprocesses, fully async)
- QML `Timer` for debouncing

---

## Identified Lag Sources (by priority)

### 🔴 CRITICAL

#### 1. `onMessagesChanged` — O(n) parse loop on every token
**File**: `main.qml` L1031–1044  
**Symptom**: Severe jank during streaming; every batch of tokens caused the full message list to be re-parsed.  
**Root cause**: `onMessagesChanged` fired on every `root.messages = root.messages.concat([...])` assignment. Inside the handler, **every message** was checked for `blocks === undefined` and `parseMessageBlocks(content)` was called (full Markdown tokenization) for any unparsed message. During streaming, the last message has no `blocks` yet, so it's re-parsed on every timer tick.  
**Fix applied**: Guard with `if (!root.streamingResponse)` — skip during active streaming. `flushStreamingBuffer()` sets `streamingResponse = false` *before* writing the final message, so the final parse still runs.

#### 2. `checkAndMarkCurrentSessionAsRead` called on every token
**File**: `main.qml` L1044, `MainDatabase.js` L191  
**Symptom**: `root.sessions = updated` + `persistSessions()` fired per-token from `onMessagesChanged`.  
**Root cause**: Same `onMessagesChanged` handler unconditionally called `Qt.callLater(checkAndMarkCurrentSessionAsRead)`, which does a sessions array copy + slice + assignment + debounce trigger.  
**Fix applied**: Same guard as above — only runs when `!root.streamingResponse`.

#### 3. `pushErrorMessage` — synchronous save + synchronous scroll
**File**: `MainNetwork.js` L54  
**Symptom**: Visible freeze when an error arrives (HTTP fail, timeout, network error), including voice errors.  
**Root cause**: `saveCurrentSessionState(true)` called synchronously → `root.sessions = updated` → `sortSessionsByUpdated()` (sort + array reassign) → `persistSessions()` (JSON.stringify on sessions array). Also `scrollToBottom()` was called synchronously.  
**Fix applied**: Use `deferSaveStateTimer.restart()` (debounced) and `Qt.callLater(scrollToBottom)`.

---

### 🟠 HIGH

#### 4. `saveCurrentSessionState(true)` called 40+ times per chat event
**File**: `MainDatabase.js` — 40+ call sites  
**What it does**: `root.sessions.slice()` + `Object.assign` + `root.sessions = updated` + `sortSessionsByUpdated()` + `persistSessions()`.  
**Problem**: `root.sessions = updated` invalidates **all QML bindings** on the sessions array (sidebar list, session title, unread badges). Even when sessions are already sorted, QML re-evaluates every binding that reads `root.sessions`.  
**Mitigation already in place**: `sortSessionsByUpdated()` has an early-exit check via `SessionManager.isSessionOrderCorrect()`. `persistSessions()` uses `persistSessionsDebounce` (1-second debounce).  
**Remaining issue**: The `root.sessions = updated` assignment itself still happens synchronously many times. Each triggers QML property change notifications.  
**Recommended fix**: Batch multiple `saveCurrentSessionState` calls within a single JS call stack into one using a micro-debounce flag.

#### 5. `streamingBatchTimer` interval — 150ms
**File**: `MainDataSources.qml` L173  
**What it does**: Flushes buffered streaming tokens to `root.streamingContent` at ~6.7 Hz.  
**Issue**: At 150ms, each flush triggers `root.streamingContent` change → QML re-render of `MessageContent` → `convertMarkdownToHtml()` on the streaming block.  
**`convertMarkdownToHtml` cost**: Full regex Markdown-to-HTML conversion every 150ms during streaming. The result is cached by content hash, but during streaming the content changes every flush, so the cache never hits.  
**Recommended fix**: During streaming, render `streamingContent` as plain text (no Markdown conversion). Apply Markdown only when the final `flushStreamingBuffer()` commits the message.

#### 6. `convertMarkdownToHtml` on every `streamingContent` update
**File**: `MessageContent.qml` L208  
**Root cause**: The streaming bubble uses `MessageContent` with the same `convertMarkdownToHtml` path as completed messages. The LRU cache (`_markdownCache`) holds the last N entries, but growing streaming text never hits the cache since the string changes on every flush.  
**Cost**: Full MarkdownRenderer.js parse + regex pipeline on potentially kilobytes of text every 150ms.

---

### 🟡 MEDIUM

#### 7. `voiceStatusPollTimer` — 250ms HTTP poll
**File**: `MainDataSources.qml` L705  
**What it does**: While `root.voiceRecording || root.ttsPlaying` is true, fires an `XMLHttpRequest` every 250ms to `http://127.0.0.1:{9015|9016}/status`.  
**Impact**: Each XHR creates a network request object, fires `onreadystatechange`, calls `handleVoiceResponse()` which may set QML properties (`root.ttsPlaying`, `root.ttsPaused`). Setting these properties during drag/resize events compounds with the render cost.  
**Note**: 250ms is already reasonable. Increasing to 400ms when not actively tracking countdown would reduce impact.

#### 8. `onMessagesChanged` — inner loop on all existing messages
**File**: `main.qml` L1031–1039  
**Current state**: The loop is now guarded by `!root.streamingResponse`. But it still runs on every non-streaming `root.messages` assignment, re-checking all N messages for unparsed blocks.  
**Cost**: O(n) loop; for long chats (100+ messages), each non-streaming write (e.g. error message, session switch, background schedule message) parses all messages. The `lastParsedContent` check avoids re-parsing already-parsed messages, but the loop itself takes O(n) time.  
**Recommended fix**: Track the index of the last parsed message and only check from that index forward.

#### 9. Plasma popup drag-release lag
**Symptom**: Window "sticks" briefly when released after dragging.  
**Root cause**: Not a code bug — this is Plasma's popup compositor behavior. When the popup is moved (via the Plasma panel drag affordance), releasing the mouse causes Plasma to:
  1. Recalculate the popup's anchor/gravity position
  2. Re-layout the containment
  3. Re-evaluate all QML `implicitWidth`/`implicitHeight` bindings recursively
**Our contribution**: Any pending timer callbacks (streaming, polling) that fire *during* the layout recalculation add to the composite delay. The `persistSessionsDebounce` timer (1s) and `streamingBatchTimer` (150ms) can fire at this moment.  
**Recommended fix**: No single fix eliminates Plasma compositor overhead. Reducing the number of active timers when idle helps.

---

### 🟢 LOW / ALREADY MITIGATED

#### 10. `persistSessions()` — JSON.stringify on full sessions array
**File**: `MainDatabase.js` L247  
**Mitigation**: Debounced to 1 Hz via `persistSessionsDebounce`. The actual `plasmoid.configuration.chatSessionsJson = jsonStr` write is the expensive operation (IPC to KDE config system).  
**Remaining**: Still runs `JSON.stringify(root.sessions)` on the full array (potentially many KB). No further optimization without switching storage backends.

#### 11. `sortSessionsByUpdated()` early-exit check
**File**: `MainDatabase.js` L274  
**Mitigation already in place**: `SessionManager.isSessionOrderCorrect()` checks if the array is already sorted and returns early. The O(n log n) sort only runs when order is actually wrong.

#### 12. LRU Markdown cache
**File**: `MainDatabase.js` `_markdownCache` / `LRUCache.js`  
**Mitigation already in place**: Completed messages are cached by (content + theme) key. Cache hits are O(1). Streaming content misses the cache by design (growing string).

---

## Fixes Applied in This Session

| Issue | Fix |
|-------|-----|
| `.import "Security.js"` error in `MainNetwork.js` | Removed invalid `.import` directive |
| `onMessagesChanged` per-token parse | Guarded by `!root.streamingResponse` |
| `checkAndMarkCurrentSessionAsRead` per-token | Same guard |
| `pushErrorMessage` sync save | Switched to `deferSaveStateTimer` + `Qt.callLater` |
| TTS emoji reading | Strip all Unicode emoji + markdown before TTS |
| File attachments restricted to specific types | Now accepts any file; model decides if usable |

---

## Recommended Future Optimizations

### High Impact

1. **Plain-text streaming** — While `root.streamingResponse` is true, render `streamingContent` as `textFormat: Text.PlainText` instead of calling `convertMarkdownToHtml`. Switch to RichText only when the final message is committed. This eliminates the expensive Markdown parse every 150ms.

2. **Incremental `onMessagesChanged` parse** — Track `_lastParsedMessageIndex` as a module-level variable. In the `onMessagesChanged` guard block, only loop from `_lastParsedMessageIndex` forward instead of from 0.

3. **Batch `saveCurrentSessionState` writes** — Replace the direct `root.sessions = updated` in `saveCurrentSessionState` with a flag + single-shot timer so multiple calls within the same JS turn collapse into one QML binding invalidation.

### Medium Impact

4. **Reduce `voiceStatusPollTimer` frequency** — Poll at 400ms when not tracking STT countdown; 250ms is only needed for the live countdown display.

5. **Increase `streamingBatchTimer` to 200ms** — Reduces Markdown re-render calls to 5 Hz during streaming. Imperceptible to users but saves ~25% of streaming render calls.

6. **Lazy message block parsing** — Use `Loader`/`Component.onCompleted` in `MessageContent.qml` so off-screen messages don't parse until they scroll into the viewport.
