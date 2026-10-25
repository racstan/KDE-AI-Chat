# Where images can come from (generation services and chat replies)

Status: research, 2026-10-25. No app code changed. Facts marked (verified) were checked live on this machine; (docs) come from the cited pages; (unverified) could not be checked.

Goal: let the widget show images in replies (direct mode) and optionally generate images from a prompt with a service that needs no account. Rule: follow each service's published usage rules; never work around a limit, never fake a referrer or user agent.

## Summary

| Source | Needs account/key? | Output | Anonymous limit | Latency (verified) | Fit |
|---|---|---|---|---|---|
| Pollinations legacy `image.pollinations.ai/prompt/...` | No | `image/jpeg` bytes in the response | 1 image per 45 s per IP, model `sana` only, watermark | 8 to 11 s for 256-512 px | Works, but legacy and tight |
| Pollinations `gen.pollinations.ai` | Yes (`sk_` key, or user-authorised key via OAuth "BYOP") | jpeg/png/svg | n/a | n/a | Not anonymous: 401 |
| AI Horde `aihorde.net`, key `0000000000` | No | R2 URL (webp) or base64 webp | Lowest queue priority; over 586x586 needs kudos upfront | ~17 s total, 0 s queue (idle) | Best truly keyless option, async |
| Chat model images (OpenRouter, Gemini, OpenAI) | Provider key the user already has | base64 data URL / b64 | Provider limits and cost | n/a | Show in replies, not a "free" source |
| Markdown image links in text | none | remote URL | n/a | n/a | Render only with a safe-URL policy |

## 1. Pollinations.ai

### Endpoints (verified)

- **Legacy** `GET https://image.pollinations.ai/prompt/<url-encoded prompt>?width=&height=&seed=&model=&nologo=` still answers without any key. Response `200`, `content-type: image/jpeg`, headers `x-auth-status: unauthenticated`, `x-model-used: sana`, `x-usage-completion-image-tokens: 1`, `cache-control: public, max-age=31536000, immutable`. An identical URL is served from cache (`x-cache: HIT`, 0.8 s).
- `GET https://image.pollinations.ai/models` returns `["sana"]` (verified). So anonymous use is one model: `sana` (alias of `lykon/dreamshaper-8-lcm`, "dreamshaper").
- **New API** `GET https://gen.pollinations.ai/image/<prompt>?model=...` returned `401 UNAUTHORIZED`: "A valid API key is required. Get one at https://enter.pollinations.ai/keys" (verified). Docs (APIDOCS.md in the pollinations repo, section Authentication): `sk_` secret keys go in `Authorization: Bearer`; browser/CLI apps register an App Key (`pk_` with redirect URIs) and use OAuth 2.1 PKCE or the device flow (RFC 8628) so the user authorises a scoped `sk_`. Raw `pk_` keys are "legacy only ... do not mint new ones". The model catalogue endpoints (`/image/models`, `/v1/models`, `/models`) need no key.
- The legacy anonymous endpoint is not described in the current APIDOCS.md at all; only its error text (below) tells us it is intentional free tier. Treat it as unsupported and subject to removal.

### Rate limit and watermark (verified)

A second anonymous request inside the window returned `402`, `{"error":{"code":"FREE_LIMIT","message":"Free limit reached: 1 image every 45 seconds per IP. Retry after 10s, or get unlimited images with a pollen key at https://enter.pollinations.ai/?ref=classic"}}` with a `retry-after` header (seconds). So: 1 image per 45 s per IP, honour `retry-after`. Third-party blogs quote 5 s or 15 s; the live server says 45 s and is the number to use.

Even with `nologo=true` the anonymous image carried a "pollinations.ai" logo in the bottom-right corner (verified by viewing a 512x512 output). Plan on the watermark.

### Models (verified, `GET https://gen.pollinations.ai/image/models`)

About 70 image entries (plus video); each has `name`, `aliases`, `paid_only`, `per_user_rpm`, `pricing` (pollen), `health`. Not `paid_only` (still needs a key on `gen.`): `z-image-turbo` (the default, 60 rpm), `flux.2-klein-4b` (60 rpm), `flux.1-schnell` (alias `flux`, 60 rpm), `dreamshaper-8-lcm` (`sana`, 300 rpm), `mai-image-2.6(-flash)` (12 rpm), `gpt-image-1-mini`, `gpt-image-1.5`, `gpt-image-2`, `flux.1.1-pro`, `flux.1-kontext-pro`. The rest are `paid_only`. Anonymous legacy use only gets `sana`.

### Parameters (docs, `gen.` image GET)

