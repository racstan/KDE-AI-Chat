.pragma library

// The variants (reasoning / thinking levels, see Variants.js) of one direct
// provider model, found where the provider reports them.
//
// 1. The provider's /models list (ProviderCheck.listModels already puts them in
//    its result as `variants`): the list is cached here per provider URL, so a
//    model chosen later costs no request.
// 2. A local server's POST /api/show (Ollama): it names the models that think,
//    one request per model, cached. Other local servers answer 404: no variants.
//
// A provider that reports nothing gives [] and the widget shows no picker.
// Plain JavaScript (no QML imports) so tests run it under node; the caller
// passes ProviderCheck.listModels in as `list`.

var CACHE_MS = 30 * 60 * 1000;
var _lists = {};   // provider URL -> {at, models: {id: [variants]}}
var _shown = {};   // provider URL + model -> {at, variants}

function _root(cfg) {
    return String(cfg.baseUrl || "").replace(/\/+$/, "").replace(/\/chat\/completions$/, "");
}

function _fresh(entry) {
    return entry && Date.now() - entry.at < CACHE_MS ? entry : null;
}

function clear() {
    _lists = {};
    _shown = {};
}

// Remembers a listModels result (from any caller) for later lookups.
function remember(cfg, result) {
    if (result && result.ok)
        _lists[_root(cfg)] = {"at": Date.now(), "models": result.variants || {}};
}

function _isLoopback(url) {
    return /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])[:\/]/i.test(String(url || ""));
}

// Ollama: "thinking" in /api/show's capabilities. It cannot say which levels,
// and over the OpenAI-style route the one value that works for every thinking
// model is reasoning_effort "none", so the one variant offered is "off".
function _show(cfg, model, cb, opts) {
    var o = opts || {};
    var root = _root(cfg).replace(/\/v1$/, "");
    var key = root + "\n" + model;
    var cached = _fresh(_shown[key]);
    if (cached) { cb(cached.variants); return; }
    var done = false;
    function finish(status, text) {
        if (done) return;
        done = true;
        var variants = [];
        try {
            var caps = status >= 200 && status < 300 ? JSON.parse(text).capabilities : null;
            if (Array.isArray(caps) && caps.indexOf("thinking") >= 0)
                variants = [{"id": "off", "label": "Thinking off", "send": {"reasoning_effort": "none"}}];
        } catch (e) {}
        if (status > 0)
            _shown[key] = {"at": Date.now(), "variants": variants};
        cb(variants);
    }
    try {
        var xhr = o.xhrFactory ? o.xhrFactory() : new XMLHttpRequest();
        xhr.open("POST", root + "/api/show", true);
        xhr.timeout = o.timeout || 10000;
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() { if (xhr.readyState === 4) finish(xhr.status, String(xhr.responseText || "")); };
        xhr.ontimeout = function() { finish(0, ""); };
        xhr.onerror = function() { finish(0, ""); };
        xhr.send(JSON.stringify({"model": model}));
    } catch (e) {
        finish(0, "");
    }
}

// The cached variants of a model: an array (maybe empty), or null when the
// provider has not been asked about it yet.
function cached(cfg, model) {
    var list = _fresh(_lists[_root(cfg)]);
    if (!list)
        return null;
    if (list.models[model])
        return list.models[model];
    if (!_isLoopback(cfg.baseUrl))
        return [];
    var shown = _fresh(_shown[_root(cfg).replace(/\/v1$/, "") + "\n" + model]);
    return shown ? shown.variants : null;
}

// cb(variants) for `model` of the provider `cfg` ({type, baseUrl, headers}):
// from the cache, else after fetching its model list (`list` is
// ProviderCheck.listModels) and, for a local server, /api/show.
function forModel(cfg, apiKey, model, list, cb, opts) {
    var id = String(model || "");
    if (id === "") { cb([]); return; }
    var hit = cached(cfg, id);
    if (hit) { cb(hit); return; }
    function afterList() {
        var known = (_fresh(_lists[_root(cfg)]) || {"models": {}}).models[id];
        if (known) cb(known);
        else if (_isLoopback(cfg.baseUrl)) _show(cfg, id, cb, opts);
        else cb([]);
    }
    if (_fresh(_lists[_root(cfg)])) { afterList(); return; }
    list(cfg, apiKey, function(result) { remember(cfg, result); afterList(); }, opts);
}
