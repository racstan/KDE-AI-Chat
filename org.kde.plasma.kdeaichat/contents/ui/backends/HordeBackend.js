.pragma library

// AI Horde (aihorde.net): a community-run service where volunteers' GPUs make images.
// Anonymous use needs no account (key 0000000000) but has the lowest queue priority and
// stricter size limits. Flow: submit a job, check it every few seconds (queue position and
// wait time), fetch the finished image, and cancel the job with DELETE if the user stops.
//
// Self-contained: no QML globals and no imports. The caller passes what it needs in options:
//   http        backends/ImageHttp.js (request, bytesOf, looksLikeImage, retryAfterSeconds, ...)
//   xhrFactory  returns a new XMLHttpRequest
//   setTimer(fn, ms) -> handle and clearTimer(handle)   (a QML Timer wrapper; tests use a fake clock)
//   toBase64(bytes)  ImageExtract.bytesToBase64
//   onEvent(event)
// Events:
//   {type: "submitted", id, kudos}
//   {type: "progress", phase: "queued"|"working", queuePosition, waitTime, waiting, processing, finished, total, possible}
//   {type: "images", items: [{kind: "data", b64, mime, seed, model}]}
//   {type: "error", code, message, status?, retryAfter?}      code: see describeError
//   {type: "done"}
// Error messages are plain English that starts with the service name (chat/ErrorText.js shows them as they are).

var BASE_URL = "https://aihorde.net/api/v2";
var TERMS_URL = "https://aihorde.net/terms";
var ANONYMOUS_KEY = "0000000000";
var REPO_URL = "https://github.com/racstan/KDE-AI-Chat";
// Anonymous requests over 586x586 need kudos up front; stay below with sizes in steps of 64.
var ANON_MAX_SIZE = 576;
var KEY_MAX_SIZE = 1024;
var DEFAULT_SIZE = 512;
var DEFAULT_STEPS = 22;
var MAX_STEPS = 50;
var ANON_MAX_STEPS = 30;
var POLL_MS = 4000;          // between checks (3 to 5 s), then slower once a job has waited a minute
var SLOW_POLL_MS = 10000;
var GIVE_UP_MS = 180000;
var PREFERRED_MODELS = ["Deliberate", "stable_diffusion", "Dreamshaper", "ICBINP", "Anything Diffusion"];
var FALLBACK_MODEL = "stable_diffusion";
// Models whose names say they are made for adult content are not offered (the request also sends nsfw: false).
var BLOCKED_NAMES = /nsfw|hentai|porn|xxx|erotic|lewd|\bsex|adult|nude|naked|bdsm|fetish|r34|rule34|ahegao|futa|yiff|hardcore|milf|pony|illustrious|grapefruit|uber realistic|babes|waifu/i;

// "KDE-AI-Chat:<version>:<website>" (metadata.json; the caller passes them), as AI Horde asks clients to name themselves.
function clientAgent(version, contact) {
    return "KDE-AI-Chat:" + String(version || "unknown") + ":" + String(contact || REPO_URL);
}

// The sizes, steps and count the service allows. Anonymous: at most 576 px, 30 steps and one image at a time
// (more would need kudos up front, which an anonymous user does not have).
function clampOptions(options, hasOwnKey) {
    var maxSize = hasOwnKey ? KEY_MAX_SIZE : ANON_MAX_SIZE;
    var o = options || {};
    function clamp(value, min, max, fallback, step) {
        var n = Math.round(Number(value));
        if (!isFinite(n)) return fallback;
        n = Math.max(min, Math.min(max, n));
        return step > 1 ? Math.max(min, Math.min(max, Math.round(n / step) * step)) : n;
    }
    var seed = o.seed === undefined || o.seed === null || o.seed === "" || Number(o.seed) < 0 ? -1 : clamp(o.seed, 0, 2147483647, -1);
    return {"width": clamp(o.width, 64, maxSize, DEFAULT_SIZE, 64), "height": clamp(o.height, 64, maxSize, DEFAULT_SIZE, 64),
            "steps": clamp(o.steps, 10, hasOwnKey ? MAX_STEPS : ANON_MAX_STEPS, DEFAULT_STEPS), "n": hasOwnKey ? clamp(o.n, 1, 4, 1) : 1, "seed": seed};
}