`model`, `width`, `height` (exact pixels; some models need multiples of 16/32), `seed` (only some models; `-1` random), `safe` (comma list: privacy, secrets, sexual, violence, shield, true, nsfw; default off), `quality` (low/medium/high/hd, OpenAI-style models), `image` (reference URLs for edit), `transparent` (gpt-image only), `resolution`. Also OpenAI-compatible `POST /v1/images/generations` (`response_format`, `quality`, `n`, `size`). Legacy also accepts `nologo`, `enhance`, `private`; their current effect is unverified (`nologo` did not remove the logo anonymously). Output: `image/jpeg`, `image/png` or `image/svg+xml` bytes; no JSON wrapper.

### Latency (verified)

Fresh `sana`: 256x256 jpeg 10.5 KB in 8.1 s; 512x512 jpeg 25.3 KB in 10.6 s. 1024x1024 not tested (rate limit).

### Referrer / token / terms

- No referrer or token is needed on the legacy endpoint (verified). A fake referrer must not be used.
- Terms of use: could not be retrieved (pollinations.ai/terms and enter.pollinations.ai are single-page apps that returned only a title; no terms file found in the repo). Commercial use, attribution and content rules are therefore **unverified**. The server offers a `safe` filter that is off by default. Per the coordinator's rule, no further digging; the widget should link the user to pollinations.ai and not claim commercial rights.
- Registered users get higher limits and no watermark (third-party sources, unverified).

## 2. AI Horde (aihorde.net)

Community-run, volunteer GPUs, anonymous API key `0000000000`. Base `https://aihorde.net/api/v2`.

### Flow (verified end to end)

1. `POST /generate/async`, headers `apikey: 0000000000`, `Client-Agent: <name>:<version>:<contact>`, `Content-Type: application/json`. Body used: `{"prompt":..., "params":{"width":384,"height":384,"steps":20,"n":1,"sampler_name":"k_euler_a","cfg_scale":7}, "models":["Deliberate"], "nsfw":false, "r2":true, "slow_workers":true}`. Reply `{"id":"<uuid>","kudos":5.0}` (kudos = estimated cost).
2. Poll `GET /generate/check/{id}` (light, no images). Fields: `finished, processing, restarted, waiting, done, faulted, wait_time` (seconds, estimate), `queue_position`, `kudos`, `is_possible`, `eligible_workers`, `eligible_worker_threads`, `might_stall`. Observed: processing, wait_time 4, then 0, done after ~17 s from submit. No polling interval was found in the sources I could read; poll every 3 to 5 s to be polite (our choice, not a documented figure).
3. `GET /generate/status/{id}` once `done` (or `finished >= 1`): the same fields plus `generations: [{img, seed, id, censored, worker_id, worker_name, model, state, gen_metadata}]`. `img` was `https://<hash>.r2.cloudflarestorage.com/stable-horde/0` (R2 URL, `r2: true` is the default); with `r2: false` it is base64 webp inline. Download returned `200 image/webp`, 384x384, 41 KB (verified). R2 links are short-lived (docs: about 30 minutes; unverified), so save the bytes right away.
4. Cancel: `DELETE /generate/status/{id}` (same headers). It returns the status object. In one test the job was already `processing`, and a status call two seconds later still showed `processing`, so cancelling an in-flight job may not stop it at once (final state not confirmed).

### Models (verified)

`GET /status/models?type=image&min_count=1` returned 159 models, each `{name, count (workers), queued, jobs, eta (s), performance, type}`. Most worker-backed that day: ICBINP, stable_diffusion, Anything Diffusion, Deliberate, Dreamshaper, Counterfeit, URPM (4 to 7 workers each). Several are NSFW-focused (WAI-NSFW-illustrious-SDXL, Grapefruit Hentai); the widget must filter or default to a safe, named list and send `nsfw: false`. `GET /status/heartbeat` gives `{"message":"OK","version":"5.1.14","queue":0,...}`; `GET /status/performance` gives queue and worker totals (661 queued requests, 15 image workers when tested).

### Limits for anonymous users

- Verified: a 1024x1024, 50-step request was refused before queuing: `{"message":"Due to heavy demand, for requests over 586x586 or over the applicable first-order-equivalent sampler work budget the client needs to already have the required kudos. This request requires 31.59 kudos to fulfil.","rc":"KudosUpfront"}`. So anonymous users should stay at or below 576x576 (and moderate steps); 384x384, 20 steps cost 5 kudos estimated and ran with no kudos balance. `dry_run: true` returns the cost without queuing (used for the probe).
- `allow_downgrade: true` makes the server shrink steps and size so no kudos are needed (docs, swagger).
- Schema (swagger): `width`/`height` 64 to 3072, `steps` 1 to 500, `n` 1 to 20, `cfg_scale` 0 to 100, `seed` string, `post_processing`, `loras`, `source_image` (base64 webp for img2img). The anonymous account record (`GET /find_user`) shows `concurrency: 500`; real limits are not published, so assume 1 request at a time and `n: 1`.
- Anonymous users get the lowest queue priority and may be restricted at high load (Horde README, docs).
- `shared`: the swagger says "For anonymous users, this is always True" (images shared with LAION for dataset improvement). Tell the user.

