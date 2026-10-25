.pragma library

// Pollinations.ai images, two ways:
//   "key"     gen.pollinations.ai, the documented API, with the user's own key (Authorization: Bearer).
//   "legacy"  image.pollinations.ai, the older free service. It needs no key but is not documented any
//             more and may stop working: one image every 45 seconds per computer, one model, and a
//             Pollinations logo on the picture. The widget keeps the 45 s gap itself (a Pacer with a
//             countdown) and honours 402/429 and Retry-After. It never retries by itself.
//
// Self-contained (no QML globals, no imports). The caller passes in options: http (ImageHttp.js),
// xhrFactory, setTimer(fn, ms) -> handle, clearTimer(handle), toBase64(bytes), now() (optional), onEvent(event).
// Events:
//   {type: "progress", phase: "countdown", seconds}   waiting for the 45 s gap; one event per second
//   {type: "progress", phase: "working"}               the request is out
//   {type: "images", items: [{kind: "data", b64, mime, seed, model, width, height}]}
//   {type: "error", code, message, retryAfter?}
//   {type: "done"}
// Error messages are plain English that starts with "Pollinations" (chat/ErrorText.js shows them as they are).

var LEGACY_BASE = "https://image.pollinations.ai/prompt/";
var KEY_BASE = "https://gen.pollinations.ai/image/";
var MODELS_URL = "https://gen.pollinations.ai/image/models";
var SITE_URL = "https://pollinations.ai";
var KEYS_URL = "https://enter.pollinations.ai";
var FREE_GAP_MS = 45000;
var MAX_PROMPT_CHARS = 1000;
var LEGACY_MODEL = "sana";
var DEFAULT_MODEL = "z-image-turbo";
var DEFAULT_SIZE = 512;
var MAX_SIZE = 1024;

// Width and height in steps of 64 (256 to 1024) and a seed (-1: pick one for each image).
function clampOptions(options) {
    function size(value) {
        var n = Math.round(Number(value));
        if (!isFinite(n)) return DEFAULT_SIZE;
        return Math.max(256, Math.min(MAX_SIZE, Math.round(n / 64) * 64));
    }
    var o = options || {};
    var seed = o.seed === undefined || o.seed === null || o.seed === "" || Number(o.seed) < 0 || !isFinite(Number(o.seed)) ? -1
        : Math.min(2147483647, Math.round(Number(o.seed)));
    return {"width": size(o.width), "height": size(o.height), "seed": seed};
}

// {url, headers, params} for one image. options: {service: "key"|"legacy", prompt, model, apiKey, width, height, seed}
// (seed < 0 means "choose one": options.random is a number in [0, 1) for tests).
function buildRequest(options) {
    var p = clampOptions(options);
    var seed = p.seed >= 0 ? p.seed : Math.floor((options.random === undefined ? Math.random() : options.random) * 2147483647);
    var legacy = options.service === "legacy";
    var model = legacy ? LEGACY_MODEL : String(options.model || DEFAULT_MODEL);
    var query = "width=" + p.width + "&height=" + p.height + "&seed=" + seed + "&model=" + encodeURIComponent(model);
    var headers = {"Accept": "image/png,image/jpeg,image/webp"};
    if (!legacy) {
        query += "&safe=true";
        headers["Authorization"] = "Bearer " + String(options.apiKey || "");
    }
    return {"url": (legacy ? LEGACY_BASE : KEY_BASE) + encodeURIComponent(String(options.prompt || "")) + "?" + query,
            "headers": headers, "params": {"width": p.width, "height": p.height, "seed": seed, "model": model}};
}

// What to tell the user about a failed request: {code, message, retryAfter}. `retryAfter` in seconds (0: none given).
function describeError(status, text, retryAfter, service) {
    var detail = "";
    try {
        var obj = JSON.parse(text);
        var err = obj.error !== undefined ? obj.error : obj;
        detail = typeof err === "string" ? err : String((err && err.message) || obj.message || "");
    } catch (e) {
        detail = String(text || "").substring(0, 200).trim();
    }
    var wait = retryAfter > 0 ? retryAfter : 0;
    if (status === 0)
        return {"code": "unreachable", "message": "Pollinations can't be reached. Check your internet connection and try again."};
    if (status === 402 || status === 429) {
        if (service === "legacy" || /free limit/i.test(detail)) {
            var secs = wait > 0 ? wait : Math.round(FREE_GAP_MS / 1000);
            return {"code": "free_limit", "retryAfter": secs, "message": "Pollinations free limit: try again in " + secs + " s."};
        }
        return status === 402
            ? {"code": "credit", "message": "Pollinations says this key has no credit for this model. Pick a free model, or check your balance at pollinations.ai."}
            : {"code": "busy", "retryAfter": wait, "message": "Pollinations is limiting requests" + (wait > 0 ? ": try again in " + wait + " s." : ". Try again in a minute.")};
    }
    if (status === 401 || status === 403)
        return {"code": "key", "message": service === "legacy"
            ? "Pollinations no longer gives free images without a key. Add your own Pollinations key in Settings → Connection."
            : "Pollinations did not accept the key. Check it in Settings → Connection."};
    if (status === 404 || status === 410)
        return {"code": "gone", "message": "Pollinations does not answer at this address any more (the older free service may have stopped)."};
    if (status >= 500)
        return {"code": "server", "message": "Pollinations had a problem on its side. Try again in a moment."};
    return {"code": "http", "status": status, "message": "Pollinations answered HTTP " + status + (detail ? ": " + detail : ".")};
}

