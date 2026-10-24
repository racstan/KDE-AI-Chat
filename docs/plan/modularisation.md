# Modularisation

**Owner request (2026-10-24):** several files are thousands of lines long, which makes the code almost impossible to maintain. Split them up.

**Approach:** split each file **during the phase that rewrites it**, not as one big refactor.
- Not first: `main.qml`'s chat logic has no tests, so splitting 5,100 lines blind could break things unnoticed. The Phase 0 harness is what makes splitting verifiable.
- Not last: phases 1-4 rewrite most of this code anyway. Splitting it first and then rewriting would do the work twice.

**Rule:** no source file over **~400 lines** (QML, JS or Python) without a written reason in the file's header comment.

## Today

21,187 lines across 17 files. Eight files are over 1,000 lines:

| File | Lines |
|---|---|
| `ui/main.qml` | 5,109 |
| `ui/ConfigGeneral.qml` | 3,658 |
| `ui/FullRepresentationContent.qml` | 2,040 |
| `ui/voice/voice_helper.py` | 1,536 |
| `ui/ScheduleDialog.qml` | 1,391 |
| `ui/kde_ai_helper.py` | 1,324 |
| `ui/ConfigOther.qml` | 1,281 |
| `ui/ConfigVoice.qml` | 1,048 |
| `scripts/kde-ai-scheduler.py` | 746 |
| `ui/ProviderService.js` | 653 |
| `ui/ChatSettingsDialog.qml` | 600 |

## Split map

| Today | Becomes | Phase |
|---|---|---|
| `main.qml`: storage, sessions | `store/ChatStore.qml`, `store/SessionIndex.qml` | 1 |
| `main.qml`: KWallet | `store/Secrets.qml` | 1 |
| `main.qml`: provider requests, streaming | `backends/Backend.js`, `backends/DirectBackend.js`, `backends/sse.js` | 2 |
| `ProviderService.js` | `providers/presets.js` (data only), `providers/ProviderList.qml` | 2 |
| `main.qml`: OpenCode, Pi | `backends/OpenCodeBackend.js`, `backends/PiBackend.js`; `helper/pi_bridge.py` | 3 |
| `main.qml`: what remains | `main.qml` wiring only (< 300 lines) + `ChatController.qml` (send, queue, edit, regenerate) | 4 |
| `FullRepresentationContent.qml` | `chat/ChatView.qml`, `chat/Composer.qml`, `chat/SessionList.qml`, `chat/delegates/*.qml` (one per role), `chat/ToolCard.qml`, `chat/PermissionCard.qml`, `chat/MarkdownBlock.qml` | 4 |
| `ChatSettingsDialog.qml` | `chat/ChatSettingsPanel.qml` + reused settings components | 4 |
| `ConfigGeneral.qml` | `config/ConfigProviders.qml`, `config/ConfigHarness.qml`, `config/components/*` (ProviderEditor, KeyField, ModelPicker) | 2-4 |
| `ConfigOther.qml`, `ConfigSystemPrompt.qml` | `config/ConfigChat.qml` (prompt, limit, templates), `config/ConfigAppearance.qml` | 4 |
| `ScheduleDialog.qml` | `schedules/ScheduleList.qml`, `schedules/ScheduleEditor.qml`, `schedules/cron.js` (pure, node-tested) | 5 |
| `kde_ai_helper.py` + `scripts/kde-ai-scheduler.py` | a `kdeaichat/` Python package: `cli.py` (command dispatch), `files.py` (atomic I/O, paths), `chats.py`, `secrets.py`, `schedules.py`, `systemd.py`, `run_schedule.py`; `kde_ai_helper.py` stays as a thin entry point | 1, 5 |
| `ConfigVoice.qml`, `VoiceManager.qml` | `voice/VoiceSettings.qml`, `voice/TtsEngine*.qml`, `voice/SttClient.qml` | 6 |
| `voice/voice_helper.py` | `voice/stt_service.py` (socket-activated) + `voice/engines/*.py` (one per STT engine) | 6 |

## Guard rails

- **CI size check** (`scripts/check_file_sizes.py`): fails when a source file exceeds 400 lines and isn't on an allowlist. The allowlist starts with today's big files and their current sizes, which may only shrink. Each phase removes its entries. Phase 7 checks the list is empty.
- **Module boundaries:**
  - Backends and pure logic (`backends/`, `schedules/cron.js`, `providers/presets.js`) never touch QML globals, so node tests can load them.
  - UI components get data through properties, not by reaching into `root`.
- **CLAUDE.md** is updated with the new layout at the end of each phase.

## Done when

- Every source file is under ~400 lines, or has a written reason.
- `main.qml` is wiring only.
- The size allowlist is empty.