### Client-Agent and terms

- Header `Client-Agent: <name>:<version>:<contact>` (name, version, and a URL or email for the author). Use `KDE-AI-Chat:<version>:<repo url>`. The tests here used `kdeaichat-research:0.1:anonymous`; the widget should use the proper form above.
- Terms of service and privacy policy are at `/terms` and `/privacy` on aihorde.net (SPA pages that did not render for the fetcher), so the content rules are **unverified** by me. Known from the README: kudos cannot be bought or sold; anonymous use is allowed. The Horde runs a prompt censor/filter (`replacement_filter`, `censor_nsfw`, `censored` flag in the result); a result can come back `censored: true` or a worker may reject a prompt. Handle both without retry loops.
- Because volunteers' machines process the prompt, the prompt and image are visible to the worker and to the Horde; see the privacy notes below.

## 3. Chat models that return images (direct mode)

None of this needs a free service; the user's own provider key is used and the cost is the model's.

### OpenRouter chat completions

- Image-output chat models are in the normal `GET /api/v1/models` list with `architecture.output_modalities: ["image","text"]` (verified, 12 models: `google/gemini-3.1-flash-image`, `google/gemini-3-pro-image`, `google/gemini-2.5-flash-image`, `openai/gpt-5-image`, `openai/gpt-5-image-mini`, `openai/gpt-5.4-image-2`, `openrouter/auto`, and more). The widget can detect them from this field.
- Request needs `"modalities": ["image","text"]` (docs; the API reference lists `modalities` with "text" and "image", and `image_config` e.g. `{"aspect_ratio":"16:9","quality":"high"}`).
- Response shape (**unverified**: the chat-style image page was not retrievable in the current docs, and no paid request was made): non-stream `choices[0].message.images = [{"type":"image_url","image_url":{"url":"data:image/png;base64,..."}}]` next to the normal `content` string; streaming puts the same array on `choices[0].delta.images` in one chunk (usually near the end, not split into pieces). Parse defensively: accept an `images` array on both `message` and `delta`, and also `url` being an `https` URL.
- Separate dedicated image API (docs, verified in docs only): `POST /api/v1/images` with `{model, prompt, aspect_ratio, quality, n}` returns `{"created":..., "data":[{"b64_json":"...","media_type":"image/png"}], "usage":{...}}`; `stream: true` sends SSE events `image_generation.partial_image` (`partial_image_index`, `b64_json`), `image_generation.completed` (`b64_json`, `media_type`, `created`, `usage`), `error`, then `[DONE]`. Models from `GET /api/v1/images/models`. One reported generation took 94 s, so use a long timeout.
- Server tool `{"type":"openrouter:image_generation"}` in `tools` lets any text model call image generation; the tool result is `{"status":"ok","imageUrl":"https://..."}` returned to the model, which can then write a Markdown link (beta).

### Gemini (Google AI)

- OpenAI-compatible `POST .../v1beta/openai/images/generations` (docs): models `gemini-2.5-flash-image`, `gemini-3-pro-image-preview`; params `prompt, model, n, size, response_format`; response `data[].b64_json` (use `"response_format":"b64_json"`); extras via `extra_body`: `aspect_ratio`, `generation_config` (`{"responseModalities":["IMAGE"],"candidateCount":2}`), `safety_settings`, `tools`.
- The compatibility page does not document image output inside `chat/completions`; native Gemini returns `candidates[].content.parts[].inlineData {mimeType, data(base64)}`. Inline images in the OpenAI-compat chat path are **unverified**.

### OpenAI

- Images API: `POST /v1/images/generations` returns `data[0].b64_json` (output defaults to PNG; jpeg/webp selectable); streaming events `image_generation.partial_image` with `partial_image_index`, `b64_json` (docs).
- Responses API with the `image_generation` tool: `response.output` has an item `type:"image_generation_call"` with `id, status, revised_prompt, result` (base64). Streaming: `response.image_generation_call.partial_image` events carry `partial_image_index` and `partial_image_b64` (`partial_images` 0 to 3); final image in `response.completed`.
- Chat Completions returning images: the guide does not describe it (no image output there). Plain OpenAI-compatible vendors (NIM, Groq, Mistral, ...) return text only.

### Markdown image links in plain text replies

Models often answer `![alt](https://...)`. This is just text in `content`. Rendering it makes the widget fetch a remote URL chosen by the model (a tracking and data-exfiltration vector, as the URL can carry chat text in the query). If supported: only `https`, show a placeholder and load on user click or a setting, no cookies/referrer, size cap, content-type check, and run the URL through `Security.js`. Also accept `data:image/(png|jpeg|webp);base64,` links from the shapes above, with a size cap.

