# Enhanced Plasmoid Audit - 2026-06-14

Scope: KDE AI Chat plasmoid under `org.kde.plasma.kdeaichat`, with focus on broken scrolling, chat responsiveness, streaming, error handling, voice UX, and reducing monolithic coupling.

## Executive Summary

The current lag is not one bug. It is a pile-up of heavy QML delegates, root-level mutable arrays, frequent model reassignment, executable DataSource side effects, and voice status polling all sharing the Plasma UI thread. The recent commits did move in the right direction by batching streaming text and precomputing message blocks, but the architecture is still fragile enough that small UI changes can break scrolling or make voice/TTS feel sticky.

Highest priority fixes:

1. Restore the June 13 native attached scrollbar in `FullRepresentation.qml`.
2. Remove the fragile visible-message slice and its index mapping.
3. Remove obvious syntax/maintenance hazards: duplicate root aliases and duplicate local declarations.
4. Reduce per-frame QML work in message delegates, especially day-divider counting and search-match expressions.
5. Move voice UI to optimistic, low-frequency status updates; avoid pushing chat error bubbles for transient voice poll failures.

## Current Hot Files

- `org.kde.plasma.kdeaichat/contents/ui/FullRepresentation.qml`: 3,242 lines. Main chat UI, history UI, message delegate, settings dialogs, schedules, voice controls, and custom scrollbar are all in one file.
- `org.kde.plasma.kdeaichat/contents/ui/MainDatabase.js`: 3,500+ functions/lines in practice. Session state, persistence, context compaction, scrolling, prompt construction, files, voice, clipboard, and streaming all live here.
- `org.kde.plasma.kdeaichat/contents/ui/MainDataSources.qml`: executable DataSources, timers, voice polling, persistence debounce, and OpenCode timers.
- `org.kde.plasma.kdeaichat/contents/ui/MessageContent.qml`: delegate body renderer for rich text, code, tables, quote blocks, and images.
- `org.kde.plasma.kdeaichat/contents/ui/MainNetwork.js`: normal API streaming/error paths.
- `org.kde.plasma.kdeaichat/contents/ui/MainOpenCode.js`: OpenCode session and streaming bridge.

## Key Findings

### P0 - Scrollbar Drag Regression - Resolved

The custom scrollbar and visible-message slice were removed. The chat now uses
the June 13 attached `QQC2.ScrollBar.vertical` and `root.messages` directly.

### P0 - Visible Window Index Fragility - Resolved

The ListView model is `root.visibleMessages`, a slice of `root.messages`. Delegates compute `originalIndex` as `index + (root.messages.length - root.visibleMessages.length)`. This is workable, but every direct call to `positionViewAtIndex`, `indexAt`, search, edit, delete, fork, regenerate, quote jump, and day headers must consistently convert between local and original indices.

Impact: jump/search/edit can target the wrong item when older messages are hidden or when `visibleMessagesCount` changes.

Fix applied: the sliced model was removed, so ListView and session indices are identical.

### P1 - Chat Delegate Does Too Much Per Delegate

The delegate computes:

- search matching with `modelData.content.toLowerCase().indexOf(...)`
- day headers via `messageDayKeyAt` and `dayDividerLabelForIndex`
- `dayDividerLabelForIndex` calls `countMessagesForDayKey`, which scans all messages
- rich text rendering in `MessageContent.qml`, with caches attached to block objects

Impact: large chats can stutter during scroll, search, theme changes, or model reset.

Fix: precompute message metadata (`dayKey`, `dayLabel`, `dayCount`, searchable lowercase text) at message insertion/session load time. Keep delegates as simple property readers.

### P1 - Streaming Still Causes Too Many Bottom-Scroll Calls

Streaming text is batched at ~8 Hz, which is good. But `updateAssistantStreamingContent()` still schedules `Qt.callLater(scrollToBottom)` for every incoming chunk when the user is at bottom. If tokens arrive faster than the batch timer, this can queue many redundant scroll calls.

Impact: visible stutter while model responses stream.

Fix: add a small scroll debounce/flag such as `_scrollToBottomPending`, and only queue one bottom scroll per frame/timer cycle.

### P1 - Persistence Is Better but Still Mixed With UI Mutation

`saveCurrentSessionState()` debounces implementation work, but it still calls `persistSessions()` immediately, and `_saveCurrentSessionStateImpl()` can reassign `root.sessions`. Some paths append messages and immediately sort sessions.

Impact: session sidebar and root bindings can refresh during chat-streaming or error paths.

Fix: separate "message write to current chat" from "session sidebar order refresh". During active chat, update the current session object lazily and sort/sidebar-refresh after the response completes.

### P1 - Voice Polling and Error Bubbles Are Too Aggressive

Voice status polls every 500 ms while STT/TTS is active. After four failures it pushes visible chat error messages and resets UI state.

Impact: transient daemon startup or load spikes create noisy chat bubbles and extra message-model changes at the exact time the UI should stay responsive.

Fix: move transient voice failures into a compact status label/toast first. Only add chat errors for user-actionable terminal failures. Slow polling after stable playback/recording.

### P2 - Monolithic Structure Blocks Safe Feature Work

The root object exposes a large API of wrappers into JS files, and several modules reach across IDs through global QML scope. This makes dependencies implicit and hard to test.

Impact: features like memory, scheduling, OpenCode, provider chat, TTS, and STT can break each other through shared root state.

Fix: split by runtime domain:

- `ChatController.js`: message append/edit/delete/search/jump.
- `StreamingController.js`: stream buffering and final commit.
- `SessionStore.js`: sessions, persistence, sorting, read counts.
- `VoiceController.js`: daemon/status/commands.
- `OpenCodeController.js`: OpenCode API/session/event bridge.
- QML components: `ChatList.qml`, `MessageDelegate.qml`, `ChatComposer.qml`, `VoiceControls.qml`, `SchedulePanel.qml`.

## External Documentation Notes

Qt ListView performance depends heavily on delegate complexity and cache behavior. Qt's docs note that `cacheBuffer` creates delegates outside the visible area, so bigger buffers trade memory/startup work for fewer creates during flicking. Qt's ScrollBar docs also state that an attached ScrollBar automatically tracks Flickable geometry, position, size, and active state. This supports minimizing custom scrollbar math unless the fixed-size thumb is a strict design requirement.

Sources checked:

- https://doc.qt.io/qt-6/qml-qtquick-listview.html
- https://doc.qt.io/qt-6/qml-qtquick-controls-scrollbar.html

## Immediate Fix Order

1. Split `ChatList.qml` out of `FullRepresentation.qml`.
2. Route all error insertion through the common message append path.
3. Extract voice state and daemon control into `VoiceController.js`.
4. Replace root array reassignment with a dedicated session/message store.
5. Add live integration tests for configured API, image, OpenCode, STT, and TTS backends.
