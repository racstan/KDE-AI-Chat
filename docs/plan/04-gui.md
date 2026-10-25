# Phase 4: GUI rebuild

**Goal:** a beautiful chat view that never flickers, jumps or loses your place, and stays smooth while long answers stream.

Paths are relative to `org.kde.plasma.kdeaichat/contents/ui/`. FRC = `FullRepresentationContent.qml`.

## Progress (branch `feat/gui-rebuild`, as of 2026-10-25)

**Done (committed: 0c33e09, 251d73a, then the popup split):**
- **Message model** (`chat/MessageModel.qml`): the list is a ListModel of `{msgKey, rev}` rows synced from `root.messages` by id and object identity (identity survives reassignment, verified). Append/edit/delete touch one row; a different chat replaces all rows. Messages without an id get one (saved with the chat). `indexOfKey()` finds a row. Tested in `tests/qml/tst_message_model.qml`.
- **Throttled streaming**: deltas go to `root.streamPending` and `flushStream()` applies them at most every 33 ms (`streamFlushTimer`); flushed before done/reset.
- **Streamed reply tracked by id** (`root.currentStreamKey`, recomputed in `onMessagesChanged`), so deletes/inserts mid-stream can't send text to the wrong bubble (problem 6).
- **One scroll rule** (problem 3, 4): `chat/ChatView.qml` follows new content while `root.userScrolledUp` is false; wheel/drag/scrollbar away from the end stops following; reaching the end or the "Latest"/"New messages" button resumes. Standard attached ScrollBar (drag works). Removed the scroll lock/capture/restore code and timers from main.qml. Touchpad kinetics from issue #3 kept.
- **Message list split** (problems 1, 2, 8, 9 partly, 10): `chat/ChatView.qml`, `MessageDelegate.qml` (Loaders per role instead of DelegateChooser), `MessageBody.qml` (plain text while streaming, Markdown + code blocks once done, via `MessageBlocks.js`), `MessageText.qml` (read-aloud highlight searches the displayed text), `CodeBlock.qml`, `ReasoningBlock.qml`, `AttachmentChips.qml` (thumbnails decoded at chip size, icons for non-images), `QuestionCard.qml`, `ContextList.qml`, `MessageActions.qml`, plus Phase 3's `PermissionButtons.qml`. FullRepresentationContent.qml went 1999 → 957 lines.
- **Removed**: unused colour pulse animation, desktop-selection auto-fill, `getEffectiveModel`.
- **Tests**: `tests/qml/FakeChat.qml` (stand-in for main.qml) + `tests/qml/tst_chat_view.qml`: 2,000 deltas keep the same delegate and stay at the bottom; scrolling up mid-stream keeps the place; editing/deleting one message keeps the other delegates; screenshots `build/qml-screens/chat-view-*.png`. `tests/js/message_blocks.test.js`. 191 tests pass; fake-agent e2e runs (`scripts/dev-pi-e2e.sh`, `scripts/dev-opencode-e2e.sh`) show no QML warnings.
- **Rest of the popup split** (step 1 done): `chat/ChatHeader.qml` (toolbar), `chat/OpenCodeBar.qml`, `chat/RenameRow.qml`, `chat/Composer.qml` (status row, files waiting to be sent, input + buttons) and `chat/SessionList.qml` (history). Each takes `chat: root`; things outside the chat (settings action, file/export/workspace dialogs, the chat-controls sidebar, writing `openCodeAgent` to config) are signals handled in FullRepresentationContent.qml, which is now 236 lines (drop area, layout, resize handle, palette, sidebar). The attachment chip's error tooltip uses `containsMouse` (was the non-existent `hovered`).
- **`root.focusInput()` works** (problem 9): Composer registers itself as `root.composerRef` and exposes `focusInput()` and `input`; `onClearChatInput` lives in the Composer. Tested in `tests/qml/tst_composer.qml` (focus, typing + Enter, Send button) and `tst_chat_layout.qml` (header, rename row, list, composer and history laid out together; screenshots `build/qml-screens/chat-layout*.png`).
- qmllint baseline regenerated in the CI container (the earlier `chat/` files had no entries, so the ratchet was failing); new files: 0 warnings except Composer 3 (explicit sizes inside layouts, kept as before) and OpenCodeBar 1 (`i18n`).