## 4. Recommendations for the widget

- **Default free service: AI Horde.** It is the only one that is documented, keyless, async and non-legacy. Pollinations works anonymously today only through an undocumented legacy URL with a 45 s per IP limit, one model and a watermark; offer it as an optional second choice (or hide it), and if the user has a Pollinations key use `gen.pollinations.ai` with `z-image-turbo` (the documented default).
- Provider order: (1) the chat model's own image output if the selected model lists `image` output; (2) the user's Pollinations key if set; (3) Horde anonymous.
- **Horde defaults:** 512x512 (safe under the 586x586 anonymous cap; 384x384 for a faster option), steps 20 to 25, `n: 1`, `sampler_name: k_euler_a`, `cfg_scale: 7`, `nsfw: false`, `r2: true`, `slow_workers: true`, `shared` ignored. Model default `Deliberate` or `stable_diffusion`; build the picker from `GET /status/models?type=image`, sorted by `count`, hide names the user should not see by a safe-list or a "show all" toggle; show `count` and `eta`. Never hardcode model ids; fall back to `stable_diffusion` only if the list call fails. If the server says `KudosUpfront`, retry once with `allow_downgrade: true` or a smaller size, not a loop.
- **Pollinations defaults (legacy):** 512x512, `model=sana`, a fresh `seed`, one request per 45 s: disable the button until the `retry-after`/45 s window passes and show a countdown.
- **Queue progress for Horde:** poll `/generate/check/{id}` every 3 to 5 s (back off to 10 s after a minute), show `queue_position` ("position 3"), `wait_time` as "about N s left", and `processing/waiting` counts; show "no workers for this model" when `is_possible` is false; give up and offer cancel at about 3 minutes of wait; on `faulted` show an error. Cancel with `DELETE /generate/status/{id}` on close or Stop button, and treat it as best effort. Run all polling in QML with `XMLHttpRequest`; the image download goes through the helper (or XHR as blob) and must be checked for content-type `image/webp|png|jpeg`.
- **What to save:** in the chat's folder `~/.local/share/kdeaichat/chats/applet-<plasmoid.id>/`, add `images/<chatId>/<messageId>-<n>.<ext>` (ext from content-type: webp, png, jpg), written atomically by the helper (stdlib, `_safe_path`, mode 0600, folder 0700 like the rest). Store in the chat message only a relative path plus small metadata: `{service, model, prompt, width, height, seed, created}`, never the signed R2 URL or any key. Delete the files when the chat or message is deleted (the helper already owns deletion); include them in the chat folder size accounting. Decode base64 data URLs in the helper, not in QML, and cap at about 10 MB per image. Show with `Image { source: "file://..." }`.
- **Privacy text to show before first use and in settings:** "The prompt is sent to <service>. Anyone running the service, and for AI Horde the volunteer worker who generates it, can see the prompt and the image. Do not include personal data or secrets. AI Horde anonymous requests may be shared for dataset research. Pollinations anonymous images carry a watermark." Add "Chat history is not sent to the image service, only the prompt text you approve". Make generation an explicit user action (or confirmed tool call), never silent from a model's tool call.
- Content rules: send `nsfw: false`, keep `censor_nsfw` default, treat `censored: true` as a normal outcome, and link each service's terms from the settings page.
- Add any new helper or QML file to the manifest check and to `tests/test_no_qml_import_in_js_files.py` `WATCHED_FILES` when a JS backend module is added (e.g. `backends/HordeBackend.js`).

## Could not verify

- Pollinations terms of use (commercial use, attribution, content rules): pages are SPAs; no text obtained.
- AI Horde terms and privacy policy text, R2 URL lifetime, and the exact anonymous concurrency/priority numbers (only the 586x586 kudos-upfront rule and `concurrency: 500` on the account record were seen).
- Whether cancel stops an in-flight Horde job.
- OpenRouter `message.images` / `delta.images` JSON on chat completions (stated from the API reference's `modalities`/`image_config` fields and the earlier documented shape, not captured live), and Gemini inline images via the OpenAI chat path. No paid request was made.
- Pollinations `enhance`, `nologo`, `private` on the legacy endpoint, and 1024x1024 anonymous latency.

## Test log (for transparency)

Pollinations: one cached hit, two successful anonymous generations (256 and 512 px), one 401 on `gen.`, and four requests inside the 45 s window that were correctly refused with 402 FREE_LIMIT (this was a mistake in pacing, made before the "few and slow" rule arrived; nothing was retried or worked around, and testing of this service stopped there). AI Horde: two real jobs (one cancelled), plus three dry-run or refused probes, all with the documented anonymous key; testing stopped there.
