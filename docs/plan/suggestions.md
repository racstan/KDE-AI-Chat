# Suggestions for 1.4.0

These are new features to build **after** the fixes in phases 0-7 and **before** the 1.4.0 release (see `README.md`). They build on the rebuilt pieces: the shared backend interface (Phase 2), the message model (Phase 4) and the engine interface for voice (Phase 6).

Each suggestion lists **why**, a rough **size** (S = a day or less, M = a few days, L = a week or more) and a **priority**:
- **P1:** should be in 1.4.0.
- **P2:** good to have.
- **P3:** only if time allows.

Sources are noted where they apply: issue numbers, an audit finding, or "Linux users customise everything".

## 1. Make it yours (customisation)

Linux desktop users expect to shape their tools. Phase 4 removes the old hard-coded dark/light override; these replace it with real theming that respects the system theme by default.

| Suggestion | Why | Size | Pri |
|---|---|---|---|
| **Themes**: accent colour, bubble style (bubbles / flat / minimal), corner radius, density (compact / comfortable), chat font and code font, text size | Follows the Plasma colour scheme by default; everything overridable. | M | P1 |
| **Theme files**: themes are small JSON files in `~/.local/share/kdeaichat/themes/`; import/export; ship 3-4 built-in themes | People share rice setups; lets the community make themes without touching code. | S | P2 |
| **Layout options**: sidebar left/right/hidden, show/hide timestamps, model name, token usage; avatar or no avatar | Different panels and screen sizes need different layouts. | S | P1 |
| **Keyboard shortcuts**: global shortcut to open the chat (Plasma's standard applet shortcut), plus configurable in-chat keys (send, new chat, stop, focus search, read aloud) | Keyboard-first users. | S | P1 |
| **Popup size and position presets**, and a detachable window mode (open the chat as a normal window) | The popup is cramped for long agent sessions. | M | P2 |
| **Custom user CSS for rendered messages** (applied to the Markdown renderer's styling: code-block colours, quote style) | Power users' standard request; scoped so it can't break the layout. | S | P3 |
| **Syntax-highlight theme** picker for code blocks (KSyntaxHighlighting themes, the same ones Kate uses) | Consistent with the rest of KDE. | M | P2 |

## 2. KDE integration

| Suggestion | Why | Size | Pri |
|---|---|---|---|
| **KRunner plugin**: type `ai <question>` in KRunner and get the answer inline, or "open in chat" | Fastest way to ask something; suggested in #5. | M | P1 |
| **Dolphin service menu**: right-click a file → "Ask AI about this" / "Summarise" / "Open folder in harness chat" | Puts attachments and harness folders one click away; suggested in #5. | S | P1 |
| **"Ask about selection" global shortcut**: sends the current text selection (primary selection or clipboard) into a new chat | Replaces the removed auto-fill with an explicit, privacy-safe action. | S | P1 |
| **Notifications with actions**: finished replies and scheduled runs notify with "Open chat" / "Copy answer" | Uses Plasma's notification actions; pairs with Phase 5. | S | P1 |
| **Share via Purpose**: send an answer to email, KDE Connect (phone), Pastebin, etc. | Standard KDE share menu. | S | P2 |
| **D-Bus interface**: `org.kde.kdeaichat` with `Ask(text)`, `NewChat()`, `Open()` | Scripts, KDE Connect commands and other apps can drive the widget. | M | P2 |
| **Activity-aware chats**: optionally show only chats tagged with the current Plasma Activity | Keeps work and personal chats apart. | S | P3 |

## 3. Providers and models

| Suggestion | Why | Size | Pri |
|---|---|---|---|
| **Local server auto-detect**: on first run, probe localhost for Ollama (11434), LM Studio (1234), llama.cpp (8080), Jan (1337) and offer to add each one found | Zero-config local AI; suggested in #5. | S | P1 |
| **Model picker in the composer**: switch model per message from a dropdown next to Send, with favourites | Requested in #3; faster than the settings panel. | S | P1 |
| **Token and cost display** per reply and per chat (using provider-reported usage; prices user-editable) | Users paying per token want to see it. | S | P2 |
| **Fallback provider**: if the main provider errors or times out, retry on a chosen fallback | Free-tier rate limits are common. | S | P3 |
| **Reasoning controls**: thinking-level / reasoning-effort selector where the provider supports it; collapsible reasoning view | Modern models expose it. | S | P2 |

## 4. Harness mode

| Suggestion | Why | Size | Pri |
|---|---|---|---|
| **Agent Client Protocol (ACP) backend**: drive any ACP agent (`opencode acp` is available locally; Gemini CLI, Codex, Goose and Claude Code have ACP support or adapters) through one backend | One integration instead of one per harness; future agents work automatically. Fits the "don't reinvent, use the harness" goal. | L | P1 |
| **Session browser**: list, resume, rename and delete the harness's own sessions | OpenCode and Pi keep sessions; the widget should show them, not duplicate them. | M | P1 |
| **Diff viewer** for files the agent changed, with per-file "open in Kate" | Builds on `file_changed` events (Phase 3). | M | P2 |
| **Permission rules UI**: "always allow reading files in this folder" style rules, stored per workspace | Fewer prompts for trusted projects. | M | P2 |
| **Agent todo/plan panel** (OpenCode todos, Pi plan mode) | See what the agent intends before it does it. | S | P2 |
| **Workspace picker** with recent folders and Git branch shown | Harness chats are always about a folder. | S | P1 |

## 5. Chats

| Suggestion | Why | Size | Pri |
|---|---|---|---|
| **Search across all chats** (titles and content) | The per-chat search exists; cross-chat is the common ask once history grows. | S | P1 |
| **Pin, folders or tags** for chats | Long chat lists get unmanageable. | S | P2 |
| **Branching on edit**: editing an old message creates a branch instead of deleting everything after it; switch between branches | Safer than today's rewind, which deletes later messages. | M | P2 |
| **Prompt templates with variables**: `/translate {lang}` asks for `lang` before sending; templates importable as files | Extends existing templates. | S | P2 |
| **Personas / system-prompt presets** selectable per chat | One-click "code reviewer", "translator", etc. | S | P2 |
| **Import/export** chats as Markdown and JSON, including from other apps' JSON exports | Data portability; matches the privacy goal. | S | P2 |
| **Incognito chat**: never written to disk | Privacy goal. | S | P1 |

## 6. Voice

Builds on the pluggable engines in Phase 6.

| Suggestion | Why | Size | Pri |
|---|---|---|---|
| **Push-to-talk global shortcut**: hold a key anywhere to dictate into the chat (or into the focused app via the clipboard) | The most-used voice feature in other assistants. | M | P1 |
| **Hands-free conversation mode**: dictate → send → read reply aloud → listen again, with voice-activity detection | A real voice-assistant experience. | M | P2 |
| **Per-language voices**: auto-pick the TTS voice from the reply's detected language | Multilingual users. | S | P3 |

## 7. Privacy and trust

| Suggestion | Why | Size | Pri |
|---|---|---|---|
| **Privacy indicator**: a small badge per chat showing "local only" (local model, nothing leaves the machine) vs "cloud: <provider>" | Makes the privacy promise visible. | S | P1 |
| **Optional encryption of chat files at rest**, with the key in KWallet | For shared or laptop machines. | M | P3 |
| **Redaction before send**: optional regex/list rules (emails, keys, IPs) masked before a message leaves the machine | Protects against pasting secrets into cloud models. | M | P3 |

## 8. Quality and distribution

| Suggestion | Why | Size | Pri |
|---|---|---|---|
| **Human translations via KDE's translation teams** (or Weblate) instead of machine translation | Better quality; the current `.po` files are machine-generated. | S | P2 |
| **Accessibility pass**: screen-reader names on every control, full keyboard navigation, high-contrast check | Required for KDE quality; mostly labels. | S | P1 |
| **Packages**: AUR, openSUSE OBS and a Fedora COPR in addition to the KDE Store | Easier installs and updates for distro users. | M | P2 |
| **First-run setup**: one screen with "Use a local model" / "Use an API key" / "Use OpenCode or Pi", with detection results | Replaces the removed interactive guides with one focused flow. | M | P1 |

## Suggested P1 set for 1.4.0

Grouped so related work happens together:

1. **Customisation:** themes, layout options, keyboard shortcuts.
2. **KDE:** KRunner plugin, Dolphin service menu, "ask about selection", notification actions.
3. **Providers:** local server auto-detect, model picker in the composer.
4. **Harness:** ACP backend, session browser, workspace picker.
5. **Chats:** cross-chat search, incognito chat.
6. **Voice:** push-to-talk.
7. **Trust:** privacy indicator, accessibility pass, first-run setup.
