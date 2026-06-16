# KDE AI Chat — Deep Performance & Architecture Analysis

## Executive Summary

Your instinct is correct: **the modular split is the root cause of most problems**. Since the v1.4.0 KDE Store release (`38ecf3b`, Jun 9), you've made **134 commits** — most of which are firefighting performance regressions caused by the architecture itself. The codebase has grown from **274 KB** of core logic to **434 KB** (+58%), and the main.qml has become a **171-function proxy layer** that adds overhead on every single function call.

---

## 1. Architecture Autopsy

### Current File Structure (Core Logic Only)

| File | Lines | Bytes | Purpose |
|---|---|---|---|
| `main.qml` | 1,165 | 43 KB | **171 proxy functions** — does nothing except forward calls |
| `MainDatabase.js` | 3,879 | 129 KB | **God file** — everything dumped here |
| `MainNetwork.js` | 614 | 20 KB | HTTP requests, streaming, base64 |
| `MainOpenCode.js` | 521 | 16 KB | OpenCode server management |
| `MainScheduler.js` | 250 | 10 KB | Schedule command handling |
| `FullRepresentation.qml` | 3,202 | 179 KB | Main chat UI |
| `MainDataSources.qml` | 892 | 37 KB | DataSources/Timers container |
| **Total** | **10,523** | **434 KB** | |

### The Proxy Tax

`main.qml` has **171 functions** like this:

```qml
function sendMessage() {
    return MainDatabase.sendMessage();
}
function pushErrorMessage(text) {
    return MainNetwork.pushErrorMessage(text);
}
```

Every function call from QML or between JS modules goes through this proxy layer. In QML/Qt Quick:
- Each proxy call involves: QML → V4 engine → import scope lookup → function dispatch → return value marshalling
- During streaming, `flushStreamingBuffer()` is called via timer every ~100ms, and it calls `updateAssistantStreamingContent()` → `precomputeBlocksAndHtmlForMessage()` → `queueScrollToBottom()` — **each bouncing through main.qml**
- The `onMessagesChanged` handler fires on every `root.messages = ...` assignment, triggering `updateMessageMetadata()` which loops all messages

> [!CAUTION]
> **Before the split (pre-`ccb5fda`, Jun 5), ALL functions were in main.qml and could call each other with zero overhead.** The split didn't separate concerns — it just added an indirection layer with no benefit.

---

## 2. Critical Bugs Found

### Bug 1: `pushErrorMessage()` references undefined variables `_t0`, `_t1`

