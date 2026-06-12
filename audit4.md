# KDE AI Chat — Full Codebase Audit

## Features Implemented

### AI Providers (21 providers)
| Provider | Status | Notes |
|----------|--------|-------|
| OpenAI | Working | Default model: gpt-4o-mini |
| Anthropic | Working | Separate API format handled |
| Groq | Working | |
| DeepSeek | Working | |
| MiniMax | Working | |
| Fireworks | Working | |
| Google (Gemini) | Working | |
| OpenRouter | Working | Custom headers (Referer/Title) |
| Mistral | Working | |
| Cloudflare | Working | |
| NVIDIA | Working | |
| Hugging Face | Working | |
| xAI (Grok) | Working | |
| LM Studio | Working | No API key needed |
| Local | Working | No API key needed |
| Ollama | Working | No API key needed |
| LiteLLM | Working | |
| Qwen | Working | |
| Moonshot | Working | |
| MiMo | Working | |
| Maritaca | Working | |

**Quality:** Provider registry in `ProviderService.js` is well-designed and data-driven. However, `ConfigGeneralLogic.js` has massive if/else chains (`currentProviderConfig`, `providerHasConfiguredKey`, `apiKeyForTarget`) that duplicate this registry instead of using it dynamically.

### OpenCode Integration
| Feature | Status | Notes |
|---------|--------|-------|
| Server start/stop | **Bug** | `page.startOpenCodeServer()` and `page.stopOpenCodeServer()` are called in ConfigOpenCodeSection.qml but never defined |
| Auto-start server | Working | |
| Auto-kill on idle | Working | Configurable timeout |
| SSE event stream | Working | Auto-reconnect on disconnect |
| Session management | Working | Creates/switches OpenCode sessions |
| Foreground streaming | Working | |
| Background scheduled requests | Working | |
| Provider/model discovery | Working | Probes /config/providers |
| Active sessions list | Working | With kill button |

### Chat & Session Management
| Feature | Status | Notes |
|---------|--------|-------|
| Create/delete sessions | Working | Refuses to delete last session |
| Switch sessions | Working | Saves state before switch |
| Rename sessions | Working | Inline editing |
| Archive/restore sessions | Working | |
| Fork sessions | Working | Fork from any message |
| Auto-name from first message | Working | First 5 words, max 30 chars |
| Unread badges | Working | |
| Session search | Working | Filters active/archived |
| Sort (updated/name/created/unread) | Working | |
| Session sidebar | Working | |
| Custom history path | Working | With migration support |
| Export to markdown/plaintext | Working | |

### Messaging
| Feature | Status | Notes |
|---------|--------|-------|
| Send messages | Working | Enter key, button click |
| Streaming responses | Working | SSE-based for OpenAI-compat and Anthropic |
| Message queue | Working | Max 5 queued messages |
| Edit messages | Working | Re-sends if user message |
| Delete messages | Working | |
| Copy message text | Working | Via clipboard helper |
| Quote/reply | Working | |
| Regenerate reply | Working | Shorter/longer options |
| File attachments | Working | Images, PDF, DOCX, etc. |
| Clipboard paste | Working | |
| Markdown rendering | Working | Code blocks, tables, links |
| Code block copy button | Working | |
| Table CSV export | Working | |
| Message search | Working | With prev/next navigation |
| Day-based message grouping | Working | |
| Token/char counter | Working | Display in input area |

### Scheduling System
| Feature | Status | Notes |
|---------|--------|-------|
| Create schedules | Working | Single-run and recurring |
| Cron expression builder | Working | Minutes/hours/days/weeks/months |
| Human-readable schedule summary | Working | |
| Edit schedules | Working | |
| Archive/restore schedules | Working | |
| Delete schedules | Working | |
| Enable/disable toggle | Working | |
| Execution history | Working | With success/failure status |
| Desktop notifications | Working | On schedule execution |
| Sound alerts | Working | On schedule execution |
| Missed schedule recovery | Working | Optional, configurable |
| /schedule command from chat | Working | Inline schedule creation |
| Systemd service integration | Working | Auto-start at login |
| Per-chat schedule view | Working | In chat settings |

### Security
| Feature | Status | Notes |
|---------|--------|-------|
| Shell injection prevention | Working | `sanitizeForShell()` strips metacharacters |
| URL validation | Working | Blocks javascript:/data:/file: |
| File path validation | Working | Rejects `..` traversal |
| Session ID validation | Working | Strict alphanumeric+dash whitelist |
| Secret scrubbing in logs | Working | Redacts API keys, tokens |
| Helper path containment | Working | Rejects paths outside /contents/ui/ |
| KWallet encryption | Working | 3 storage modes |
| **Exception:** `checkClipboardForAttachments()` | **Minor bug** | Uses direct string interpolation instead of `Sec.quoteForShell()` |

