# Phase 4: GUI rebuild

**Goal:** a beautiful chat view that never flickers, jumps or loses your place, and stays smooth while long answers stream.

Paths are relative to `org.kde.plasma.kdeaichat/contents/ui/`. FRC = `FullRepresentationContent.qml`.

## Progress (branch `feat/gui-rebuild`, as of 2026-10-25)

**Done (committed: 0c33e09, 251d73a, then the popup split):**
- **Message model** (`chat/MessageModel.qml`): the list is a ListModel of `{msgKey, rev}` rows synced from `root.messages` by id and object identity (identity survives reassignment, verified). Append/edit/delete touch one row; a different chat replaces all rows. Messages without an id get one (saved with the chat). `indexOfKey()` finds a row. Tested in `tests/qml/tst_message_model.qml`.
- **Throttled streaming**: deltas go to `root.streamBuffer` (`chat/StreamBuffer.qml`), which adds them to `currentStreamText`/`currentStreamReasoning` at most every 33 ms; flushed before done/reset.
- **Streamed reply tracked by id** (`root.currentStreamKey`, recomputed in `onMessagesChanged`), so deletes/inserts mid-stream can't send text to the wrong bubble (problem 6).
- **One scroll rule** (problem 3, 4): `chat/ChatView.qml` follows new content while `root.userScrolledUp` is false; wheel/drag/scrollbar away from the end stops following; reaching the end or the "Latest"/"New messages" button resumes. Standard attached ScrollBar (drag works). Removed the scroll lock/capture/restore code and timers from main.qml. Touchpad kinetics from issue #3 kept.
- **Message list split** (problems 1, 2, 8, 9 partly, 10): `chat/ChatView.qml`, `MessageDelegate.qml` (Loaders per role instead of DelegateChooser), `MessageBody.qml` (plain text while streaming, Markdown + code blocks once done, via `MessageBlocks.js`), `MessageText.qml` (read-aloud highlight searches the displayed text), `CodeBlock.qml`, `ReasoningBlock.qml`, `AttachmentChips.qml` (thumbnails decoded at chip size, icons for non-images), `QuestionCard.qml`, `ContextList.qml`, `MessageActions.qml`, plus Phase 3's `PermissionButtons.qml`. FullRepresentationContent.qml went 1999 → 957 lines.
- **Removed**: unused colour pulse animation, desktop-selection auto-fill, `getEffectiveModel`.
- **Tests**: `tests/qml/FakeChat.qml` (stand-in for main.qml) + `tests/qml/tst_chat_view.qml`: 2,000 deltas keep the same delegate and stay at the bottom; scrolling up mid-stream keeps the place; editing/deleting one message keeps the other delegates; screenshots `build/qml-screens/chat-view-*.png`. `tests/js/message_blocks.test.js`. 191 tests pass; fake-agent e2e runs (`scripts/dev-pi-e2e.sh`, `scripts/dev-opencode-e2e.sh`) show no QML warnings.
- **Rest of the popup split** (step 1 done): `chat/ChatHeader.qml` (toolbar), `chat/OpenCodeBar.qml`, `chat/RenameRow.qml`, `chat/Composer.qml` (status row, files waiting to be sent, input + buttons) and `chat/SessionList.qml` (history). Each takes `chat: root`; things outside the chat (settings action, file/export/workspace dialogs, the chat-controls sidebar, writing `openCodeAgent` to config) are signals handled in FullRepresentationContent.qml, which is now 236 lines (drop area, layout, resize handle, palette, sidebar). The attachment chip's error tooltip uses `containsMouse` (was the non-existent `hovered`).
- **`root.focusInput()` works** (problem 9): Composer registers itself as `root.composerRef` and exposes `focusInput()` and `input`; `onClearChatInput` lives in the Composer. Tested in `tests/qml/tst_composer.qml` (focus, typing + Enter, Send button) and `tst_chat_layout.qml` (header, rename row, list, composer and history laid out together; screenshots `build/qml-screens/chat-layout*.png`).
- **Popup resize** (problem 5): `chat/ResizeHandle.qml` measures the mouse with `mapToGlobal` from the press point, so the handle moving with the corner no longer feeds back into the size. While dragging it sets `root.livePopupWidth/Height` (main.qml's `popupPreferredWidth/Height` prefer them over the saved size), clamped to 500×620 … screen size; `customPopupWidth/Height` are written once, on release (or cancel). The grip sits in the corner away from the panel (top edge for a bottom panel, left edge for a right panel). Tested in `tests/qml/tst_resize_handle.qml` (exact delta per move, no drift while holding still, min/max, one config write per dimension on release, top-left variant); the old local-coordinate maths fails 5 of its 6 tests. FRC is now 194 lines. Not yet tried in a real panel popup: how far the popup grows towards the grip depends on where Plasma places it (e.g. centred over the applet, a width change moves each side by half).
- **Export path**: `ChatHeader.exportFileName()` suggests `StandardPaths.DocumentsLocation` (QtCore) instead of `/home/home/Documents/`, with the file name URL-encoded; tested in `tst_chat_layout.qml`.
- qmllint baseline regenerated in the CI container (the earlier `chat/` files had no entries, so the ratchet was failing); new files: 0 warnings except Composer 3 (explicit sizes inside layouts, kept as before) and OpenCodeBar 1 (`i18n`).

- **Performance budget** (step 3) met, measured offscreen by `tests/qml/tst_perf_open.qml` and `tst_perf_stream.qml` (they print `PERF …` lines; numbers below from this machine, the CI container is similar or faster):
  - *Open*: from creating `chat/ChatView.qml` with a 500-message chat already in the model (mixed user/assistant, Markdown, code blocks, every tenth answer ~4,000 characters) until the first swapped frame at which the list is laid out at the end (atYEnd, last delegate built and in view). Before: 441–511 ms when the last message was a long one, and **never** when the chat ended with short messages: `positionViewAtEnd()` built delegates at a guessed height, they grew when their layouts ran, pushed the last one out, and the list released and rebuilt all of them in an endless loop. After: first open 77–134 ms, then 60–73 ms (CI container: 60–122, then 41–43). Switching the open view to another 500-message chat: 448 ms → 85–94 ms (CI: 52). The tool buttons are built after that frame and all are in place 160–240 ms after opening, without moving anything.
  - *Streaming*: a fake server feeds the real `DirectBackend.js` an OpenAI-style stream of 20,000 tokens (~140,000 characters) at ~5 tokens/ms, through `StreamBuffer` into `ChatView`. Frame interval (frameSwapped to frameSwapped; offscreen frames come every ~11 ms): before p95 27–28 ms, p99 35–36, max 41–45, 21–22 frames over 25 ms; after p95 15–17, p99 16–18, max 17–23, none over 25 ms. Update-to-frame time (from a `currentStreamText` change to the next frame) grew from 7–9 ms at the start of the answer to 32–33 ms at the end before; now it stays flat (~8–15 ms). Rendering the finished reply as Markdown once: 590–630 ms → 420–460 ms (one-off, after the stream; CI: ~315 ms).
  - Test thresholds: open ≤ 150 ms (best of the two later runs; the first ≤ 375 ms), switch ≤ 150 ms; stream p95 ≤ 16.7 + 5 ms, at most 2% of frames over 33 ms, and the update cost in the last fifth ≤ 1.5 × the first fifth + 5 ms. With every core busy with other work, the stream p95 rises to 24–27 ms and fails (the local CI runner runs one job at a time).
  - What changed: delegates know their final height when created (`MessageDelegate.bubbleWidth` / `MessageBody.textWidth` give the text its wrap width before the layouts run), which ends the rebuild loop and the double layout; the list has no current item (it kept row 0's delegate alive); a different chat replaces the rows in one insert, and the view lets go of the model meanwhile (`MessageModel.aboutToReplace/replaced`) so it builds only the delegates at the end; the Plasma tool buttons under messages and on code blocks (3–4 ms each, ~15 ms per message) are built only if shown, after the first frame, a few per frame (`chat/DeferredBuilder.qml`), with their height kept free; the regenerate menu and the busy indicator are created when needed. While streaming, the reply is plain text in ~1,500-character pieces split at line breaks (`chat/StreamingText.qml`): a TextEdit lays out and redraws all its text on every change, even when only appended to, so one TextEdit holding the whole reply got slower with every update. The collapsed thinking block no longer lays out its text. `DirectBackend`'s SSE parser walks a chunk's lines by index instead of copying the rest of the buffer per line (quadratic in a big chunk). Following the end no longer happens while the user drags/flicks, and a wheel step stops following before moving (moving can build a delegate and trigger a follow first). The stream parser in main.qml (problem 2) had already moved to `DirectBackend.js`; what remains linear per network read is Qt's `xhr.responseText`, which returns the whole response every time.

- **Design review** (`04-gui-review.md`); the owner decided: follow the Plasma theme completely.
- **Plasma colour scheme everywhere** (design pass, part 1): the custom palette is gone (FRC's and main.qml's `Kirigami.Theme` overrides with `#3182ce` and fixed greys, the popup's own background rectangle, `popupIsDark`, main.qml's `historySessionTint` with its fixed blue). Every colour in `chat/`, FRC and the settings/schedule dialogs is a `Kirigami.Theme` colour (some with an alpha tint of one); spacing uses `Kirigami.Units`; one corner radius, `Kirigami.Units.cornerRadius`. Text fields and the OpenCode agent box are Plasma's own (`PC3.TextArea/TextField/ComboBox`) instead of QQC2 ones with hand-drawn backgrounds, so the message box is dark in a dark theme. Links take the scheme's link colour (TextEdit has no `linkColor`; its Markdown importer uses the application palette, which Plasma sets from the scheme: `#1d99f3` in Breeze Dark). Breeze icons instead of emoji (answered permission: `dialog-ok-apply`/`dialog-cancel` + word; no 📁 in the OpenCode bar); delete buttons use the neutral `trash-empty` instead of the red `edit-delete`; error bubbles and banners are a neutral card with a negative-coloured edge and normal text; the "OC" badge is text-coloured on an accent tint.
- **Screen-region capture removed** (cut list): the composer button, `captureScreenRegion` and its `#spectacle-shot-` handler in main.qml (it had no helper command or config entry).
- **Honest mock-ups**: `tests/qml/tst_mockups.qml` is now `tests/qml/mockups.qml` (not run by the main suite) and sets no colours. `tests/test_qml.py::test_qml_mockups` runs it under Breeze Light and Breeze Dark with KDE's platform theme (`QT_QPA_PLATFORMTHEME=kde`) reading the scheme from a temporary `kdeglobals`, the way Plasma gives Kirigami and the controls their colours; each shot is named after the scheme `Kirigami.Theme` really reported, and a check asserts the message box is dark in the dark scheme. Same in the CI container.

- **Panels** (branch `feat/gui-panels`): *History as a side panel*: `chat/ChatBody.qml` lays out everything under the header; from a body width of 40 grid units (720 px at the default 18 px unit) the history (`chat/SessionList.qml`, 15 grid units wide) slides in beside the chat (`chat.historyOnlyMode` is still the toggle), below that it replaces the chat as before (`historyFull`). The header, OpenCode bar and rename row take `historyFull` from FRC instead of reading `historyOnlyMode`. Rows are one line (title, Today/Yesterday/date; the full "Updated ..." is the tooltip); rename/archive/delete appear on hover or keyboard focus (Enter opens, Up/Down moves). `main.qml` got `historySidePanel` (set by ChatBody) so New chat leaves a side panel open. *Chat info panel*: `ChatSettingsDialog.qml` (564 lines, off the size allowlist) is now the 200-line panel shell around `chat/ChatSettingsDraft.qml` (the draft, its Apply and the async model/agent/Pi refreshes), `chat/ChatOverridesForm.qml` (the settings form) and `chat/ChatInfoSummary.qml` (totals from `chat/ChatStats.js`, summed from per-message `tokens`/`cost`; replies without usage add nothing and are counted in a note). *Usage*: `DirectBackend.js` sends `stream_options.include_usage` on every OpenAI-style streaming request, retried once without it on a 400/422 that names the field (remembered per base URL), asks OpenRouter for `usage: {include: true}` and reports its `usage.cost` as the usage event's `cost`, reports usage once per request, and counts Anthropic's cached prompt tokens as input. *Header*: Accessible.name on every icon-only button; rename, the four jump actions, export and clear moved into a "More actions" menu (`ChatHeader.clearChat()` is the clear action). Live check (`scripts/dev-send.sh openrouter openrouter/auto`, once): the saved reply carried `tokens {input: 87, output: 46}` and `cost: 0.0000363`, both from OpenRouter's own usage block. Tests: `tst_history_panel.qml`, `tst_chat_info.qml`, `chat_stats.test.js`, new cases in `direct_backend.test.js`; mock-ups for history (side panel) and chat info.

- **Settings: one Connection page** (branch `feat/4a-settings`): "Providers" and "Harness" are now `ConfigConnection.qml` ("Connection": it is how the widget connects to a model, whichever way). The mode choice (`config/ModeChooser.qml`: directly to a provider / through OpenCode / through Pi) is at the top and decides which section shows: direct = `config/ProvidersPanel.qml` + `config/RequestOptions.qml` (time limit, streaming); OpenCode = `config/OpenCodeSettings.qml`; Pi = `config/PiSettings.qml`. Every setting is kept; the other modes' values stay saved. The wallet is opened only in direct mode. *Model lists*: `components/ModelPicker.qml` (+ `ModelFilter.js`) replaces `config/ModelCombo.qml` and the provider editor's model box: type any word to see every model whose id or name contains it (case-insensitive, several words must all match), "12 of 340" count, Up/Down/PageUp/PageDown/Enter/Esc, current model keeps its check mark, any id can still be typed. 1,000 models filter in ~0.1 ms (~10 ms per keystroke including the list). Tests: `tst_config_connection.qml`, `tst_model_picker.qml`.

**Next:** the rest of the design pass (step 2): header and actions (hover actions, overflow menu, model chip), empty state, error copy and buttons, tool/permission cards (incl. the right-edge clipping), history panel; then owner review.

**Still open:** the rest of the design pass and owner review (step 2, incl. PR #7 ideas and `Sec.sanitizeMarkdown`), settings pages (step 4), remaining cuts (step 5: language/appearance overrides, guides). Emoji remain in error text built in main.qml (`⚠️ Cannot send…`, error copy is for the error-state pass) and in exported Markdown/text (not UI chrome). `main.qml` is still ~2850 lines.

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
