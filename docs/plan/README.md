# KDE AI Chat 1.4.0: rebuild plan

Status: plan, 2026-10-24. Nothing here is implemented yet. Every phase file starts with an audit of the current code (with file:line references), then the design, steps, tests and a "done when" checklist.

## Goal

A Plasma widget that does six things well, and nothing else:

1. **GUI**: beautiful, fast, stable.
2. **Direct API mode**: talk to any provider with your own key.
3. **Harness mode**: drive OpenCode or Pi, so their agent features are usable from the desktop without reinventing them.
4. **Privacy**: keys in KWallet, chats in private local files.
5. **Scheduling**: run prompts on a schedule, even with the widget closed.
6. **Voice**: read aloud and dictation.

## Phases

| # | File | What | Size |
|---|---|---|---|
| 0 | [00-dev-harness.md](00-dev-harness.md) | Lets Claude launch, click, screenshot and check the widget without restarting your desktop. CI that catches components failing to load. | S |
| — | [07-cut-list.md](07-cut-list.md) (watchdog row) | Remove the plasmashell watchdog. It's running on users' machines now. | S |
| 1 | [01-privacy-and-storage.md](01-privacy-and-storage.md) | Keys only in KWallet; chats in per-chat files; one-time migration. | M |
| 2 | [02-direct-mode.md](02-direct-mode.md) | Shared backend interface; direct mode with streaming for OpenAI-compatible and Anthropic; provider list with presets. | M |
| 3 | [03-harness-mode.md](03-harness-mode.md) | Fix OpenCode (permissions, tools, stop, long runs); Pi over RPC with streaming; tool and permission cards. | L |
| 4 | [04-gui.md](04-gui.md) | Rebuild the chat view on a real model; one scroll rule; design pass; performance budget. | L |
| 5 | [05-scheduling.md](05-scheduling.md) | systemd timers, headless runs, notifications; no polling. | M |
| 6 | [06-voice.md](06-voice.md) | Read aloud via Qt's built-in TTS (zero setup); dictation as an on-demand service with no torch. | M |
| 7 | [07-cut-list.md](07-cut-list.md) | Final removal of everything on the cut list, migration of old settings, docs and screenshots. | S |
| — | [modularisation.md](modularisation.md) | Split every 1,000+-line file into small modules, phase by phase; CI size guard. | — |
| — | [suggestions.md](suggestions.md) | New features after the fixes: customisation, KDE integration, ACP, voice, privacy. | — |
| — | [variants-sources.md](variants-sources.md) | Research: where per-model reasoning variants can be fetched, and how each is sent. | — |

Each phase is one or more PRs that leave the widget working.

**Release:** everything ships together as **1.4.0**, in this order: the fixes in phases 0-7, then the features in [suggestions.md](suggestions.md), then the release. Nothing is released in between, so `master` can be mid-rebuild.

**Why this order:**
- The harness comes first because it makes every later phase faster and verifiable.
- Privacy comes before features because it touches user data today.
- The GUI follows the backend work because it needs the message model (Phase 1) and the shared event stream (Phases 2-3).

## Headline findings

- **API keys leak to plaintext.** The settings dialog writes them back into `~/.config/plasma-org.kde.plasma.desktop-appletsrc` on every OK/Apply; the clean-up runs too late. A stale `~/.config/kdeaichatrc` (mode 0644) holds 18 more.
- **All chats are one 732 KB JSON string inside Plasma's desktop config**, rewritten after every reply.
- **The GUI is unstable because the message list is a plain JS array that's replaced on every change.** Every bubble is destroyed and rebuilt, which also resets scrolling. Auto-scroll locks after the first send and never unlocks.
- **OpenCode permission prompts, tool display and Stop don't work.** The code reads the wrong event fields, sends invalid answers and never calls abort. Long runs fail at 60 s.
- **Pi gets no streaming at all.** It's one process per message, with a 60 s default timeout.
- **Scheduled prompts only run while the widget is open.** They can re-fire after saving settings, and a Python daemon wakes every 5 s.
- **Voice setup installs torch, spacy and transformers.** The dictation service preloads a model at login and never frees it. Reading aloud can use Qt's built-in TTS instead, with zero setup.

## Decisions

| Decision | Status |
|---|---|
| Remove watchdog, MCP in direct mode, sys-info, memory manager, compaction, process monitor, screen capture, selection auto-fill, open-in-terminal, guides, language and appearance overrides | **Decided** (owner, 2026-10-24) |
| Scheduled direct-API prompts run headless, needing KWallet unlocked at that time, versus only while the widget is open | **Open**: see `05-scheduling.md` |
| Drop the 7 image-generation provider entries | **Open**: proposed in `02-direct-mode.md` |
| Design mock-ups reviewed by the owner before polishing | Planned in `04-gui.md` |

## Progress tracking

Progressor is set up in this repo (`.progressor/`). After restarting Claude Code, each phase becomes a goal and each step a task, visible on the dashboard at http://localhost:4747. These files stay the readable spec; Progressor tracks where the work is.