### KWallet Integration
| Feature | Status | Notes |
|---------|--------|-------|
| Bulk read all keys | Working | |
| Bulk write all keys | Working | |
| Individual key read | Working | |
| Individual key write | Working | |
| Wallet detection | Working | |
| Wallet creation | Working | |
| Wallet status check | Working | |
| Auto-unlock toggle | Working | Configurable |
| Permanent failure handling | Working | 3-attempt limit with manual reset |
| KWallet failure banner | Working | In settings UI |

### UI/UX
| Feature | Status | Notes |
|---------|--------|-------|
| Appearance modes | Working | Follow system/light/dark |
| 12 languages | Working | EN, AR, ZH, FR, DE, IT, JA, PT, RU, ES, HI |
| Notification sound | Working | Configurable |
| Interactive guides | Working | Toggleable |
| Keyboard shortcuts | Working | 11 customizable shortcuts |
| Custom popup size | Working | Width/height configurable |
| Configurable app name | Working | |

### Per-Chat Settings (Chat Settings Dialog)
| Feature | Status | Notes |
|---------|--------|-------|
| Context override toggle | Working | |
| Context enable/disable | Working | |
| Context limit | Working | Per-chat override |
| Auto-compact | Working | Per-chat override |
| Compact threshold | Working | Per-chat override |
| Manual compact button | Working | |
| Chat System Prompt | Working | Override global prompt per chat |
| Chat Memory | Working | Per-chat facts, deleted with chat |

### Context & Memory
| Feature | Status | Notes |
|---------|--------|-------|
| Global system prompt | Working | |
| Global memory | Working | Injected into every prompt |
| Global context limit | Working | |
| Auto-compaction | Working | Summarizes old messages |
| Per-chat system prompt | Working | Overrides global |
| Per-chat memory | Working | Deleted with chat |
| Compacted summary injection | Working | In system prompt |

### Scheduler Daemon (Python)
| Feature | Status | Notes |
|---------|--------|-------|
| Cron parsing | Working | 5-field with ranges/steps/lists |
| Schedule execution | Working | Writes trigger files |
| History management | Working | Capped at configurable limit |
| Missed schedule recovery | Working | Optional |
| SIGHUP reload | Working | |
| File-change detection | Working | Mtime-based |
| Lock file | Working | Prevents multiple instances |

### Document Extraction (Python)
| Feature | Status | Notes |
|---------|--------|-------|
| Plain text | Working | |
| PDF extraction | Working | Via pdftotext |
| DOCX extraction | Working | Via pandoc |
| Image base64 | Working | |
| Clipboard content | Working | |

### Advanced Features (Voice / TTS / STT & Memory)
| Feature | Status | Notes |
|---------|--------|-------|
| CPU Venv Setup | Working | CPU-optimized PyTorch build (~150MB) |
| GPU Venv Setup | Working | GPU-accelerated PyTorch with CUDA & cuDNN |
| STT Engine (Whisper) | Working | Selectable Whisper sizes, downloaded on demand |
| TTS Engine (Kokoro) | Working | Kokoro-82M model local synthesis |
| espeak-ng Installer | Working | Auto-detects package manager to install |
| Daemon Memory Tracking | Working | Live RSS memory read of scheduler, opencode, voice daemons |
| TTS Speak Test | Working | Synthesis preview tool in settings |

### Testing
| Module | Unit | Integration | Coverage |
|--------|------|-------------|----------|
| kde_ai_helper.py | 3 | 7 | Partial — 8/15 commands untested |
| kde-ai-scheduler.py | ~53 | 0 | Good for cron logic; no main-loop tests |
| doc_extractor.py | 11 | 4 | Moderate |
| Security.js | ~25 | — | Good |
| MarkdownRenderer.js | 7 | — | Good |
| LRUCache.js | 8 | — | Good |
| SessionManager.js | 10 | — | Good |
| RequestDeduplicator.js | 6 | — | Good |

---

## Bugs Found

### Critical
1. **OpenCode Start/Stop buttons broken** — `ConfigOpenCodeSection.qml` calls `page.startOpenCodeServer()` and `page.stopOpenCodeServer()` but these functions are never defined in `ConfigGeneral.qml` or `ConfigGeneralLogic.js`. Only `startOpenCodeServerAutomatically()` exists (different function). Buttons will throw runtime errors.

### Minor
2. **Shell injection in `checkClipboardForAttachments()`** — `MainDatabase.js:2567` uses direct string interpolation instead of `Sec.quoteForShell()` for the doc extractor path.
3. **Dead code in F1 handler** — `main.qml:288` checks for `openKeyboardShortcutsHelp` which doesn't exist.
4. **Duplicate provider if/else chains** — `ConfigGeneralLogic.js` has 4 massive if/else chains that duplicate `ProviderService.js` instead of using it.
5. **File handle leaks in Python helper** — 12+ instances of `json.load(open(...))` without `with` statements.
6. **Race condition on schedules.json** — Scheduler daemon and kde_ai_helper.py both read/write without file-level coordination.
7. **Silent data loss on corrupt schedules.json** — `_load_schedules()` returns empty defaults; next write overwrites everything.
8. **Flatpak manifest version mismatch** — References tag `1.3.0` but `metadata.json` says `1.3.1`.
9. **Service file inconsistency** — `install.sh` has `RestartSec=30` + ExecReload; bundled `.service` has `RestartSec=5` and no ExecReload.
10. **CI swallows QML/test failures** — `|| true` on qmllint, qmltestrunner, and markdownlint.

