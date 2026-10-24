# Phase 2: Shared backend interface and direct API mode

**Goal:** one small, well-tested path for talking to a provider with the user's key. It sits behind the same interface the harnesses use (Phase 3), so the UI never cares which mode is running.

Paths below are relative to `org.kde.plasma.kdeaichat/contents/ui/`.

## Audit findings

- **Routing:** `sendMessageByIndex` (`main.qml:2527-2532`) sends Anthropic-type providers to `doAnthropicRequest` and everything else to `doOpenAICompatRequest` (`/chat/completions`). Gemini uses Google's OpenAI-compatible endpoint; there's no native Gemini code, which is fine.
- **Providers:**
  - `ProviderService.js:26-284` has 22 chat providers plus 7 `image-gen` entries.
  - 19 appear in settings (`ConfigGeneral.qml:180-198`); qwen, moonshot and mimo are in the registry only.
  - `image-gen` entries would wrongly fall through to the chat path.
  - Custom providers are `openai-compat` or `anthropic` (`ConfigGeneral.qml:3475`).
- **Streaming:**
  - Only OpenAI-compatible responses stream (`main.qml:3022`). Anthropic waits for the full reply (3370).
  - The SSE parser (3167-3176) buffers partial lines correctly. It only accepts `data: ` with a space, ignores `event:` lines, and silently drops lines that aren't valid JSON (3238).
  - `<think>` blocks are extracted as reasoning; there's a 20 MB cap.
- **Timeout and cancel:**
  - `requestTimeout` defaults to 60 s.
  - Cancel bumps a generation counter and aborts the request (552); partial text is kept.
- **Bug:** both payload builders read `root.messages`, the chat on screen, not the chat being sent (2894, 2938). Fixed by the ChatStore in Phase 1.
- **Clutter being removed (owner decision):**
  - MCP tools; streaming was even switched off whenever they were enabled.
  - System-info injection, memory block, compaction.
  - See `07-cut-list.md`.

## Steps

1. **`backends/Backend.js`: the shared contract.**
   - Methods: `send(chatId, parts)`, `abort()`, `listModels()`, `loadHistory()` (no-op for direct mode).
   - Events, the same for every backend:
     ```
     start{turnId}
     text_delta{delta}        reasoning_delta{delta}
     tool_start{callId,name,input}  tool_update{callId,output}  tool_end{callId,output,isError}
     file_changed{path,diff?}
     permission_request{id,tool,detail}  -> reply(id, "once"|"always"|"reject")
     question_request{id,questions[]}    -> answer(id, answers) / reject(id)
     usage{input,output,reasoning,cost}
     error{message,retryable}
     done{reason: "complete"|"aborted"|"error"}
     ```
   - Direct mode only emits `start`, text and reasoning deltas, `usage`, `error` and `done`.
2. **`backends/DirectBackend.js`**
   - OpenAI-compatible `/chat/completions` with streaming.
   - **Anthropic `/v1/messages` with streaming**, which is new.
   - A spec-compliant SSE parser (optional space after `data:`, `event:` lines, errors reported instead of dropped).
   - Pure JS with no QML globals, so node tests can drive it with recorded streams.
3. **Provider list with presets**
   - Settings hold a list of providers: `{id, name, type: openai|anthropic, baseUrl, model}`. The key lives in KWallet under `id` (Phase 1).
   - "Add provider" offers presets: OpenAI, Anthropic, Groq, DeepSeek, Gemini, OpenRouter, Mistral, NVIDIA, xAI, Ollama, LM Studio, llama.cpp, LiteLLM, … . A preset just fills in the URL and a default model, so adding a provider never needs a code change.
   - **Fetch models from the provider** (`GET /models`) where supported, with free-text fallback.
   - Delete the 20 hard-coded `*BaseUrl`/`*ApiKey`/`*Model` trios and the `image-gen` entries, and migrate users' existing values into the list.
4. **Default output limit.** Send `max_tokens` (default 4096, configurable per provider and per chat) on every request. Without it, OpenRouter reserves credit for the model's maximum output (131,072 tokens for `openrouter/auto`) and returns HTTP 402 on accounts with a small balance. Found in the live end-to-end test on 2026-10-24.
5. **System prompt:** keep one system-prompt text field (global plus a per-chat override) and the message limit. Remove the rest (see cut list).

## Tests

- node: request building for both API types, streaming parse from recorded fixtures (split chunks, `[DONE]`, error mid-stream, `<think>`), abort mid-stream.
- Offscreen QML: provider add/edit/delete with a fake wallet; send with a fake backend.
- Manual via harness: one real request each to an OpenAI-compatible provider and to Anthropic.

## Done when

- Any OpenAI-compatible or Anthropic endpoint works by adding it in settings, and both stream.
- `ProviderService.js` has no per-provider code paths.
