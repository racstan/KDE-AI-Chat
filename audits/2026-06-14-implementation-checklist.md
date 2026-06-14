# Implementation Checklist - 2026-06-14

## Phase 1 - Stabilize Current Build

- [x] Restore the June 13 native attached scrollbar and full ListView model.
- [x] Remove the custom scrollbar geometry and visible-message slice.
- [x] Check for duplicate/invalid declarations in the edited hot paths.
- [x] Run static diff checks and Python tests.

## Phase 2 - Smooth Streaming and Errors

- [x] Add a queued `queueScrollToBottom()` helper.
- [x] Replace direct `Qt.callLater(scrollToBottom)` in hot paths.
- [ ] Ensure error insertion uses the same append/session path as normal messages.
- [x] Keep error UI lightweight and avoid rich markdown parsing for errors.

## Phase 3 - Reduce Delegate Work

- [x] Remove slice index conversion from the runtime path.
- [x] Use direct ListView-to-session message indices.
- [x] Precompute day counts/labels once per message array update.
- [x] Cache lowercase search text per message.

## Phase 4 - Voice Responsiveness

- [x] Make STT/TTS buttons change state immediately on click.
- [x] Reduce steady-state voice polling frequency.
- [x] Move transient voice daemon failures to status text instead of chat bubbles.
- [ ] Keep final, actionable failures as user-visible errors.

## Phase 5 - Settings and Feature Wiring

- [x] Honor configured Local and Ollama endpoints.
- [x] Wire OpenAI, Google, Stability, and Replicate image settings.
- [x] Honor the configured Pollinations endpoint.
- [x] Validate all image providers instead of bypassing validation.
- [x] Apply response-length preferences to prompts and API token limits.
- [x] Make model and response-length overrides session-specific.
- [x] Keep scheduler trigger polling active at a reduced background rate.
- [x] Add provider configuration regression tests.

## Phase 6 - Architecture Cleanup

- [ ] Extract `ChatList.qml`.
- [ ] Extract `ChatComposer.qml`.
- [ ] Extract `VoiceController.js`.
- [ ] Extract `SessionStore.js`.
- [ ] Add a small performance/debug panel or log mode for stream flushes, parse counts, delegate count, and voice latency.
