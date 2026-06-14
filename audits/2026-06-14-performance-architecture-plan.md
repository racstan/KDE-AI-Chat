# Performance and Architecture Plan - 2026-06-14

## Target UX

The plasmoid should feel instant for normal chat, local models, OpenCode bridge operations, and voice interactions. The UI thread must stay mostly dedicated to painting and input. Slow work must be batched, cached, moved to helpers, or deferred.

## Performance Budget

- Typing: no visible pause per keystroke.
- Streaming: update text at 8-12 Hz, not per token.
- Scroll: no rich parsing or full-message scans during flick/drag.
- Voice controls: button state changes immediately, daemon work happens in background.
- Persistence: no full JSON stringify on every UI state twitch.

## Workstreams

### 1. Chat List Hot Path

Current problems:

- Heavy delegate tree in `FullRepresentation.qml`.
- Rich `TextEdit` for every visible block.
- Search and day labels are computed inside delegates.
- Message slice creates index conversion risk.

Actions:

- Extract `ChatList.qml` and `MessageDelegate.qml`.
- Keep `MessageContent.qml`, but make it consume precomputed block HTML where practical.
- Precompute message metadata:
  - `dayKey`
  - `dayDividerLabel`
  - `searchText`
  - `blocks`
  - light/dark HTML cache only when rendered
- Add a small profiler mode that logs counts of visible delegates, parse calls, and stream flushes.

### 2. Streaming Pipeline

Current improvements:

- `_pendingStreamingText` batches chunks.
- final messages get precomputed blocks.

Remaining actions:

- Debounce bottom scroll.
- Commit final assistant messages through one append path so sessions and visible messages stay consistent.
- Avoid sorting sessions until stream end.
- Keep streaming footer plain text.

### 3. Session Store

Current problems:

- `root.sessions`, `root.messages`, `currentSessionId`, and read counts mutate from many places.
- Persistence and sorting can happen as side effects of message append.

Actions:

- Create `SessionStore.js` for:
  - create/switch/delete/rename
  - append/update/remove message
  - read counts
  - persistence scheduling
- Store mutable current-chat state separately from sidebar ordering.
- Only reorder sessions when a conversation turn completes or the user switches sessions.

### 4. Voice Pipeline

Current problems:

- UI state, daemon start, fallback command execution, polling, and error reporting are mixed.
- Polling every 500 ms is too eager.
- transient failures become chat messages.

Actions:

- Extract `VoiceController.js`.
- Introduce states: `idle`, `starting`, `listening`, `transcribing`, `speaking`, `paused`, `error`.
- Optimistically update buttons immediately on click.
- Report transient startup/poll issues in a status label; chat bubbles only for final failures.
- Poll at 500 ms only while starting/transcribing; use 1000-2000 ms while stable.

### 5. OpenCode Bridge

Current problems:

- OpenCode event stream, session creation, command execution, permission/question UI, and chat append paths share broad root state.

Actions:

- Keep OpenCode session IDs in the session store.
- Route OpenCode messages through the same streaming controller as normal providers.
- Keep permission/question requests as typed messages but render with a dedicated lightweight component.

## Refactor Boundaries

Safe extraction order:

1. `ChatList.qml`: move the ListView and custom scrollbar only.
2. `ChatComposer.qml`: input box, attachments, send/stop, voice buttons.
3. `VoiceController.js`: no UI extraction needed first.
4. `SessionStore.js`: only after scroll and streaming are stable.
5. `SchedulePanel.qml`: move large schedule UI out of `FullRepresentation.qml`.

Avoid doing all extractions at once. The scrolling regression should be fixed before major moves.