// {url, headers, body} of the request that starts a job. options: {prompt, model, apiKey, version, contact, seed, ...clampOptions}.
function buildSubmit(options) {
    var hasKey = !!options.apiKey && options.apiKey !== ANONYMOUS_KEY;
    var p = clampOptions(options, hasKey);
    var params = {"width": p.width, "height": p.height, "steps": p.steps, "n": p.n, "sampler_name": "k_euler_a", "cfg_scale": 7};
    if (p.seed >= 0)
        params.seed = String(p.seed);
    var body = {"prompt": String(options.prompt || ""), "params": params, "nsfw": false, "censor_nsfw": true, "r2": true, "slow_workers": true,
                "models": [options.model || FALLBACK_MODEL]};
    return {"url": BASE_URL + "/generate/async", "body": body, "params": p,
            "headers": {"apikey": options.apiKey || ANONYMOUS_KEY, "Client-Agent": clientAgent(options.version, options.contact), "Content-Type": "application/json"}};
}

function _detail(text) {
    try {
        var obj = JSON.parse(text);
        return {"message": String(obj.message || obj.error || ""), "rc": String(obj.rc || "")};
    } catch (e) {
        return {"message": String(text || "").substring(0, 200), "rc": ""};
    }
}

// {code, message, retryAfter} for a failed request (HTTP status 0: not reachable).
function describeError(status, text, retryAfter) {
    var d = _detail(text);
    var rc = d.rc.toLowerCase();
    var msg = d.message.toLowerCase();
    var wait = retryAfter > 0 ? retryAfter : 0;
    if (status === 0)
        return {"code": "unreachable", "message": "AI Horde can't be reached. Check your internet connection and try again."};
    if (rc === "kudosupfront" || /kudos/.test(msg))
        return {"code": "kudos", "message": "AI Horde needs kudos for this size. Pick a smaller picture or fewer steps in Settings → Connection, or add your own AI Horde key."};
    if (status === 401 || rc === "invalidapikey")
        return {"code": "key", "message": "AI Horde did not accept the API key. Check it in Settings → Connection."};
    if (status === 429 || rc === "toomanyrequests" || rc === "timedout")
        return {"code": "busy", "retryAfter": wait, "message": "AI Horde is limiting requests right now" + (wait > 0 ? ": try again in " + wait + " s." : ". Try again in a minute.")};
    if (status === 503 || status === 502 || status === 504 || rc === "maintenancemode")
        return {"code": "busy", "retryAfter": wait, "message": "AI Horde is busy or down for maintenance. Try again in a few minutes."};
    if (rc === "corruptprompt" || rc === "promptsafety" || /censor|safety|prohibited|not allowed/.test(msg))
        return {"code": "censored", "message": "AI Horde's safety filter blocked this prompt. Try different words."};
    if (status === 403)
        return {"code": "refused", "message": "AI Horde refused this request" + (d.message ? ": " + d.message : ".")};
    if (status === 400 || status === 422)
        return {"code": "bad_request", "message": "AI Horde did not accept the request" + (d.message ? ": " + d.message : ".")};
    return {"code": "http", "status": status, "message": "AI Horde answered HTTP " + status + (d.message ? ": " + d.message : ".")};
}

// {ok, id, kudos} or {ok: false, code, message, retryAfter} for the answer to the submit request.
function parseSubmit(status, text, retryAfter) {
    if (status === 200 || status === 202) {
        try {
            var obj = JSON.parse(text);
            if (obj && obj.id)
                return {"ok": true, "id": String(obj.id), "kudos": Number(obj.kudos) || 0};
        } catch (e) {}
        return {"ok": false, "code": "bad_response", "message": "AI Horde sent an answer the widget could not read."};
    }
    return Object.assign({"ok": false}, describeError(status, text, retryAfter));
}

// What a check of a job says: {finished, faulted, phase, queuePosition, waitTime, waiting, processing, done, total, possible}.
function parseCheck(obj) {
    obj = obj || {};
    var done = Number(obj.finished) || 0;
    var processing = Number(obj.processing) || 0;
    return {"done": obj.done === true || (obj.finished !== undefined && done > 0 && Number(obj.waiting) === 0 && processing === 0),
            "faulted": obj.faulted === true, "finished": done, "processing": processing, "waiting": Number(obj.waiting) || 0,
            "queuePosition": Number(obj.queue_position) || 0, "waitTime": Math.max(0, Number(obj.wait_time) || 0),
            "possible": obj.is_possible !== false, "phase": processing > 0 ? "working" : "queued"};
}

