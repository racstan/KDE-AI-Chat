# 1.5: MCP, skills and agent tools in direct chats

Direct chats already run a tool loop: `backends/DirectTools.js` (definitions, collecting calls, the
messages that carry calls and results back, OpenAI and Anthropic formats) and `chat/DirectToolRounds.qml`
(tool cards, running each call, the next round). Today the only tool is `ask_user`. 1.5 adds three
kinds of tools to that loop. Agent modes (OpenCode, Pi) are unchanged: they have their own tools.

## Pieces, in build order

### A. Tool registry and approval (foundation)

- `backends/DirectTools.js`: `toolDefinitions(type, options)` takes `options.extra`, a list of
  `{name, description, schema, source, risk}` (`source`: `"mcp:<server>"`, `"skill"`, `"workspace"`;
  `risk`: `"read"` or `"change"`). Names are made provider-safe (`^[a-zA-Z0-9_-]{1,64}$`, MCP tools
  become `mcp__<server>__<tool>`, cut and de-duplicated) with a map back to the real name.
- New `chat/DirectToolRunner.qml` (or JS + small QML) that `DirectToolRounds._execute` hands every
  call that isn't `ask_user` to. It looks the call up in the registry and runs it through the right
  runner (B, C, D), with a per-call timeout and a result cut to a size limit (say 32 kB, with a note
  that it was cut).
- Approval: a call whose tool needs approval shows a `permission_request` message (the card OpenCode
  and Pi already use; `harness: "direct"`), with Allow once / Always / Deny. "Always" is remembered
  per tool (MCP: per server+tool; workspace: per chat folder+tool) in a small JSON file through the
  helper, never in a `cfg_` setting. Deny returns "The user denied this tool call." to the model.
  `MessageEdits.respondToPermission` routes direct requests to the runner (today it goes to
  OpenCode/Pi). Stopping the request cancels a waiting approval like `cancelPending()` does for questions.
- `MAX_ROUNDS` becomes a setting (default 8, up to 50 when workspace tools are on).
- Incognito chats: tools work, but "Always" is not remembered.

### B. MCP servers (helper side: an MCP bridge)

- `kdeaichat/mcp_bridge_server.py`: a loopback, token-protected server like `pi_bridge_server.py`
  (started by a `mcp_bridge_start` helper command with a lock, exits when idle). It keeps one process
  per stdio server (JSON-RPC 2.0 over newline-delimited stdin/stdout: `initialize`,
  `notifications/initialized`, `tools/list`, `tools/call`), and talks to URL servers with the
  Streamable HTTP transport (POST JSON-RPC, accept `application/json` or `text/event-stream`,
  keep `Mcp-Session-Id`). Stdlib only.
- Endpoints: `GET /health`, `POST /tools` (`{servers:[...]}` → tools per server, or an error per
  server), `POST /call` (`{server, tool, arguments}` → `{content, isError}`; text content joined,
  images described, not inlined, in the first version), `POST /stop`.
- Server definitions: `~/.local/share/kdeaichat/mcp.json`, written only by the settings page through
  helper commands (`mcp_list`, `mcp_save`, `mcp_delete`, `mcp_import`). Same shape as the usual
  `mcpServers` JSON (`command`, `args`, `env`, `cwd` / `url`, `headers`) plus `enabled`. Secrets in
  `env`/`headers` are KWallet entries `mcp-<id>` and are passed to the bridge in the request body,
  never in argv or the JSON file.
- `mcp_import`: reads the `mcpServers` block from Claude Desktop
  (`~/.config/Claude/claude_desktop_config.json`) and OpenCode (`~/.config/opencode/opencode.json[c]`,
  key `mcp`) and offers them; nothing is imported without the user picking it.
- Tests: a tiny fake stdio MCP server and a fake HTTP one in `tests/`, no network.

### C. Skills

- Skill folders: `~/.local/share/kdeaichat/skills/<name>/SKILL.md` plus, read only, the folders
  Claude Code and OpenCode use (`~/.claude/skills`, `~/.config/opencode/skill[s]`). The YAML front
  matter gives `name` and `description`.
- The system prompt lists each enabled skill's name and description (short); one tool
  `load_skill(name)` returns the SKILL.md body (risk `read`, no approval). Files next to SKILL.md can
  be read with `read_skill_file(name, path)` inside that folder only. Scripts are never run.
- Helper commands `skills_list` / `skills_read`; Settings → Chat (or a new Skills page) lists them
  with on/off (the on/off list is a plain setting, the skills themselves are files).

### D. Agent tools (workspace)

- Only for a direct chat with a workspace folder (the chat's folder chip), and only when turned on
  for that chat. First set (risk `read`, no approval): `list_files`, `read_file` (line range, size
  limit), `search_files` (plain text / regex, skips .git and binary files). Second set (risk
  `change`, always asks): `write_file`, `edit_file` (exact string replace, shows a diff on the card),
  `run_command` (in the folder, timeout, output cut; shows the full command on the card).
- All paths are checked by the helper (`_safe_path`, inside the workspace, no symlink escape).

## Settings

- Settings → Tools (new page): MCP servers (add stdio/URL, import, test = list tools, on/off),
  Skills (list, on/off, open folder), Agent tools (default on/off for new direct chats with a folder,
  max rounds), Remembered approvals (list, forget).
- Per-chat override in Chat settings: which MCP servers and whether agent tools are on.

## Not in 1.5

Prompts and resources from MCP servers, sampling, OAuth for URL servers (a header token works),
running skill scripts.