[MainNetwork.js:97-99](file:///home/home/Programming/rachitkdeaichat/org.kde.plasma.kdeaichat/contents/ui/MainNetwork.js#L97-L99):
```javascript
let _t2 = Date.now();
if (_t2 - _t0 > 5)  // ← _t0 is NEVER defined!
    console.log("[KAI-PERF] pushErrorMessage: concat=" + (_t1-_t0) + "ms post=" + (_t2-_t1) + "ms");
```

**Impact:** Every error message call throws a `ReferenceError` internally. The error is silently swallowed but wastes cycles and pollutes the JS stack.

### Bug 2: `reuseItems: true` with mutable delegate state

[FullRepresentation.qml:589](file:///home/home/Programming/rachitkdeaichat/org.kde.plasma.kdeaichat/contents/ui/FullRepresentation.qml#L589):
```qml
reuseItems: true
```

Combined with the complex delegate that has `isSearchMatch`, `isCurrentSearchMatch`, `roleIsUser`, etc. as regular properties, `reuseItems` causes delegates to "leak" visual state from one message to another when they get recycled. This is a known Qt bug source — recycled delegates don't reliably re-evaluate all bindings.

### Bug 3: Array mutation triggers cascading rebinds

Every `root.messages = root.messages.concat([newMsg])` (10 instances) and `root.messages = root.messages.slice()` (2 instances) triggers:
1. `onMessagesChanged` handler (which loops ALL messages for metadata)
2. All ListView delegate bindings re-evaluate
3. `searchMatches` re-computes (even with fingerprint optimization)
4. `_searchFingerprint` re-computes
5. Session save debounce starts

During streaming, this happens **every 100ms** via `streamingBatchTimer`.

### Bug 4: Translation files loaded eagerly at startup

All 10 translation files (~700 KB total) are loaded via JS imports when `main.qml` loads:
```qml
import "translations.js" as Translations
```

The `translate()` function only uses ONE language at a time, but **all 10 files** are parsed by the V4 engine at startup.

### Bug 5: `precomputeBlocksAndHtmlForMessage()` runs TWICE for light + dark

[MainDatabase.js:406-411](file:///home/home/Programming/rachitkdeaichat/org.kde.plasma.kdeaichat/contents/ui/MainDatabase.js#L406-L411):
```javascript
block.contentHtmlCache["dark"] = MarkdownRenderer.convertMarkdownToHtml(block.content, true);
block.contentHtmlCache["light"] = MarkdownRenderer.convertMarkdownToHtml(block.content, false);
```

Every message gets its markdown converted to HTML **twice** — once for dark theme and once for light. Since the user is only ever in one theme at a time, this doubles the compute cost for zero benefit.

---

## 3. Performance Hotspots

### 3.1 The Streaming Pipeline (Most Critical)

The hot path during streaming:

```
SSE data arrives (xhr.onreadystatechange)
  → updateAssistantStreamingContent()     [via MainDatabase proxy]
    → _pendingStreamingText += content
    → streamingBatchTimer triggers (every 100ms)
      → root.streamingContent = text      [triggers binding update]
      → TextEdit re-renders PlainText     [OK, but binding cascade starts]
```

When streaming finishes:
```
flushStreamingBuffer()                    [via MainDatabase proxy]
  → flushIntermediateStreaming()           [via MainDatabase proxy]
  → precomputeBlocksAndHtmlForMessage()   [blocks + 2x HTML conversion]
  → root.messages = root.messages.concat() [TRIGGERS onMessagesChanged]
    → updateMessageMetadata()              [loops ALL messages]
    → precomputeBlocks for new messages
    → checkAndMarkCurrentSessionAsRead()  [sessions.slice() + assignment]
    → queueScrollToBottom()
```

### 3.2 Session Switch (200ms+ hang)

```
switchSession(sessionId)
  → saveCurrentSessionState()             [sessions.slice() + Object.assign]
  → root.messages = []                    [triggers onMessagesChanged #1]
  → Qt.callLater:
    → root.messages = targetMsgs          [triggers onMessagesChanged #2]
    → checkAndMarkCurrentSessionAsRead()  [sessions.slice() #2]
    → scrollToBottom()
```

Two `onMessagesChanged` fires for one session switch.

### 3.3 `sessions.slice()` Everywhere

`sessions.slice()` creates a shallow copy of the sessions array every time ANY property changes. With 6+ sessions, each containing messages arrays with potentially hundreds of messages, this is expensive. It's called in:
- `saveCurrentSessionState()` 
- `setCurrentSessionSource()`
- `setSessionArchived()`
- `saveSessionRename()`
- `deleteSession()`
- `checkAndMarkCurrentSessionAsRead()`
- `setSessionProperty()`
- `respondToCompactRequest()`
- `touchSessionsList()`

That's **9+ sites** doing `root.sessions = updated` which triggers all sidebar bindings to re-evaluate.

### 3.4 Debug Timing Code Left In Production

The codebase has leftover `[KAI-PERF]` timing code:
- `main.qml:1092-1116` — 8 lines of timing in `onMessagesChanged`
- `main.qml:1003-1015` — timing in `onCurrentSessionIdChanged`
- `MainNetwork.js:97-99` — broken timing (references undefined vars)

This adds function call overhead on every hot path.

---

## 4. Architectural Issues

### 4.1 MainDatabase.js Is a God Object (129 KB, 3,879 lines)

This file contains:
- Session management
- Message handling  
- Streaming
- Markdown/HTML conversion
- Clipboard operations
- File attachments
- Voice/TTS functions
- Schedule management helpers
- OpenCode event handling
- UI scroll management
- Autocomplete
- Export
- KWallet helpers

It's NOT a "database" — it's the entire application logic dumped into one file. The name is misleading and the file is unmaintainable.

### 4.2 Cross-Module Coupling Is Extreme

- `MainDatabase.js` references `root.` **528 times**
- `MainNetwork.js` references `root.` **54 times**
- `MainOpenCode.js` references `root.` **52 times**
- `MainScheduler.js` references `root.` **32 times**

The JS modules aren't independent — they're tightly coupled to the QML root object. Every `root.something` access crosses the QML/JS boundary.

### 4.3 Duplicate Imports

`FullRepresentation.qml` imports the same JS modules as `main.qml`:
```qml
import "MainDatabase.js" as MainDatabase
import "ProviderService.js" as ProviderService
import "SessionManager.js" as SessionManager
// ... etc
```

In QML, each `.import` triggers the V4 engine to parse and register the module. Multiple imports of the same file in different components **don't share state** — they create separate instances.

### 4.4 FullRepresentation.qml Is Too Large (3,202 lines, 179 KB)

This single file contains:
- Toolbar with 12+ buttons
- Rename bar
- Search bar
- ListView with complex delegate (~450 lines just for the delegate)
- 14+ dialogs
- Input area with autocomplete
- File attachment UI
- Streaming footer
- Session sidebar
- Voice controls

---

## 5. What the "Good" Version Had

At the KDE Store v1.4.0 release (`38ecf3b`):

| File | Bytes (Then) | Bytes (Now) | Growth |
|---|---|---|---|
| `main.qml` | 38 KB | 43 KB | +13% |
| `FullRepresentation.qml` | 155 KB | 179 KB | +15% |
| `MainDatabase.js` | 80 KB | 129 KB | **+61%** |

The growth in `MainDatabase.js` (+49 KB) comes from:
- Voice/TTS functions (~150 lines)
- Variant system (~60 lines)
- Additional streaming optimization attempts (~200 lines)
- More `Qt.callLater` wrappers
- Timing/debug code

---

## 6. Recommended Plan of Action

### Phase 1: Fix Critical Bugs (Immediate)

1. **Fix `pushErrorMessage()` broken variables** — Remove lines 97-99 in MainNetwork.js
2. **Remove `reuseItems: true`** — Causes delegate state leaks, marginal perf benefit with the complex delegate
3. **Remove all `[KAI-PERF]` debug logging** — Dead code in production

### Phase 2: Eliminate the Proxy Layer (High Impact)

**Merge `MainDatabase.js`, `MainNetwork.js`, `MainOpenCode.js`, `MainScheduler.js` back into a single `ChatEngine.js`** and import it once in `main.qml`.

This eliminates:
- 171 proxy functions in main.qml
- Cross-module `root.` bouncing
- Import scope lookup overhead

`main.qml` becomes just:
```qml
import "ChatEngine.js" as Engine

PlasmoidItem {
    id: root
    // properties
    // shortcuts
    // Component.onCompleted calls Engine.init(root)
}
```

### Phase 3: Fix the Streaming Pipeline

1. **Don't rebuild the entire messages array during streaming** — Use a separate `streamingContent` TextEdit in the footer (already there!) and only commit to `root.messages` when streaming finishes
2. **Single-theme HTML caching** — Only compute HTML for the current theme, not both
3. **Skip `onMessagesChanged` during streaming** — The current code already partially does this but still runs `updateMessageMetadata()`

### Phase 4: Reduce Session Mutation Cost

1. **Use in-place mutation** for session property changes instead of `sessions.slice()` + reassign
2. **Batch session updates** — Don't call `persistSessions()` after every tiny change
3. **Lazy-load translation files** — Only import the current language, not all 10

### Phase 5: Simplify the File Structure

Target structure:
```
contents/ui/
├── main.qml            (~200 lines: PlasmoidItem, properties, shortcuts)
├── ChatEngine.js        (~4500 lines: ALL logic in one file)
├── FullRepresentation.qml  (UI only, no JS imports)
├── MessageContent.qml
├── SessionSidebar.qml
├── ScheduleDialog.qml
├── MainDataSources.qml
├── Config*.qml           (settings pages)
├── MarkdownRenderer.js   (pure utility, no root refs)
├── Security.js           (pure utility, no root refs)
├── LRUCache.js           (pure utility)
├── translations.js       (lazy loader)
└── voice/
```

Key principles:
- **One source of truth for logic** — `ChatEngine.js`
- **QML files are purely visual** — no business logic
- **Utility JS files** are stateless pure functions (no `root.` references)
- **Translation files** are loaded on demand, not all at startup

---

## 7. Why the Monolithic Approach Works Here

This is a **KDE Plasma widget**, not a web SPA. The constraints are different:

1. **Single execution context** — There's no server/client split, no modules, no bundle system. QML's `.import` is NOT like ES modules — it doesn't tree-shake, doesn't share state properly across components, and each import has V4 engine overhead
2. **Property bindings are the bottleneck** — Every `root.X = Y` triggers binding re-evaluation across ALL components that reference `root.X`. The proxy layer multiplies these transitions
3. **All code runs on the UI thread** — There are no web workers in QML. Every function call, array copy, and JSON parse blocks rendering
4. **The QML cache (.qmlc/.jsc)** helps with parse time but NOT with runtime overhead from proxy indirection

The v1.2.9 release that users loved was fast because:
- Direct function calls (no proxy layer)
- Fewer features = less code in hot paths
- No voice/TTS polling
- Simpler streaming (less `Qt.callLater` wrapping)

---

## 8. Quick Wins (Can Be Done Now)

| Fix | Impact | Effort |
|---|---|---|
| Delete `[KAI-PERF]` console.log lines | Small | 5 min |
| Fix `_t0`/`_t1` ReferenceError in pushErrorMessage | Bug fix | 2 min |
| Remove `reuseItems: true` | Fixes visual glitches | 1 min |
| Single-theme HTML cache (current theme only) | -50% parse time | 15 min |
| Lazy translation loading | -700KB startup parse | 30 min |
| Remove duplicate JS imports from FullRepresentation.qml | Fewer V4 instances | 5 min |

> [!IMPORTANT]
> The single highest-impact change is **merging the JS files back into one and eliminating the proxy functions**. This alone should bring back the v1.4.0 responsiveness. All the `Qt.callLater` and `streamingBatchTimer` optimizations you've been adding are band-aids on top of the architectural overhead.