// The finished images of a status answer: [{url, b64, seed, model, censored}].
function parseGenerations(obj) {
    var list = obj && Array.isArray(obj.generations) ? obj.generations : [];
    var out = [];
    for (var i = 0; i < list.length; i++) {
        var g = list[i] || {};
        var img = String(g.img || "");
        if (img === "" || g.state === "faulted")
            continue;
        var isUrl = /^https:\/\//i.test(img);
        out.push({"url": isUrl ? img : "", "b64": isUrl ? "" : img.replace(/^data:[^,]*,/, ""), "seed": String(g.seed || ""), "model": String(g.model || ""),
                  "censored": g.censored === true});
    }
    return out;
}

// --- Models -------------------------------------------------------------------

function isSafeModel(model) {
    return !!model && !BLOCKED_NAMES.test(String(model.name || "")) && model.nsfw !== true && model.nsfw !== "true";
}

// The models to offer from GET /status/models?type=image: [{id, workers, eta, queued}] with the most workers first,
// without models that are made for adult content (by the list's own flags where it has them, and by name).
function parseModels(list) {
    var out = [];
    for (var i = 0; Array.isArray(list) && i < list.length; i++) {
        var m = list[i];
        if (!m || !m.name || (m.type && m.type !== "image") || !(Number(m.count) > 0) || !isSafeModel(m))
            continue;
        out.push({"id": String(m.name), "workers": Number(m.count) || 0, "eta": Number(m.eta) || 0, "queued": Number(m.queued) || 0});
    }
    out.sort(function(a, b) { return b.workers - a.workers; });
    return out;
}

// The model to start with: a well-known one that has workers, else the one with the most, else the fallback.
function defaultModel(models) {
    var ids = (models || []).map(function(m) { return m.id; });
    for (var i = 0; i < PREFERRED_MODELS.length; i++) {
        if (ids.indexOf(PREFERRED_MODELS[i]) >= 0)
            return PREFERRED_MODELS[i];
    }
    return ids.length > 0 ? ids[0] : FALLBACK_MODEL;
}

function modelsRequest(version, contact) {
    return {"url": BASE_URL + "/status/models?type=image&min_count=1", "headers": {"Client-Agent": clientAgent(version, contact), "Accept": "application/json"}};
}

// --- Running a job ---------------------------------------------------------------

function _json(text) {
    try { return JSON.parse(text); } catch (e) { return null; }
}