// --- Pacing the free service -----------------------------------------------------

// Remembers when the next free image may be asked for. state: {lastAt, blockedUntil} (ms since the epoch,
// 0 for "never"), kept by the caller between runs.
function createPacer(state, gapMs) {
    var s = Object.assign({"lastAt": 0, "blockedUntil": 0}, state || {});
    var gap = gapMs > 0 ? gapMs : FREE_GAP_MS;
    return {
        "waitMs": function(now) { return Math.max(0, s.lastAt + gap - now, s.blockedUntil - now); },
        "sent": function(now) { s.lastAt = now; },
        // The service said to wait `seconds` (Retry-After): nothing goes out before that.
        "limited": function(now, seconds) { s.blockedUntil = now + Math.max(seconds, 1) * 1000 + 1000; },
        "state": function() { return {"lastAt": s.lastAt, "blockedUntil": s.blockedUntil}; }
    };
}

// --- Models (keyed API) --------------------------------------------------------------

// The image models of gen.pollinations.ai/image/models: [{id, title, paid}], the free ones first.
// Video models and community uploads are left out. `id` is what the request takes (the name without its maker).
function parseModels(list) {
    var items = Array.isArray(list) ? list : (list && Array.isArray(list.models) ? list.models : []);
    var out = [];
    for (var i = 0; i < items.length; i++) {
        var m = items[i];
        if (!m || typeof m !== "object" || !m.name || /^community\//.test(m.name))
            continue;
        var outputs = Array.isArray(m.output_modalities) ? m.output_modalities : ["image"];
        if (outputs.indexOf("image") < 0 || outputs.indexOf("video") >= 0)
            continue;
        out.push({"id": String(m.name).split("/").pop(), "title": String(m.title || m.name), "paid": m.paid_only === true});
    }
    out.sort(function(a, b) { return (a.paid ? 1 : 0) - (b.paid ? 1 : 0); });
    return out;
}

// --- Running a request -------------------------------------------------------------------

// Makes one image. Returns {cancel()}. options: see the top, plus the fields of buildRequest and
// pacer (createPacer) for the legacy service.
function generate(options) {
    var http = options.http;
    var clock = options.now || function() { return Date.now(); };
    var legacy = options.service === "legacy";
    var request = buildRequest(options);
    var stopped = false;
    var timer = null;
    var pending = null;

    function emit(event) {
        if (!stopped)
            options.onEvent(event);
    }
    function fail(error) {
        emit(Object.assign({"type": "error"}, error));
        stopped = true;
    }
    function stop() {
        stopped = true;
        if (timer !== null)
            options.clearTimer(timer);
        timer = null;
        if (pending)
            pending.abort();
        pending = null;
    }
    function send() {
        if (options.pacer && legacy)
            options.pacer.sent(clock());
        emit({"type": "progress", "phase": "working"});
        pending = http.request({"xhrFactory": options.xhrFactory, "url": request.url, "headers": request.headers, "binary": true, "timeoutMs": 120000}, function(res) {
            pending = null;
            if (stopped)
                return;
            if (res.status < 200 || res.status >= 300) {
                var retry = http.retryAfterSeconds(res.header("retry-after"), clock());
                if (legacy && options.pacer && (res.status === 402 || res.status === 429))
                    options.pacer.limited(clock(), retry > 0 ? retry : Math.round(FREE_GAP_MS / 1000));
                fail(describeError(res.status, res.text, retry, options.service));
                return;
            }
            var bytes = http.bytesOf(res.buffer);
            if (!bytes || !http.looksLikeImage(bytes) || bytes.length > http.MAX_IMAGE_BYTES) {
                fail({"code": "not_image", "message": "Pollinations answered, but not with a picture. Try again."});
                return;
            }
            emit({"type": "images", "items": [Object.assign({"kind": "data", "b64": options.toBase64(bytes), "mime": res.header("content-type") || "image/jpeg"}, request.params)]});
            emit({"type": "done"});
            stopped = true;
        });
    }
    function countdown() {
        timer = null;
        if (stopped)
            return;
        var wait = options.pacer.waitMs(clock());
        if (wait <= 0) {
            send();
            return;
        }
        emit({"type": "progress", "phase": "countdown", "seconds": Math.ceil(wait / 1000)});
        timer = options.setTimer(countdown, Math.min(1000, wait));
    }

    if (String(options.prompt || "").length > MAX_PROMPT_CHARS) {
        fail({"code": "prompt_too_long", "message": "Pollinations takes prompts of up to " + MAX_PROMPT_CHARS + " characters. Make it shorter."});
    } else if (!legacy && !options.apiKey) {
        fail({"code": "key", "message": "Pollinations needs your key for this. Add it in Settings → Connection."});
    } else if (legacy && options.pacer) {
        countdown();
    } else {
        send();
    }
    return {"cancel": stop};
}
