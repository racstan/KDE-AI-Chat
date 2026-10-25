# Where model variants can be fetched

Status: research, 2026-10-25. No app code changed. Facts marked (verified) were checked live on this machine; (docs) come from the cited pages.

"Variant" = a model's selectable reasoning level or mode (effort minimal..max, thinking on/off, budget). Owner rule: nothing hardcoded. Where a source reports nothing, show no picker.

## Summary

| Source | Reports variants? | Where | How the choice is sent |
|---|---|---|---|
| OpenRouter | Yes (per-model list) | `GET /api/v1/models`, `reasoning.supported_efforts` | `reasoning: {effort}` |
| OpenAI-compat (OpenAI, NIM, Groq, Mistral, DeepSeek, xAI, Fireworks, Together) | No | `/models` = `id, object, created, owned_by` only | `reasoning_effort: "<level>"` (Chat Completions) |
| Anthropic | Yes | `GET /v1/models`, `capabilities.thinking` and `capabilities.effort` | `thinking: {type:"adaptive"}` + `output_config: {effort}`; older models `thinking: {type:"enabled", budget_tokens}` |
| Gemini | Partial (on/off only) | native `models.get`: `thinking: bool` | `reasoning_effort` (compat) or `thinking_config.thinking_level` / `thinking_budget` |
| Ollama | Partial (on/off only) | `POST /api/show` `capabilities` | `think: true` or `think: "low"\|"medium"\|"high"` |
| OpenCode | Yes (ready-made, per model) | `GET /config/providers` -> `models[id].variants` | `variant: "<name>"` on the prompt body |
| Pi | Partial (flag only) | `pi --list-models` column `thinking yes/no` | `--thinking <level>` / `:<level>` model suffix |

## 1. OpenRouter (verified, public, no key)

`GET https://openrouter.ai/api/v1/models` returned 467 models. Per model:

- `supported_parameters: [...]`. Counts: `reasoning` 342, `include_reasoning` 342, `reasoning_effort` 212, `verbosity` 98.
- `reasoning` object (338 models). Keys seen: `mandatory` (always on), `default_enabled`, `supported_efforts`, `default_effort`, `supports_max_tokens`.

```json
"openai/gpt-5":        {"reasoning": {"mandatory": true, "supported_efforts": ["high","medium","low","minimal"], "default_effort": "medium"}}
"anthropic/claude-haiku-5.5": {"reasoning": {"mandatory": false, "supported_efforts": ["max","xhigh","high","medium","low","none"], "default_effort": "medium"}}
"google/gemini-2.5-pro": {"reasoning": {"mandatory": true}}          // reasons, but no levels reported
"anthropic/claude-sonnet-4.5": {"reasoning": {"mandatory": false}}   // can reason, no levels reported
```

Level sets differ per model (most common: `max,xhigh,high,medium,low,none`; also `high,medium,low`; `high,medium,low,minimal`). `none` means thinking can be switched off. A model with `reasoning` but no `supported_efforts` has a toggle at most (`mandatory:false` = optional, `mandatory:true` = always on, nothing to pick).