// Makes one image: submits, checks every few seconds, downloads the result. Returns {cancel()}.
// options: {prompt, model, apiKey, version, contact, width, height, steps, n, seed, giveUpMs, http, xhrFactory, setTimer, clearTimer, toBase64, onEvent}
function generate(options) {
    var http = options.http;
    var hasKey = !!options.apiKey && options.apiKey !== ANONYMOUS_KEY;
    var submit = buildSubmit(options);
    var headers = {"apikey": submit.headers.apikey, "Client-Agent": submit.headers["Client-Agent"]};
    var state = {"id": "", "stopped": false, "timer": null, "pending": null, "startedAt": 0};
    var giveUpMs = options.giveUpMs > 0 ? options.giveUpMs : GIVE_UP_MS;
    var clock = options.now || function() { return Date.now(); };

    function emit(event) {
        if (!state.stopped)
            options.onEvent(event);
    }
    function fail(error) {
        if (state.stopped)
            return;
        emit(Object.assign({"type": "error"}, error));
        stop(true);
    }
    function stop(cancelJob) {
        state.stopped = true;
        if (state.timer !== null)
            options.clearTimer(state.timer);
        state.timer = null;
        if (state.pending)
            state.pending.abort();
        state.pending = null;
        // Best effort: tell the service to drop a job that is not finished (it may already be running).
        if (cancelJob && state.id !== "" && !state.deleted && !state.finished) {
            state.deleted = true;
            http.request({"xhrFactory": options.xhrFactory, "method": "DELETE", "url": BASE_URL + "/generate/status/" + state.id,
                          "headers": headers, "timeoutMs": 15000}, function() {});
        }
    }
    function schedule(ms) {
        state.timer = options.setTimer(function() { state.timer = null; check(); }, ms);
    }
    function check() {
        if (state.stopped)
            return;
        if (clock() - state.startedAt > giveUpMs) {
            fail({"code": "too_long", "message": "AI Horde did not finish within " + Math.round(giveUpMs / 60000) + " minutes, so the request was cancelled. Try again later or pick another model."});
            return;
        }
        state.pending = http.request({"xhrFactory": options.xhrFactory, "url": BASE_URL + "/generate/check/" + state.id, "headers": headers, "timeoutMs": 20000}, function(res) {
            state.pending = null;
            if (state.stopped)
                return;
            var wait = clock() - state.startedAt > 60000 ? SLOW_POLL_MS : POLL_MS;
            if (res.status === 429 || res.status === 503) {
                schedule(Math.max(wait, http.retryAfterSeconds(res.header("retry-after"), clock()) * 1000));
                return;
            }
            var obj = res.status === 200 ? _json(res.text) : null;
            if (!obj) {
                // One lost check is not the end of the job: try again, but not forever.
                state.misses = (state.misses || 0) + 1;
                if (state.misses >= 4)
                    fail(describeError(res.status, res.text, 0));
                else
                    schedule(wait);
                return;
            }
            state.misses = 0;
            var c = parseCheck(obj);
            if (c.faulted) {
                fail({"code": "faulted", "message": "AI Horde could not make this image (the worker failed). Try again."});
            } else if (c.done) {
                fetchResult();
            } else {
                emit({"type": "progress", "phase": c.phase, "queuePosition": c.queuePosition, "waitTime": c.waitTime, "waiting": c.waiting,
                      "processing": c.processing, "finished": c.finished, "total": submit.params.n, "possible": c.possible});
                if (!c.possible && clock() - state.startedAt > 30000) {
                    fail({"code": "no_workers", "message": "AI Horde has no worker for this model right now. Pick another model in Settings → Connection."});
                    return;
                }
                schedule(wait);
            }
        });
    }
    function fetchResult() {
        state.pending = http.request({"xhrFactory": options.xhrFactory, "url": BASE_URL + "/generate/status/" + state.id, "headers": headers, "timeoutMs": 30000}, function(res) {
            state.pending = null;
            if (state.stopped)
                return;
            var found = res.status === 200 ? parseGenerations(_json(res.text)) : [];
            var usable = found.filter(function(g) { return !g.censored; });
            if (usable.length === 0) {
                fail(res.status === 200 && found.length > 0
                    ? {"code": "censored", "message": "AI Horde's safety filter blocked this image. Try different words."}
                    : describeError(res.status === 200 ? 502 : res.status, res.text, 0));
                return;
            }
            download(usable, [], 0);
        });
    }
    function download(list, items, at) {
        if (at >= list.length) {
            state.finished = true;
            emit({"type": "images", "items": items});
            emit({"type": "done"});
            state.stopped = true;
            return;
        }
        var g = list[at];
        var meta = {"seed": g.seed, "model": g.model, "width": submit.params.width, "height": submit.params.height};
        if (g.b64 !== "") {
            items.push(Object.assign({"kind": "data", "b64": g.b64, "mime": "image/webp"}, meta));
            download(list, items, at + 1);
            return;
        }
        state.pending = http.request({"xhrFactory": options.xhrFactory, "url": g.url, "binary": true, "timeoutMs": 60000}, function(res) {
            state.pending = null;
            var bytes = res.status >= 200 && res.status < 300 ? http.bytesOf(res.buffer) : null;
            if (!bytes || !http.looksLikeImage(bytes) || bytes.length > http.MAX_IMAGE_BYTES) {
                fail({"code": "download", "message": "AI Horde made the image, but it could not be downloaded. Try again."});
                return;
            }
            items.push(Object.assign({"kind": "data", "b64": options.toBase64(bytes), "mime": "image/webp"}, meta));
            download(list, items, at + 1);
        });
    }

    state.startedAt = clock();
    state.pending = http.request({"xhrFactory": options.xhrFactory, "method": "POST", "url": submit.url, "headers": submit.headers,
                                  "body": JSON.stringify(submit.body), "timeoutMs": 30000}, function(res) {
        state.pending = null;
        if (state.stopped)
            return;
        var parsed = parseSubmit(res.status, res.text, http.retryAfterSeconds(res.header("retry-after"), clock()));
        if (!parsed.ok) {
            fail(parsed);
            return;
        }
        state.id = parsed.id;
        emit({"type": "submitted", "id": parsed.id, "kudos": parsed.kudos});
        schedule(1000);
    });
    return {"cancel": function() { stop(true); }, "jobId": function() { return state.id; }};
}
