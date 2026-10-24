# Phase 7: Remove dead weight

**Decision (owner, 2026-10-24):** remove everything below. Some items are removed earlier, inside the phase that rebuilds their area; this file is the checklist.

Counts are the number of lines that mention the feature, per file, on `master` today.

| Feature | Where it lives | Removed in |
|---|---|---|
| Plasmashell watchdog / auto-restart | `autoRestartPlasmaShell` (main.xml), `main.qml` (10: `runPlasmaShellWatchdog`, `syncPlasmaShellWatchdog`, heartbeat timer), `ConfigOther.qml` (4), `kde_ai_helper.py` `cmd_plasmashell_watchdog` + monitor | **First PR** (it's running on user machines now) |
| MCP tools in direct mode | `enableMcpTools`, `mcpServersJson`; `main.qml` (16: `mcpToolDefinitions`, `executeMcpTool`, `handleMcpToolCalls`, …); `ConfigOther.qml` (10); helper `cmd_mcp_query`, `cmd_mcp_discover`, `cmd_mcp_web_search` | Phase 2 |
| System-info injection | 13 `sysInfo*` entries + `gatheredSysInfo`; `main.qml` (68); `ConfigSystemPrompt.qml` (73); `api.js` (21) | Phase 2 |
| Memory manager / user facts | `enableMemory`, `userMemory`; `main.qml` (14: `buildEffectiveMemoryBlock`); `api.js` (5); `ConfigSystemPrompt.qml` (11); per-chat memory in `ChatSettingsDialog.qml` (4) | Phase 2 |
| Context compaction | `enableCompactingContext`, `compactContextAfter`; `main.qml` (22: `checkAndTriggerCompaction`, `runContextCompaction`, …); `ConfigSystemPrompt.qml` (7) | Phase 2 (replaced by the existing `contextMessageLimit`) |
| Process memory monitor / kill buttons | helper `cmd_get_memory_usage`; `ConfigOther.qml` (6); `ConfigGeneral.qml` (1) | Phase 6 (voice services become on-demand) |
| Screen-region capture | `captureScreenRegion` in `main.qml` (4), `FullRepresentationContent.qml` (2) | Phase 4 |
| Desktop selection auto-fill | `desktopSelectionEnabled`; `fetchDesktopSelection` in `main.qml` (2) | Phase 4 |
| Open OpenCode in terminal | `openOpenCodeInTerminal` in `main.qml` (2), `FullRepresentationContent.qml` (1) | Phase 3 |
| Git diff inspector | none left in the code | already gone |
| Interactive guides | `showInteractiveGuides`; guide text in `ConfigGeneral.qml` (12), `ConfigVoice.qml` (19), `ConfigOther.qml` (18), `ConfigSystemPrompt.qml` (11) | Phase 4 (settings rebuilt) |
| UI-language override | `uiLanguage`; `ConfigOther.qml` (4), `main.qml` (1) | Phase 4 |
| Appearance override | `appearanceMode`, `popupIsDark`; `ConfigGeneral.qml` (5), `main.qml` (5), `FullRepresentationContent.qml` (6) | Phase 4 (follow the system theme) |

## Migration

- Delete removed settings from users' config on first run of the new version so they don't linger in `appletsrc`.
- Stop and remove the watchdog's monitor process and its files in `~/.local/share/kdeaichat/` (`plasmashell-heartbeat`, `plasmashell-watchdog.pid`).

## Done when

- Every row above is gone from the code, `main.xml`, translations and docs.
- README and screenshots describe only what remains.