**Next:** the design pass (step 2). FRC still sets a custom dark/light palette (top of the file, and again in main.qml's `fullRepresentation`): remove it there so it follows the Plasma theme. The export dialog still suggests a hard-coded `/home/home/Documents/` path (`ChatHeader.exportFileName()`).

**Still open:** popup resize jitter (problem 5, resize handle at the end of FRC), the design pass and owner review (step 2, incl. PR #7 ideas and `Sec.sanitizeMarkdown`), performance budget (step 3), settings pages (step 4), remaining cuts (step 5: screen-region capture, language/appearance overrides, guides). `main.qml` is still ~2900 lines.

## Why the GUI is unstable (audit findings, ranked)

1. **The whole message list is rebuilt on every change.**
   - Messages are a plain JS array (`FRC:490 model: root.messages`, `reuseItems: false`), reassigned at ~44 places in `main.qml`. Qt treats each new array as a full model reset.
   - Result: every delegate is destroyed and recreated, Markdown is re-parsed, text selection is lost, and the scroll position resets.
   - The dozens of `Qt.callLater(scrollToBottom)` calls (e.g. `main.qml:4340, 1149, 3138`) are patches over this. They cause the visible flicker and jumps.
2. **The streaming bubble rebuilds itself on every chunk.**
   - The streaming row builds a new block list per chunk (`FRC:716`, Repeater at `FRC:931`), recreating every Markdown text and code block. Its height jumps every token, and the cost grows with answer length.
   - The stream parser also re-scans the whole answer and copies `responseText` 2–3 times per update (`main.qml:3189-3216`), which slows down quadratically.
3. **Auto-scroll locks and never unlocks.**
   - Every send sets `responseScrollLocked = true` (`main.qml:2181-2224`, called at 2492). Only switching chat, a new chat or the "jump to latest" button clears it, so later replies stop following the bottom.
   - At the end of a reply, the view snaps back to a saved position (2571) that may already be wrong.
4. **Dragging the scrollbar doesn't scroll the list** (`FRC:1464-1490`). The thumb moves on its own, and on release the list jumps to an estimated index.
5. **Popup resize jitters.** The handle measures the mouse relative to the corner it's moving, and writes config on every mouse move (`FRC:1978-2006`).
6. **Tokens can land in the wrong bubble.** Deleting a message (`main.qml:880`), or compaction inserting a row (3568-3571), while a reply streams shifts indexes. Text then goes into another message, and finishing the reply overwrites that message.
7. **Every change saves all chats into Plasma's config**, including base64 images and extracted document text (`main.qml:272-288`, 4741, 2787-2796). Covered in Phase 1.
8. **Attachment chips decode full-size images** for a 16 px icon, on every rebuild, and try to load non-image attachments as images (`FRC:969, 1590`).
9. **References to properties that don't exist:**
   - `ToolTip.visible: hovered` on a MouseArea (`FRC:997`).
   - `fileMouseArea.hovered` (`FRC:1560`), so the error tooltip never shows.
   - `root.focusInput()` (`main.qml:164-172`) looks for an id it can't see, so the input never gets focus.
10. **Minor:**
    - The read-aloud highlight selects positions in the raw Markdown while the rendered text differs, so the wrong words light up.
    - An endless animation (`FRC:55`) runs for a colour nothing uses.

No path leaves the UI stuck on "loading"; every error, timeout and abort resets it.

## PR #7 (draft, Oct 16)

An earlier session's draft PR #7 ("Chat window: consistent, accessible, private") was never tested on a real desktop and conflicts with `master`. Rather than merging it, bring its ideas into this phase piece by piece, each tested with the harness, then close it:
- follow the Plasma colour scheme/accent; one spacing scale; Breeze icons instead of emoji
- header with provider/model chip ("leaves the computer" indicator)
- empty-chat guidance; plain-language errors with Try again / Open settings
- Undo for clear/delete chat; confirm before regenerate drops later messages
- keyboard: Ctrl+N, Ctrl+H, Esc stops a reply, Up edits the last message, `/` suggests templates; accessible names on icon buttons
- `Sec.sanitizeMarkdown`: replies can't load remote images/HTML

## Design principles

- **Messages are a real model** (`ListModel`) with a stable `id` per message. Streaming changes only the last row's `text` (`setProperty`). Nothing ever replaces the whole list.
- **Delegates are light.** Use a `DelegateChooser` per role (user, assistant, tool, permission, error).
  - While streaming: plain text, appended. When done: Markdown rendered once.
  - Edit, question and permission UIs are loaded only when needed.
- **One scroll rule:** follow the bottom while the view is at the end (`atYEnd`). If the user scrolls up, leave them there and show a "↓ new messages" button. No locks, saved positions or `callLater` chains.
- **Throttled updates:** the backend batches deltas and the UI updates at most every ~33 ms.
- **Small files:** no QML file over ~400 lines. `main.qml` only wires things together.
- **Follow the system theme** (Kirigami colours, no custom dark/light palette), use Kirigami spacing and typography units, and make it keyboard-accessible.

## Steps

1. **Components:** `ChatView.qml` (ListView + scroll rule), `MessageDelegate.qml` (+ per-role delegates), `Composer.qml` (input, attachments, send/stop), `SessionList.qml`, `ToolCard.qml`, `PermissionCard.qml` (Phase 3 events).
2. **Design pass:**
   - Mock the chat view, empty state, streaming state, tool card, permission card and error state as offscreen screenshots.
   - Owner reviews before polishing.
   - Then match Breeze in light and dark.
3. **Performance budget:**
   - Popup opens in < 150 ms with a 500-message chat.
   - No dropped frames while streaming a 20k-token answer.
   - Measured in the offscreen harness with a fake backend that streams quickly.
4. **Settings rebuilt** as a few small pages: Providers, Harness, Chat (system prompt, message limit, templates), Schedules, Voice, Appearance (icon, sound). No guide text blocks (cut list).
5. **Remove** screen-region capture, desktop-selection auto-fill, the UI-language and appearance overrides, and the interactive guides (see `07-cut-list.md`).

## Tests

- Offscreen QML:
  - Stream 2,000 deltas and assert the delegate count doesn't churn (no recreation) and the view stays at the bottom.
  - Scroll up during streaming and assert the position is unchanged.
  - Delete a message during streaming and assert the text goes to the right bubble.
  - Drag the scrollbar.
  - Resize the popup.
- Screenshots of each state, reviewed by Claude and the owner.
- Fail on any QML warning.

## Done when

- None of the 10 problems above can be reproduced in the harness.
- The performance budget is met, and the owner signs off on the look.