### Voice & Speech Regressions
11. **Terminal read blocker & blank setup screens** — `read -n 1` prompts in `voice_setup.sh` and QML terminal commands hung or exited instantly unless redirected via `</dev/tty`. Also, nested single quoting inside `konsole -e bash -c` caused blank terminal windows on newer terminal emulator packages. (Resolved by simplifying Konsole invocations to run script parameters directly, introducing a fallback `wait_for_keypress` routine that checks for interactive/character device TTYs, and consolidating model download/system installer tasks as sub-modes inside `voice_setup.sh`).
12. **Local variable scope typo in voice_helper.py** — `custom_path` referenced instead of `custom_model_path` (causing UnboundLocalError during voice synthesis initialization). (Resolved by scoping variables locally).
13. **Espeak placeholder clarity** — espeak-ng path input field placeholder was unclear, confusing users on whether manual path configuration was required when installed via system package manager. (Resolved by updating placeholder text).
14. **Sound Playback Failure in systemd mode** — systemd user services running without standard XDG or Pulse/Pipewire session variables would silently fail to produce audio. (Resolved via fallback shell command executions).

---

## Suggestions (Feasibility × Value × Ease)

### Tier 1: High Value, Easy to Implement (1-3 hours each)

| # | Feature | Why | Effort |
|---|---------|-----|--------|
| 1 | **Prompt Templates / Snippets** | Users constantly reuse prompts. Save/load from a JSON file. Add a button next to the input. | Low |
| 2 | **Quick Model Switch dropdown** | Change model mid-conversation without opening settings. Dropdown in the toolbar. | Low |
| 3 | **Response Length Control** | Slider or dropdown (Short/Medium/Long/Max) that adjusts max_tokens before sending. | Low |
| 4 | **Provider Health Check** | "Test Connection" button per provider. Simple GET to /models endpoint. | Low |
| 5 | **System Prompt Presets** | Save/load named system prompt configurations. Switch between "Coding", "Creative", "Concise" etc. | Low |
| 6 | **Regenerate with different temperature** | Add temperature slider to the regenerate dialog. | Low |

### Tier 2: High Value, Medium Effort (4-8 hours each)

| # | Feature | Why | Effort |
|---|---------|-----|--------|
| 7 | **Structured Output / JSON Mode** | Many providers support `response_format: { type: "json_object" }`. Add toggle in send area. | Medium |
| 8 | **Vision/Image Input** | Users paste images. Detect if provider supports vision, auto-attach as base64. Already have file attachments. | Medium |
| 9 | **Token Usage Tracking** | Display per-message token counts and cumulative session cost. Parse from API response `usage` field. | Medium |
| 10 | **Split View / Model Comparison** | Send same prompt to 2 providers side by side. Useful for comparing outputs. | Medium |
| 11 | **Chat Templates** | Pre-built conversation starters (Code Review, Debug, Explain, Translate). Each with system prompt + first message. | Medium |
| 12 | **Message Branching Tree View** | Visual tree showing conversation branches. Currently forks exist but no visual navigation. | Medium |

### Tier 3: Medium Value, Higher Effort (1-2 days each)

| # | Feature | Why | Effort |
|---|---------|-----|--------|
| 13 | **Function Calling / Tool Use** | OpenAI/Anthropic/Google support tool calling. Define tools, handle responses. Requires schema UI. | High |
| 14 | **RAG Lite** | Index local files/folders, inject relevant chunks into context. Leverage existing `doc_extractor.py`. | High |
| 15 | **D-Bus API** | Allow other KDE apps to send messages/query the widget. Useful for automation. | High |
| 16 | **KDE Connect Integration** | Share conversations to phone via KDE Connect. | High |

### Bug Fixes (Should Do)

| # | Bug | Effort |
|---|-----|--------|
| 1 | Fix OpenCode start/stop buttons (define missing functions) | 15 min |
| 2 | Fix shell injection in `checkClipboardForAttachments()` | 5 min |
| 3 | Remove dead F1 handler code | 5 min |
| 4 | Refactor provider if/else chains to use ProviderService | 2-3 hours |
| 5 | Fix file handle leaks in Python helper (use `with` statements) | 30 min |
| 6 | Fix Flatpak version mismatch | 5 min |
| 7 | Unify service file (install.sh vs bundled) | 10 min |
