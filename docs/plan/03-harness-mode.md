# Phase 3: Harness mode (OpenCode and Pi)

**Goal:** use OpenCode's and Pi's agent features from the desktop, with live text, tool activity, permission prompts and file changes visible in the chat, without the widget reinventing them.

Versions audited: OpenCode 1.18.31 (SDK typings on disk are 1.2.27, so verify API details against a live server first), Pi 0.84.2. Paths are relative to `org.kde.plasma.kdeaichat/contents/ui/`.

## Audit findings: OpenCode

**What works:**
- The flow: `POST /session` → `POST /session/:id/message` → live text from the `/event` stream, finishing on `session.idle`.
- Question cards (`/question/{id}/reply|reject`).
- Agent picker and provider/model lists.

**Broken (each verified in the code against the SDK types):**

| Problem | Where | What the API actually does |
|---|---|---|
| Permission prompts never appear | `main.qml:1620` reads `props.permission.id` | In `permission.asked`, `properties` is the request itself; `permission` is a string. |
| Permission replies never update | `main.qml:1652` | `permission.replied` carries `requestID` and `reply`. |
| Permission answers are invalid | `main.qml:3687-3689` sends `allow`/`deny` to `/permission/…` | `POST /permission/{id}/reply` with `once` / `always` / `reject`. |
| Tool calls never show | `main.qml:1026, 1572` look for `tool-invocation` parts with `args` | Parts are `type: "tool"` with `state.input` / `state.output`. |
| Text deltas ignored | — | `message.part.delta` events. |
| Token and cost tracking never fires | `main.qml:1669` listens for `session.next.step.ended` | Comes on `step-finish` parts or `info.tokens` / `info.cost`. |
| History sync reads wrong fields | `main.qml:1042-1049` | `info.time.created`, `info.tokens`, `info.cost`. |
| Workspace folder ignored | `main.qml:1879` sends `directory` in the body | It's a query parameter. |
| Stop doesn't stop the agent | `main.qml:568` only aborts the browser request | `POST /session/:id/abort`. |
| Long agent runs fail at 60 s | blocking POST uses `requestTimeout` | Use `prompt_async`; completion comes from events. |
| Empty model sent | `main.qml:2000` can send `{providerID:"", modelID:""}` | Omit it. |
| "Kill server" kills user terminals | default stop command `pkill -f opencode` (`main.xml:233`) | Kill only a server the widget started itself. |

**Missing from the UI:** tool status and output, file edits and diffs, todos, session list, "always allow" for permissions.

## Audit findings: Pi

- One `pi --mode text -p <prompt>` process per message (`kde_ai_helper.py:853-863`). Output only arrives when the process exits (`main.qml:4532`), so there's **no streaming**: the reply sits on "Thinking…".
- Timeout is clamped to 15–300 s and defaults to 60 s (`kde_ai_helper.py:870`), which kills normal agent tasks.
- No working folder is passed (`kde_ai_helper.py:773`), so Pi runs in plasmashell's working directory.
- Images are dropped; only a note goes into the prompt.
- Pi has **`--mode rpc`**: a long-lived process that takes JSON-line commands on stdin and emits events.
  - Commands: `prompt` (with images), `abort`, `steer`, `follow_up`, `new_session`, `switch_session`, `get_messages`, `set_model`, `get_available_models`, `set_thinking_level`, `get_session_stats`.
  - Events: `message_update` (`text_delta`, `thinking_delta`, tool calls, usage), `tool_execution_start/update/end`, `agent_settled` (the real "done"), and `extension_ui_request` (confirm/select/input prompts).
  - Docs: `~/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/docs/rpc.md`.
  - Pi has no permission system of its own.

## Steps

1. **`backends/OpenCodeBackend.js`** on the shared contract (`02-direct-mode.md`):
   - Send with `prompt_async`; completion, text and tools all come from events, so there's no timeout on long runs.
   - Map events: `message.part.delta` → `text_delta`/`reasoning_delta`; tool parts → `tool_start/update/end`; `file.edited` and `session.diff` → `file_changed`; `step-finish` → `usage`; `session.idle` → `done`.
   - Permissions: `permission.asked` → `permission_request`; reply with `POST /permission/{id}/reply` and `once|always|reject`.
   - Stop: `POST /session/:id/abort`.
   - Folder: `?directory=` on requests. Subscribe to `/global/event` so chats in different folders all receive events.
   - **Server lifecycle:** check `/global/health`. If nothing is running, start `opencode serve --port N`, remember that PID, and only ever stop that PID. Remove the start/stop shell command settings.
2. **Pi bridge (`pi_bridge.py`, stdlib only)**
   - Runs one `pi --mode rpc` process per chat, started in the chat's working folder.
   - Exposes loopback HTTP with the same token auth as voice: `POST /prompt`, `POST /abort`, `POST /ui-response`, and an event stream at `GET /events`.
   - The bridge is needed because Plasma's process runner can't write to stdin or stream output.
   - `backends/PiBackend.js` then reuses the same event mapping: `extension_ui_request` → `question_request`/`permission_request`.
   - Bridge and Pi processes exit when the widget's chat is idle for N minutes.
3. **Chat UI for agent events** (built in Phase 4, fed by this phase):
   - Collapsible tool cards: name, input, live output, error state.
   - Permission card: Allow once / Always / Reject.
   - Files-changed summary with diffs.
   - Usage line.
4. **Per-chat settings for harness chats:** working folder, agent (OpenCode), model, thinking level (Pi). Remove the "open in terminal" button (cut list).

## Tests

- node: event mapping from recorded OpenCode event streams and Pi RPC transcripts (tool call, permission, abort, error).
- pytest: Pi bridge (spawns a fake `pi` script that speaks the RPC protocol); auth; idle exit.
- Manual via harness against real OpenCode and Pi: a task that reads a file, edits a file (permission prompt), and is stopped midway.

## Done when

- In both harnesses: text streams, tools show as they run, permission prompts can be answered, Stop really stops the agent, and runs longer than 60 s complete.
- The widget never kills processes it didn't start.
