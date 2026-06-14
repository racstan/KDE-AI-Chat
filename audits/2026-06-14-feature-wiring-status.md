# Feature Wiring Status - 2026-06-14

This matrix records configuration-to-runtime wiring. It does not claim that
external services are reachable without valid credentials, installed daemons,
models, and network access.

| Feature | Status | Verification |
| --- | --- | --- |
| OpenAI-compatible providers | Wired | Provider registry and request validation |
| Ollama / Local / LiteLLM / LM Studio | Fixed | Configured endpoints now reach runtime |
| Anthropic | Wired | Streaming and scheduled payload paths tested |
| OpenCode bridge | Wired | Session, event stream, permissions, questions, retry paths |
| Global and per-chat memory | Wired | Injected into the latest user message |
| Global/per-chat system prompt | Wired | Included in normal, scheduled, and OpenCode requests |
| Context limits/compaction | Wired | Context window and summary paths |
| Response length | Fixed | Per-chat prompt plus API token limits |
| Prompt templates | Wired | Slash-command expansion and autocomplete |
| Custom shortcuts | Wired | All configured key sequences map to runtime shortcuts |
| Scheduler | Fixed | Background polling continues at a reduced 15-second rate |
| STT/TTS | Improved | Optimistic state, adaptive polling, quieter transient failures |
| Image generation | Fixed | Missing provider settings and validation restored |
| Scrollbar | Restored | June 13 native attached scrollbar |

## Live Integration Still Required

- Send one real request through each configured provider family.
- Generate one image through each enabled image backend.
- Run OpenCode server start, reconnect, permission, question, and idle-stop flows.
- Exercise STT and TTS with the user's actual model files and audio device.
- Leave a schedule pending while the popup is closed and verify delivery.
- Test 1,000+ message histories with images, code blocks, search, and streaming.
