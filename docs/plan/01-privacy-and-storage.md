# Phase 1: Privacy and storage

**Goal:** API keys live only in KWallet (and in memory while the widget runs). Chats live in private per-chat files, not in Plasma's desktop config.

Paths below are relative to `org.kde.plasma.kdeaichat/contents/ui/` unless noted.

## Audit findings

### How keys leak into plaintext

- **Settings dialog writes keys to Plasma config.** The 16 built-in key fields are `cfg_*ApiKey` properties (`ConfigGeneral.qml:21-71`). Plasma saves every `cfg_` property to `~/.config/plasma-org.kde.plasma.desktop-appletsrc` on OK/Apply.
  - When the page opens, it copies wallet keys into those fields (`loadPlaintextApiKeyFallbacks` at 1317, and `kwalletLoadAll` → `applyLoadedKey` at 1217/1102). So pressing OK or Apply writes the wallet keys back out as plaintext.
- **The clean-up runs too late.** `clearPlaintextApiKeys()` only runs at the end of an async wallet store started from `Component.onDestruction` (1543-1546, 1289), which is after Plasma has already saved.
- **The clean-up skips old names.** `clearPlaintextApiKey` (995) ignores names not declared in `main.xml`, so leftover `qwenApiKey` and `huggingfaceImageApiKey` are never removed.
- **Custom provider keys are stored in plaintext.** They're written into `customProvidersJson` (3511-3527) as well as KWallet.
- **`~/.config/kdeaichatrc` is a stale plaintext file.** It's mode 0644 and holds 18 key entries. No live code writes it anymore; the helper commands for it (`kde_ai_helper.py:418-461`) are dead. The voice helper still reads voice settings from it (`voice_helper.py:1460`). README, the user manual and SETUP still describe it as a "fallback".
- **KWallet off or locked fails silently.** Nothing is shown to the user; the widget falls back to the plaintext copy (main.qml 4113/4117, ConfigGeneral 966/968).
- **What's already fine:**
  - Keys only travel in HTTP headers, never in process arguments.
  - Logs scrub secrets (`Security.js:238`).
  - Old builds did put keys in argv (`sync_config_keys`). The helper still reads its payload from argv (`kde_ai_helper.py:1253`), which is limited in size and visible in `ps`.

### Chat storage

- **All chats are one JSON string in Plasma config.** It's the `chatSessionsJson` entry: 732 KB, plus an orphaned duplicate in another config group.
- **Every save rewrites all of it, with no debounce.** `persistSessions` (`main.qml:272`) runs after every response, stop, edit, rename and scheduler injection. It's not per token: streaming only updates `currentStreamText`.
- **A stale snapshot can overwrite newer chats.** `ConfigOther.qml:30` snapshots `cfg_chatSessionsJson` when settings open, so pressing Apply can write back old chats (not verified at runtime).
- **The file-based history code is unused.** `write_history`, `read_history` and `migrate_history` exist (`kde_ai_helper.py:264-329`) but nothing calls them. `~/.local/share/kdeaichat/chats/` exists, empty, with mode 0755.
- **Requests can build from the wrong chat.** Both payload builders read `root.messages` instead of the target session (`main.qml:2894, 2938`), so a request can be built from whichever chat is on screen.

## Steps

1. **Remove the watchdog first.** It's running on users' machines now (see `07-cut-list.md`). Ship it as a small separate PR.
2. **`Secrets` component (KWallet only)**
   - Read the folder once at startup into memory; write a key only when the user changes it.
   - Key fields in settings are plain text fields, not `cfg_` properties, so Plasma never saves them.
   - Custom providers store only an id in config; their key goes to KWallet under that id.
   - If KWallet is off or locked, show it clearly in the chat ("Keys unavailable: KWallet is locked", with an unlock button), and don't fall back to plaintext.
3. **`ChatStore`**
   - One file per chat in `~/.local/share/kdeaichat/chats/<id>.json` (files 0600, directory 0700), plus `index.json` for the sidebar (title, updatedAt, archived, source, per-chat overrides, `openCodeSessionId`).
   - Writes are per chat, debounced (~500 ms) and atomic, done by the helper. The payload goes over stdin, not argv.
   - Keep the useful normalisation from `parseSessions`: id validation and dedup, source inference, truncation, and queued messages.
   - Payload builders take the target chat explicitly.
4. **One-time migration**, on first start of the new version:
   - Move every `*ApiKey` from every appletsrc group (including orphaned groups and undeclared names) and `customProvidersJson[].apiKey` into KWallet. Then blank them in appletsrc.
   - Delete `kdeaichatrc` after moving any voice settings it holds into normal config.
   - Split `chatSessionsJson` into chat files. Keep the old blob until the files are verified, then clear it, including the duplicate group.
   - Keep `lastSessionId`; the scheduler looks chats up by id (`main.qml:4920-4931`, `ScheduleDialog.qml:78`).
   - Show the user one line about what moved.
5. **Docs:** fix README, user manual, SETUP and CLAUDE.md to describe "KWallet only".

## Tests

- pytest for the helper: atomic chat write/read, permissions 0600/0700, payload over stdin, and migration from a sample appletsrc that includes orphaned groups.
- Offscreen QML test: the settings page with a fake wallet, OK/Apply, then assert no key in the saved config.
- Manual check with the harness: grep the real appletsrc and `kdeaichatrc` afterwards for `ApiKey=` with a value. There should be none.

## Done when

- No API key appears in any file under `~/.config` after using every settings path.
- A 700 KB history loads and saves without rewriting Plasma's desktop config.
