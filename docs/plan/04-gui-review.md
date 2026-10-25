# Phase 4: GUI design review (before polishing)

Screenshots: `build/qml-screens/mockup-<state>-<light|dark>.png`, made by `tests/qml/tst_mockups.qml` (`pytest -q` regenerates them; 760x700, the real chat components with `FakeChat`). Dark is approximated by overriding the Kirigami theme on the popup root, as `FullRepresentationContent.qml` (FRC) does: the offscreen platform has no Plasma colour scheme. Real Breeze Dark may differ, but the problems below come from the code, not the approximation.

*Since this review:* the mock-ups are made by `tests/qml/mockups.qml` under the real Breeze Light/Dark schemes through KDE's platform theme (no override), and the custom palette is gone; see Progress in `04-gui.md`.

## What I see, per state

**Empty chat**
- Completely blank grey panel; no guidance, no "what model am I talking to".
- The header already shows a chat title ("Trip planning") and ten icon buttons for a chat with nothing in it.

**Conversation**
- Hierarchy is good: user bubble right (accent tint), assistant text full width with no bubble.
- The action row (edit / regenerate / copy / delete) sits under every message all the time: 4 icons x every message is noisy. The delete icon is red at rest.
- Lists are indented differently from paragraphs (bullets far right, numbered list at another indent); headings are only slightly bigger than body text.
- Links are pure blue: unreadable on dark.
- Token line ("30 in · 212 out") is fine but easy to confuse with the action row; timestamps are fine.
- The code block follows the theme and looks good; its copy icon is not labelled.

**Streaming**
- The partial reply is plain text, so `**quiet**` shows raw asterisks; it jumps to rendered Markdown when done (fine in principle, but the stars look broken).
- The spinner floats at the far right of the empty row, away from the text.
- The status strip ("Streaming response...") is an extra row above the composer that makes the composer jump down.
- Stop is a small red circle icon at the far right with no label; the Send button turns into a greyed "+ Queue" and is easy to mistake for "disabled".
- Action icons on the streaming message are shown (greyed) although they do nothing yet.

**Reasoning**
- Collapsed-by-default "Thought process" block is neat. Expanded, it is a bordered box with a different text colour; spacing around it is tight against the name line. OK overall.

**Tool call / context list**
- Only a collapsed "> 4 steps" line under the answer. There is no tool card: no tool name, no status (running / done / failed), no icon per tool, and nothing is visible without clicking. Hard to tell what the agent did. `ToolCard.qml` from the plan does not exist yet.

**Permission card and question card**
- The orange cards are clipped on the right edge (border cut off) in both themes: the card is wider than the list.
- Heading "OpenCode asks for permission" is small and bold, the same size as body text; the command being approved is plain text, not a code block.
- Allow / Always allow / Reject are all equal-weight buttons; Allow should be the main one. Once answered they become emoji text ("Approved ✅", "Rejected ❌").
- The question card repeats the question twice (card title and bold line). Options are plain buttons with no selected state visible; custom answer field is fine.

**Error**
- Red text on a red-tinted card with a red border: three reds, medium contrast on dark. Heading "Something went wrong" is plain language, but the body is a raw "Request failed: 401" string.
- Actions are only retry / copy / delete. There is no "Open settings" for a bad key and no "Try again" label.

**History**
- It is a full-page list that replaces the chat, not a sidebar. Back arrow, pin and settings icons stay in the header.
- Rows are tall (title and "N messages" far apart), the row action icons (rename, archive, delete) are always visible and the archive icon is unclear.
- The "OC" badge is dark blue on dark: low contrast. Rows have no date.

**Attachments**
- Chips above the composer look fine: icon, name, x. Error chip is red with a truncated name; the reason shows only as a tooltip. The loading chip shows a spinner.
- Pending files sit between the list and the input and push the list up. Images show a 16 px thumbnail only.

## Cross-cutting problems

1. **Custom palette, not the Plasma theme.** FRC sets `Kirigami.Theme.inherit: false` with hard-coded greys and a fixed accent `#3182ce`, and `popupIsDark` is computed in `main.qml`. In the Breeze-styled controls this means the composer text box stays white in dark mode (see every dark shot), and SessionList hard-codes `#ffffff` text. Fix: drop all of it and inherit the real theme.
2. **Icons:** about a dozen similar header icons with no labels (up, down, top, bottom, rename, controls, export, pin, clear...). Emoji (✅ ❌) still appear in permission results.
3. **Spacing:** margins mix `Kirigami.Units.smallSpacing`, literal `8`, `6`, `20`, `180`. Chips, cards and bubbles use different radii (6, 8, `cornerRadius * 2`).
4. **Always-visible per-message icons** instead of showing on hover/focus.
5. **Clipping:** request and error cards overflow the right edge.
6. **Accessibility:** most icon buttons need `Accessible.name`; the stop button and header icons have none visible.

## PR #7 ideas, mapped to concrete changes

| PR #7 idea | Proposed change |
|---|---|
| Follow Plasma colour scheme/accent; one spacing scale; Breeze icons not emoji | Delete the Theme override in FRC and `popupIsDark`; use `Kirigami.Theme` colours only. Spacing from `Units.smallSpacing / largeSpacing`, one radius token. Replace ✅/❌ with `dialog-ok` / `dialog-cancel` icons. |
| Header with provider/model chip ("leaves the computer" indicator) | Header = back/history, title, model chip (cloud icon for remote providers, computer icon for local/Ollama), one overflow menu. Move top/up/down/bottom, export, clear, rename into the menu or hover. |
| Empty-chat guidance | Centred `Kirigami.PlaceholderMessage`: model name, where it runs, 3 example prompts that fill the input, "Attach a file" hint. |
| Plain-language errors with Try again / Open settings | Map status codes to short sentences (401 = "Your API key was rejected"); buttons "Try again" and, for key/model errors, "Open settings". Single red, neutral card with a red icon, not red text. |
| Undo for clear/delete chat; confirm before regenerate drops later messages | Inline `Kirigami.InlineMessage`-style undo bar after clear/delete; small confirm popover on regenerate when later messages exist. Hide per-message delete until hover. |
| Keyboard: Ctrl+N, Ctrl+H, Esc stops, Up edits last, `/` templates; accessible names | Add shortcuts to the chat root, a visible "Stop" button with `Esc` tooltip, `Accessible.name` on all icon-only buttons. |
| `Sec.sanitizeMarkdown` | No visual change; keep out of the design pass. Links should use `Kirigami.Theme.linkColor`. |

## Additional proposals from this review

- Streaming: render a spinner inline after the last word, hide the action row until done, show "Stop" as a labelled button replacing Send; show raw Markdown less jarringly (or render per paragraph).
- Tool card: one row per tool with icon, name, argument summary and status, expanded by default while running, collapsed when done.
- Permission card: show the command in monospace, make Allow the highlighted button, fix the width clipping.
- History: make it a real side panel or a popover list; one line per chat (title, relative date), actions on hover.
- Attachments: keep chips, but show the error text under the chip instead of only a tooltip; stop loading `Image` for non-image files (it logs "Cannot open" warnings).
