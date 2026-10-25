.pragma library

// Live checks of a provider: is the API key accepted, which models can be
// chatted with, and does the chosen model still answer.
//
// Plain JavaScript (no QML imports) so it runs under node in the tests; every
// network call takes an optional `xhrFactory` so tests can fake the server.
// A key is only ever sent in a request header and is removed from any text
// the provider sends back before that text is returned.
//
// Some providers answer GET /models with 200 for any key (NVIDIA NIM does), so
// the key is also tried on a tiny chat request (max_tokens 1) to the chosen
// model. That one request tells apart a rejected key (401/403) from a model
// that is gone (404/410): the key is fine in the second case.
//
// Model variants (reasoning / thinking levels, see Variants.js) are read from
// the same /models answer, so they cost no extra request: listModels returns
// them with the list (and so they are cached with it, per provider, in the
// settings session cache of config/ProviderChecker.qml). Only what the provider
// reports is offered.

var TIMEOUT_LIST = 10000;
var TIMEOUT_CHAT = 20000;

// ── Model lists ──────────────────────────────────────────────────────────

// [{id, raw}] from the shapes of /models responses.
function parseModelItems(responseObj) {
    var items = Array.isArray(responseObj) ? responseObj
        : (responseObj && Array.isArray(responseObj.data)) ? responseObj.data
        : (responseObj && Array.isArray(responseObj.models)) ? responseObj.models : [];
    var out = [];
    var seen = {};
    for (var i = 0; i < items.length; i++) {
        var raw = typeof items[i] === "string" ? {"id": items[i]} : (items[i] || {});
        var id = raw.id || raw.name;
        if (!id) continue;
        id = String(id).replace(/^models\//, "");
        if (seen[id]) continue;
        seen[id] = true;
        out.push({"id": id, "raw": raw});
    }
    return out;
}

// ── Variants ─────────────────────────────────────────────────────────────

// One sensible token budget for "thinking on" on older Claude models, which
// report thinking support but no levels. The API minimum is 1024 and it must
// stay below max_tokens (DirectBackend.js raises max_tokens when needed).
var THINKING_BUDGET_TOKENS = 8000;

function _variant(id, send, label) {
    return {"id": id, "label": label || id.charAt(0).toUpperCase() + id.substring(1), "send": send};
}

function _supported(entry) {
    return !!entry && typeof entry === "object" && entry.supported === true;
}

// The variants a /models entry reports itself, [] when it reports none:
//   Anthropic  capabilities.effort: the levels with supported:true, sent as
//              adaptive thinking + output_config.effort; capabilities.thinking
//              without levels: "on" (older models: a token budget); and, where
//              types.disabled is supported, "off"
//   OpenRouter reasoning.supported_efforts, sent as reasoning: {effort}
// Any other list (OpenAI, NVIDIA NIM, Groq, Mistral, ...) carries neither, so
// its models have no variants. Level names and their order are the provider's.
function variantsFromModel(raw) {
    var caps = raw && raw.capabilities;
    var thinking = caps && caps.thinking;
    var effort = caps && caps.effort;
    var types = (thinking && thinking.types) || {};
    var out = [];
    if (_supported(effort)) {
        for (var level in effort) {
            if (level !== "supported" && _supported(effort[level]))
                out.push(_variant(level, {"thinking": {"type": "adaptive"}, "output_config": {"effort": level}}));
        }
    } else if (_supported(thinking)) {
        if (_supported(types.enabled))
            out.push(_variant("on", {"thinking": {"type": "enabled", "budget_tokens": THINKING_BUDGET_TOKENS}}, "Thinking on"));
        else if (_supported(types.adaptive))
            out.push(_variant("on", {"thinking": {"type": "adaptive"}}, "Thinking on"));
    }
    if (out.length > 0 && _supported(types.disabled))
        out.push(_variant("off", {"thinking": {"type": "disabled"}}, "Thinking off"));
    var efforts = out.length === 0 && raw && raw.reasoning ? raw.reasoning.supported_efforts : null;
    for (var i = 0; Array.isArray(efforts) && i < efforts.length; i++) {
        var id = String(efforts[i]);
        if (id !== "" && !out.some(function(v) { return v.id === id; }))
            out.push(_variant(id, {"reasoning": {"effort": id}}));
    }
    return out;
}

// {modelId: [variants]} for the models of a list that have any.
function variantMap(items) {
    var map = {};
    for (var i = 0; i < items.length; i++) {
        var variants = variantsFromModel(items[i].raw);
        if (variants.length > 0)
            map[items[i].id] = variants;
    }
    return map;
}

// Words in a model id that mean it does not do text chat.
var NON_CHAT_WORDS = /(^|[^a-z0-9])(embed|embedding|embeddings|embedqa|embed-qa|rerank|reranker|reranking|retriever|nemoretriever|guard|guardian|nemoguard|safety|moderation|reward|whisper|tts|stt|asr|speech|audio|transcribe|transcription|diffusion|sdxl|dall-e|dalle|imagen|image|flux|clip|nvclip|deplot|parse|calibration|detector|gliner|pii|bge|e5|veo|sora|realtime)([^a-z0-9]|$)/i;
var NON_CHAT_PARTS = /(embed|rerank|safety|moderation|whisper|guard|reward|diffusion|nvclip|text-to-|-tts|tts-|-asr|parakeet|canary|stable-diffusion)/i;

function _textOf(value) {
    return typeof value === "string" ? value.toLowerCase() : "";
}

// True if the entry looks like a model for text chat. Uses fields the
// provider sends (type, capabilities, modalities, ...) first, then the id.
function isChatModel(item) {
    var raw = item.raw || {};
    var type = _textOf(raw.type) || _textOf(raw.kind) || _textOf(raw.task) || _textOf(raw.pipeline_tag);
    if (type && type !== "model" && /embed|rerank|image|audio|speech|moderation|tts|stt|transcri|vision-only|diffusion|video|classif/.test(type))
        return false;
    var caps = raw.capabilities;
    if (caps && typeof caps === "object" && !Array.isArray(caps)) {
        if (caps.completion_chat === false || caps.chat === false) return false;
    }
    if (raw.supports_chat === false) return false;
    var arch = raw.architecture;
    if (arch && Array.isArray(arch.output_modalities) && arch.output_modalities.indexOf("text") < 0)
        return false;
    if (Array.isArray(raw.supportedGenerationMethods) && raw.supportedGenerationMethods.indexOf("generateContent") < 0)
        return false;
    var id = item.id.toLowerCase();
    // Whisper, TTS and the like also match NON_CHAT_PARTS; word matches catch the rest.
    var bare = id.replace(/^.*\//, "");
    if (NON_CHAT_WORDS.test(bare) || NON_CHAT_PARTS.test(bare))
        return false;
    // text-davinci / babbage style completion models and OpenAI "instruct" completions.
    if (/^(davinci|babbage|text-(davinci|curie|babbage|ada))/.test(bare) || /gpt-3\.5-turbo-instruct/.test(bare))
        return false;
    return true;
}

// {chat: [ids usable for chat], all: [every id], hidden: count} from /models items.
function splitModels(items) {
    var chat = [];
    var all = [];
    for (var i = 0; i < items.length; i++) {
        all.push(items[i].id);
        if (isChatModel(items[i])) chat.push(items[i].id);
    }
    return {"chat": chat, "all": all, "hidden": all.length - chat.length};
}

// ── Requests ────────────────────────────────────────────────────────────

function _base(cfg) {
    return String(cfg.baseUrl || "").replace(/\/+$/, "").replace(/\/chat\/completions$/, "");
}

function _headers(cfg, apiKey, json) {
    var headers = {};
    if (cfg.type === "anthropic") {
        headers["x-api-key"] = apiKey || "";
        headers["anthropic-version"] = "2023-06-01";
    } else if (apiKey) {
        headers["Authorization"] = "Bearer " + apiKey;
    }
    if (json) headers["Content-Type"] = "application/json";
    for (var k in (cfg.headers || {}))
        if (cfg.headers[k]) headers[k] = cfg.headers[k];
    return headers;
}

function _redact(text, apiKey) {
    var out = String(text === undefined || text === null ? "" : text);
    if (apiKey && apiKey.length >= 4) out = out.split(apiKey).join("[key]");
    return out;
}

// One request. cb({status, text, error}) with error "timeout" | "network" | "send" | "".
function _send(factory, method, url, headers, body, timeout, cb) {
    var finished = false;
    function done(result) {
        if (finished) return;
        finished = true;
        cb(result);
    }
    var xhr;
    var started = Date.now();
    if (!/^https?:\/\/[^\s\/]/i.test(url)) {
        done({"status": 0, "text": "", "error": "url"});
        return;
    }
    try {
        xhr = factory ? factory() : new XMLHttpRequest();
        xhr.open(method, url, true);
        xhr.timeout = timeout;
        for (var h in headers) xhr.setRequestHeader(h, headers[h]);
    } catch (e) {
        done({"status": 0, "text": "", "error": "send"});
        return;
    }
    xhr.onreadystatechange = function() {
        if (xhr.readyState !== 4) return;
        if (xhr.status === 0) {
            // No response: a timeout if it took as long as the limit, else the network.
            done({"status": 0, "text": "", "error": Date.now() - started >= timeout * 0.9 ? "timeout" : "network"});
            return;
        }
        done({"status": xhr.status, "text": String(xhr.responseText || ""), "error": ""});
    };
    xhr.ontimeout = function() { done({"status": 0, "text": "", "error": "timeout"}); };
    xhr.onerror = function() { done({"status": 0, "text": "", "error": "network"}); };
    try {
        xhr.send(body === null || body === undefined ? undefined : body);
    } catch (e) {
        done({"status": 0, "text": "", "error": "send"});
    }
}

// A short human reason from an error response body, without the key and
// without account identifiers some providers put in "not found" messages.
function reasonFrom(text, apiKey) {
    var message = "";
    try {
        var obj = JSON.parse(text);
        var err = obj && obj.error;
        message = (err && typeof err === "object" ? (err.message || err.detail || err.code) : err)
            || obj.detail || obj.message || obj.title || "";
        if (typeof message !== "string") message = JSON.stringify(message);
    } catch (e) {
        message = String(text || "").replace(/<[^>]*>/g, " ");
    }
    message = _redact(message, apiKey).replace(/\s+/g, " ").trim();
    if (/not found for account/i.test(message)) message = "Not found for this account";
    return message.length > 160 ? message.substring(0, 157) + "..." : message;
}

var KEY_WORDS = /api[ _-]?key|unauthori[sz]ed|credential|authenticat|invalid.*token|permission denied/i;
var MODEL_WORDS = /(model|function).*(not found|does not exist|not exist|invalid|unknown|unsupported|not supported|unavailable)|(unknown|invalid|no such) model|end of life|decommission|deprecat|retired|no longer available/i;

// 401/403, or the 400 some providers (Gemini) use for a bad key.
function _isKeyRejection(status, text) {
    if (status === 401 || status === 403) return true;
    return status === 400 && KEY_WORDS.test(String(text || "")) && !MODEL_WORDS.test(String(text || ""));
}

function _isModelGone(status, text) {
    if (status === 404 || status === 410) return true;
    return status === 400 && MODEL_WORDS.test(String(text || ""));
}

// Lists a provider's models. cb({ok, status, error, items, chat, all, hidden, variants}):
// `error` is "" | "rejected" | "timeout" | "network" | "http" | "parse" | "send" | "url".
function listModels(cfg, apiKey, cb, opts) {
    var o = opts || {};
    var url = _base(cfg) + "/models";
    _send(o.xhrFactory, "GET", url, _headers(cfg, apiKey, false), null, o.timeout || TIMEOUT_LIST, function(r) {
        var result = {"ok": false, "status": r.status, "error": r.error, "items": [], "chat": [], "all": [], "hidden": 0, "variants": {}};
        if (r.error) { cb(result); return; }
        if (r.status >= 200 && r.status < 300) {
            try {
                if (r.text.length > 2000000) throw new Error("too large");
                var items = parseModelItems(JSON.parse(r.text));
                var split = splitModels(items);
                result.ok = true;
                result.items = items;
                result.chat = split.chat;
                result.all = split.all;
                result.hidden = split.hidden;
                result.variants = variantMap(items);
            } catch (e) {
                result.error = "parse";
            }
        } else {
            result.error = _isKeyRejection(r.status, r.text) ? "rejected" : "http";
            result.reason = reasonFrom(r.text, apiKey);
        }
        cb(result);
    });
}

// A one-token chat request. cb({status, error, reason, kind}) with kind:
//   "ok" (2xx) | "key" (key rejected) | "model" (model gone) |
//   "limit" (429/402: the key and model were accepted) | "other" | "unreachable"
function probeChat(cfg, apiKey, model, cb, opts) {
    var o = opts || {};
    var anthropic = cfg.type === "anthropic";
    var url = _base(cfg) + (anthropic ? "/messages" : "/chat/completions");
    function request(tokenField) {
        var body = {"model": model, "messages": [{"role": "user", "content": "hi"}]};
        body[tokenField] = 1;
        _send(o.xhrFactory, "POST", url, _headers(cfg, apiKey, true), JSON.stringify(body), o.timeout || TIMEOUT_CHAT, function(r) {
            if (r.error) { cb({"status": 0, "error": r.error, "kind": "unreachable", "reason": ""}); return; }
            // Newer OpenAI models want max_completion_tokens instead of max_tokens.
            if (!anthropic && tokenField === "max_tokens" && r.status === 400 && /max_completion_tokens/.test(r.text)) {
                request("max_completion_tokens");
                return;
            }
            var kind = "other";
            if (r.status >= 200 && r.status < 300) kind = "ok";
            else if (_isKeyRejection(r.status, r.text)) kind = "key";
            else if (_isModelGone(r.status, r.text)) kind = "model";
            else if (r.status === 429 || r.status === 402) kind = "limit";
            cb({"status": r.status, "error": "", "kind": kind, "reason": kind === "ok" ? "" : reasonFrom(r.text, apiKey)});
        });
    }
    request("max_tokens");
}

// Checks a key (and the model) before it is saved. opts: {cfg, apiKey, model,
// local, xhrFactory, knownList (an earlier listModels result)}. cb(result) with
//   state   "ok" | "key_rejected" | "model_unavailable" | "unverified" | "skipped"
//   status  the HTTP status that decided it (0 when there was none)
//   reason  the provider's own words for a model problem
//   modelChecked  true when the chosen model itself answered or was refused
//   models  the list result when /models answered
//   warning "limit" when the provider answered 429/402 (key and model accepted)
function checkProvider(opts, cb) {
    var cfg = opts.cfg;
    var apiKey = opts.apiKey || "";
    if (opts.local || !apiKey) {
        cb({"state": "skipped", "status": 0});
        return;
    }
    var common = {"xhrFactory": opts.xhrFactory};
    // A list fetched a moment ago saves a request when the model is chosen: the
    // chat request below decides about the key then.
    var withList = opts.knownList && String(opts.model || "").trim() !== ""
        ? function(next) { next(opts.knownList); }
        : function(next) { listModels(cfg, apiKey, next, common); };
    withList(function(list) {
        if (list.error === "rejected") {
            cb({"state": "key_rejected", "status": list.status});
            return;
        }
        if (list.error === "timeout" || list.error === "network" || list.error === "send" || list.error === "url") {
            cb({"state": "unverified", "status": 0, "error": list.error});
            return;
        }
        var model = String(opts.model || "").trim();
        var chosen = model !== "";
        if (!chosen && list.ok && list.chat.length > 0) model = list.chat[0];
        if (!model) {
            // Nothing to try the key on: only the model list answered.
            cb(list.ok ? {"state": "ok", "status": list.status, "modelChecked": false, "models": list}
                       : {"state": "unverified", "status": list.status, "error": "http"});
            return;
        }
        probeChat(cfg, apiKey, model, function(p) {
            var base = {"status": p.status, "reason": p.reason, "models": list.ok ? list : null, "model": model};
            if (p.kind === "key") base.state = "key_rejected";
            else if (p.kind === "unreachable") { base.state = "unverified"; base.error = p.error; }
            else if (p.kind === "ok") { base.state = "ok"; base.modelChecked = chosen; }
            else if (p.kind === "limit") { base.state = "ok"; base.modelChecked = false; base.warning = "limit"; }
            else if (p.kind === "model") {
                // The key is fine (auth is checked before the model). A model the
                // user did not choose is only a probe, so it is not reported.
                base.state = chosen ? "model_unavailable" : "ok";
                base.modelChecked = chosen;
            } else { base.state = "unverified"; base.error = "http"; }
            cb(base);
        }, common);
    });
}

// ── Models found dead during this session ───────────────────────────────

var _dead = {};

function markDead(providerId, model, reason) {
    _dead[providerId + "\n" + model] = reason || "not available";
}

function clearDead(providerId, model) {
    delete _dead[providerId + "\n" + model];
}

// "" when the model has not been found dead.
function deadReason(providerId, model) {
    return _dead[providerId + "\n" + model] || "";
}
