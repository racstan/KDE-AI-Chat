# Phase 4: GUI rebuild

**Goal:** a beautiful chat view that never flickers, jumps or loses your place, and stays smooth while long answers stream.

Paths are relative to `org.kde.plasma.kdeaichat/contents/ui/`. FRC = `FullRepresentationContent.qml`.

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
