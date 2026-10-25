.pragma library

// The providers and models of an OpenCode server (GET /config/providers, or
// the older /provider), reduced to what the widget uses.
//
// SECURITY: /config/providers echoes the API keys of the providers configured
// in the user's OpenCode (a `key` field per provider). parse() reads only
// provider ids and names, model ids and the NAMES of each model's variants.
// It copies nothing else, and callers must drop the parsed response right away:
// never log, store, cache or print it.
//
// Plain JavaScript (no QML imports) so tests run it under node.

function _s(value) {
    return value === undefined || value === null ? "" : String(value).trim();
}

// -> {providers: [{id, name}], models: ["provider/model", ...],
//     modelsByProvider: {provider: [model ids]},
//     variants: {"provider/model": [variant names]}}
// Models without variants are left out of `variants`.
function parse(data) {
    var out = {"providers": [], "models": [], "modelsByProvider": {}, "variants": {}};
    if (!data || typeof data !== "object")
        return out;
    var list = data.providers || data.all || data.connected || [];
    for (var i = 0; Array.isArray(list) && i < list.length; i++) {
        var p = list[i];
        var id = p ? _s(p.id || p.name) : "";
        if (id === "" || out.modelsByProvider[id])
            continue;
        out.providers.push({"id": id, "name": _s(p.name) || id});
        out.modelsByProvider[id] = [];
        var models = p.models;
        var keys = [];
        if (Array.isArray(models))
            keys = models.map(function(m, n) { return {"id": typeof m === "string" ? m : _s(m && m.id), "entry": typeof m === "string" ? null : m}; });
        else if (models && typeof models === "object")
            keys = Object.keys(models).map(function(k) { return {"id": k, "entry": models[k]}; });
        for (var j = 0; j < keys.length; j++) {
            var modelId = keys[j].id;
            if (modelId === "" || out.modelsByProvider[id].indexOf(modelId) >= 0)
                continue;
            out.modelsByProvider[id].push(modelId);
            out.models.push(id + "/" + modelId);
            var v = keys[j].entry && keys[j].entry.variants;
            if (v && typeof v === "object" && !Array.isArray(v) && Object.keys(v).length > 0)
                out.variants[id + "/" + modelId] = Object.keys(v);
        }
    }
    return out;
}