Sending (docs: https://openrouter.ai/docs/use-cases/reasoning-tokens): body `"reasoning": {"effort": "high"}` (or `{"max_tokens": 2000}`, `{"enabled": true}`, `{"exclude": true}`). Chat Completions also accepts the flat `reasoning_effort` listed in `supported_parameters`. Reasoning text comes back as `delta.reasoning` (already handled by DirectBackend.js).

Verdict: **yes**. Best source for any user going through OpenRouter.

## 2. Other OpenAI-compatible `/models`

- NVIDIA NIM `GET https://integrate.api.nvidia.com/v1/models` (verified with the KWallet key, key not printed): 85 models, every object has only `id, object, created, owned_by`. No reasoning info.
- OpenAI (docs, https://platform.openai.com/docs/api-reference/models/object; the page returned 403 to the fetcher, the shape is long-standing): `id, object, created, owned_by`. No reasoning info.
- Groq, Mistral, DeepSeek, xAI, Fireworks, Together: not checked live (no keys); they use the same OpenAI-style list. Together adds `type`, `context_length`, `pricing` but, as far as known, no effort levels. Treat as not reporting.
- Indirect source: OpenCode's catalogue (section 6) knows variants for nvidia, groq, mistral, deepseek, fireworks-ai, openai and a dozen more providers, derived from bundled metadata, not from the provider API.

Sending: Chat Completions `"reasoning_effort": "low"|"medium"|"high"` (plus `minimal`/`none`/`xhigh`/`max` where a model allows them); Responses API `"reasoning": {"effort": "high"}`. Compat vendors reuse `reasoning_effort` (Groq, Cerebras, Mistral, DeepSeek, Fireworks all appear in OpenCode with `{"reasoningEffort": ...}` options). The allowed values are per model and not machine-readable at the vendor, so the picker needs another source or stays hidden.

Verdict: **no**.

## 3. Anthropic (docs)

`GET https://api.anthropic.com/v1/models` (https://platform.claude.com/docs/en/api/models/list) has `capabilities` per model:

```json
"capabilities": {
  "effort":   {"supported": true, "low": {"supported": true}, "medium": {...}, "high": {...}, "xhigh": {...}, "max": {...}},
  "thinking": {"supported": true, "types": {"adaptive": {"supported": true}, "enabled": {...}, "disabled": {...}, "between_tools": {...}}}
}
```

Both effort levels and thinking modes are reported. Levels = the keys whose `supported` is true; `xhigh` may be null.

Sending (https://platform.claude.com/docs/en/build-with-claude/extended-thinking):
- Adaptive models (4.6 and later): `"thinking": {"type": "adaptive"}, "output_config": {"effort": "high"}`.
- 4.7 and later reject `type:"enabled"` with a 400. Older models (4.5 and earlier): `"thinking": {"type": "enabled", "budget_tokens": 10000}` (min 1024, below `max_tokens`).
- Off: `"thinking": {"type": "disabled"}` (only if `types.disabled.supported`).
- Changing the setting mid-conversation invalidates prompt-cache breakpoints.

Verdict: **yes**, needs an Anthropic key. Via OpenRouter, newer Anthropic models carry `supported_efforts`, older ones only `reasoning`.

## 4. Google Gemini (docs)

- Native `GET https://generativelanguage.googleapis.com/v1beta/models` / `models.get` (https://ai.google.dev/api/models): Model has `thinking: boolean` ("Whether the model supports thinking"). No level list.
- The OpenAI-compat endpoint's model list is the OpenAI shape (ids only).
- Sending (https://ai.google.dev/gemini-api/docs/openai): compat `reasoning_effort: "minimal"|"low"|"medium"|"high"` (maps to `thinking_level` on Gemini 3, to budgets 1024/8192/24576 on 2.5; `none` disables only on 2.5; Pro and 3 cannot disable). Or `extra_body: {"google": {"thinking_config": {"thinking_level": "low", "include_thoughts": true}}}`. Native: `generationConfig.thinkingConfig {thinkingLevel | thinkingBudget, includeThoughts}`. Do not combine `reasoning_effort` with `thinking_config`.
- Valid level sets differ per model (Flash: low/medium/high) and the API does not report them. OpenCode's catalogue does carry them (`{"thinkingConfig": {"includeThoughts": true, "thinkingLevel": "high"}}`).

Verdict: **partial** (boolean only).

## 5. Ollama (docs + local check)

A local Ollama is running (`GET localhost:11434/api/tags` returned models; only `nomic-embed-text` was looked at, so no thinking model was probed). `POST /api/show {"model": "..."}` returns `capabilities: [...]`; the docs example shows `["completion", "vision"]` and `thinking` is the capability name for reasoning models (https://github.com/ollama/ollama/blob/main/docs/api.md; confirm on a pulled thinking model before relying on it). No level list.

Sending: `/api/chat` body `"think": true|false`, or a level string `"low"|"medium"|"high"` (docs also list `"max"`). Models differ (gpt-oss wants the strings, most others only the boolean), and that is not reported. Output arrives in `message.thinking`.

Verdict: **partial**: show an on/off toggle if `thinking` is in `capabilities`; no level picker. Cost: one `/api/show` per model, on selection.

## 6. OpenCode (verified; own `opencode serve`, stopped afterwards)

`GET /config/providers` returns `{providers:[{id,name,models:{<id>:{capabilities,variants,...}}}]}`. Models with `variants` out of total (and with `capabilities.reasoning`): openrouter 198/372 (260), openai 24/24, nvidia 14/38 (15), groq 4/11 (4), google 23/37 (29), deepseek 2/2, mistral 7/21 (7), fireworks-ai 34/38.

`variants` is a map: variant name to the provider options OpenCode merges into the request. The shape depends on the provider:

```json
openai/gpt-6-luna:  {"low": {"reasoningEffort":"low","reasoningSummary":"auto","include":["reasoning.encrypted_content"]}, "none":{...}, "max":{...}}
openrouter/*:       {"low": {"reasoning": {"effort": "low"}}, "medium": {...}, "high": {...}}
nvidia/*:           {"none": {"reasoningEffort":"none"}, "minimal":{...}, "low":{...}, ..., "max":{...}}
groq/qwen3.8-27b:   {"none","default","low","medium","high"}  each {"reasoningEffort": ...}
google/gemini-3.7-flash: {"low": {"thinkingConfig": {"includeThoughts": true, "thinkingLevel": "low"}}, ...}
agentrouter/claude-opus-4-8: {"low": {"thinking": {"type":"adaptive","display":"summarized"}, "effort":"low"}, ...}
```

A model with no `variants` (or empty) has none: no picker. Caveat: OpenCode builds these from its bundled catalogue plus rules, so they are "reported by OpenCode", not by the vendor; a model OpenCode does not know has none.

Sending: both `POST /session/{id}/message` and `POST /session/{id}/prompt_async` accept `variant: string` next to `model` and `agent` (OpenAPI at `GET /doc`, verified). The value is the variant NAME (the map key). The widget's `backends/OpenCodeBackend.js` does not send one today.

Security note: `/config/providers` echoes API keys of providers configured in the user's OpenCode (field `key`). Never log or persist the response whole; keep only each model's `variants` keys.

Verdict: **yes**, for OpenCode mode. Also the only vendor-neutral catalogue of per-model levels for providers whose own API reports nothing, but it needs a running OpenCode server, so it cannot serve direct mode on its own.

## 7. Pi (verified)

`pi --list-models` prints a table `provider model context max-out thinking images`; `thinking` is `yes`/`no` only. No level list. Levels are Pi's own: `off, minimal, low, medium, high, xhigh, max` (`pi --help`).

Sending: `pi --thinking <level>`, or model suffix `--model sonnet:high`. The widget already does this: `chat/PiMode.qml` passes `thinking` to the bridge; `kdeaichat/pi_bridge_server.py` validates against `THINKING` and adds `--thinking`. `chat/PiChatSettings.qml` offers a hardcoded list of the same levels.

Verdict: **partial**: the `thinking` column says whether a model reasons at all. The level list is Pi's, not per model.

## What the widget does today

- Direct mode sends NO reasoning parameter: `backends/DirectBackend.js`, `ProviderService.js` and `ProviderCheck.js` contain no `reasoning_effort`/`thinking` request fields. DirectBackend only RECEIVES reasoning: `delta.reasoning`, `delta.reasoning_content`, `delta.thinking`, Anthropic `thinking_delta` and `<think>` tags become `reasoning_delta` events shown by `chat/ReasoningBlock.qml`.
- Pi: per-chat `piThinking` (EffectiveConfig.js), hardcoded eight levels in PiChatSettings.qml, validated again in pi_bridge_server.py.
- OpenCode: provider/model/agent only; no variant.
- ProviderCheck.js caches model lists per provider for the settings session; cached entries are ids only.

## Recommendation

One shape for all sources, stored on the model entry (not a separate registry):

```js
model = { id, name, ..., variants: [ { id: "high", label: "High", send: {...} } ] }   // [] or absent = no picker
// send = the exact fragment to merge into the request for that mode:
//  openrouter : { reasoning: { effort: "high" } }
//  openai-compat (from OpenCode, if used): { reasoning_effort: "high" }
//  anthropic  : { thinking: {type:"adaptive"}, output_config: {effort:"high"} }
//  gemini     : { reasoning_effort: "high" }
//  ollama     : { think: true }
//  opencode   : { variant: "high" }   (name only; OpenCode merges the options itself)
//  pi         : { thinking: "high" }
```

The setting stores only the variant `id` (per chat, falling back to a global default). The `send` fragment is looked up at send time, so a stale id that is no longer in the list is dropped and nothing is sent.

Where fetched (extend ProviderCheck.js, same per-provider session cache, same trigger as the model list):
1. OpenRouter: map `reasoning.supported_efforts` (including `none`) to variants from the existing `/models` call; no extra request. `reasoning` without efforts: no picker.
2. Anthropic: map `capabilities.effort` keys with `supported:true`, plus an off variant if `thinking.types.disabled.supported`. Same call as the model list.
3. Gemini native list: `thinking:true` gives at most an on/off variant.
4. Ollama: `/api/show` lazily when a model is selected; `thinking` capability gives an on/off variant.
5. Other OpenAI-compat providers: no variants. Optional later: if the user's OpenCode is running, reuse its `/config/providers` variants for the same provider and model id (read only the `variants` keys).
6. OpenCode mode: fetch `/config/providers` once per server connection, keep `models[id].variants` names only, send `variant` with `prompt_async`.
7. Pi mode: parse `pi --list-models` (new helper command, one run, cached); show the picker only for `thinking yes`.

Per-mode send path: DirectBackend merges `variant.send` into the request body just before JSON encoding (after the provider shaping in ProviderService.js, never overriding `model`/`messages`/`stream`); OpenCodeBackend adds `variant` to the prompt body; Pi passes `thinking` to the bridge as today. For pre-4.6 Claude (`types.adaptive` false, `types.enabled` true) the budget is a per-model choice that no API reports, so offer on/off only (budget needs an owner decision).

Open questions for the owner: (a) accept Pi's fixed level list as Pi's own vocabulary; (b) accept reading OpenCode's catalogue for providers whose own API reports nothing; (c) token budgets for pre-4.6 Claude models.
