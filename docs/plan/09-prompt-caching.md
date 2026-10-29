# Prompt caching in direct chats

Goal: long direct chats cost less because the provider can reuse the start of each request.

## What was unstable

Checked everything that goes into a direct request (`chat/DirectRequest.qml`): system prompt (Personality, main, project and chat instructions, response length), tool definitions, history. Already stable: no date or time anywhere, tools come in provider order (`DirectToolRunner.collectTools` keeps slots by provider index), memories are added to the message being answered, not to the system prompt (`chat/Memory.qml`). Left as it is: the memory block sits on the newest user message only, so when that message becomes history it loses the block. That only changes what comes after the last cache breakpoint (the reply before it), so nothing cached is lost. The test `tests/qml/tst_prompt_prefix.qml` builds two consecutive requests and asserts tools, system and earlier messages are byte-identical (OpenAI and Anthropic formats).

## What changed

- `backends/DirectCache.js` (new), called from `DirectBackend.buildRequest` (option `cache`):
  - Anthropic API: `cache_control: {"type":"ephemeral"}` on the last tool, the system prompt (string becomes a one-block list) and the message before the new user turn (during a tool loop: the tool-result message). 3 of the 4 allowed breakpoints. Thinking blocks and empty text are never marked.
  - OpenRouter with a model id starting `anthropic/`: the same marks as content parts on the system message and that message.
  - Every other server (OpenAI, Ollama, LM Studio, llama.cpp, vLLM, OpenRouter with other models): no new fields.
- Usage: `cacheRead` / `cacheWrite` in usage events (OpenAI `prompt_tokens_details.cached_tokens`, OpenRouter also `cache_write_tokens`, Anthropic `cache_read_input_tokens` / `cache_creation_input_tokens`, stream and not). `ReplyEvents.qml` stores them as `reply.tokens.cache = {read, write}` (the shape OpenCode replies already use); Chat info shows "Read from cache" and "Written to cache" (`ChatStats.js`, `ChatInfoSummary.qml`). Cached tokens are a part of Input tokens, not extra.

## Pi finding (investigation only)

Our code does not touch Pi's compaction: Pi compacts inside `pi --mode rpc`. Per Pi's `docs/compaction.md`, compaction replaces older messages with a summary, so the request after it has a new start: only the part before the summary (system prompt and tools, about the 1,792 cached tokens seen) can still hit, everything else is new text. That drop is inherent to compacting, not a bug in the bridge; the next turns should cache again from the summary on. Not verified against a live session. Pi's compaction requests themselves disable cache writes, so they do not warm the cache for the next turn.
