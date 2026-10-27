.pragma library

// Words-free logic of the first-run setup (chat/FirstRun.qml): when it is
// offered, which cloud providers it lists and what it saves. Plain JavaScript
// (tested with node); the provider list and presets come from ProviderService.js
// through the caller.

// Cloud providers the first screen lists, in this order (preset ids).
var CLOUD_IDS = ["openai", "anthropic", "google", "openrouter", "groq", "mistral", "nvidia", "deepseek", "xai"];

var TERMS_URL = "https://github.com/racstan/KDE-AI-Chat/blob/master/TERMS.md";

// The cloud presets as rows: [{id, name, keyUrl, preset}] (unknown ids are skipped).
function cloudChoices(presetById) {
    var out = [];
    for (var i = 0; i < CLOUD_IDS.length; i++) {
        var preset = presetById(CLOUD_IDS[i]);
        if (preset)
            out.push({"id": preset.id, "name": preset.name, "keyUrl": preset.keyUrl || "", "preset": preset});
    }
    return out;
}

// Can this provider be chatted with now? Needs a model, and a key unless it is local.
// `isLocal(entry)` says whether it needs none.
function isUsable(entry, keys, isLocal) {
    if (!entry || entry.type === "image" || String(entry.model || "").trim() === "")
        return false;
    return isLocal(entry) || String((keys || {})[entry.id] || "").trim() !== "";
}

// Is the setup wanted? Only when direct mode is in use, the user has not skipped it,
// the wallet has been read and no provider is usable yet.
//   state: {providers, keys, isLocal, dismissed, agentMode, walletStatus}
// walletStatus is "unknown" until the keys have been read. With providers listed but the
// wallet unusable we cannot tell whether they have keys, so the card stays away.
function wanted(state) {
    if (state.dismissed || state.agentMode)
        return false;
    var status = state.walletStatus;
    if (status === "unknown")
        return false;
    var providers = state.providers || [];
    if (providers.length > 0 && status !== "ready")
        return false;
    for (var i = 0; i < providers.length; i++) {
        if (isUsable(providers[i], state.keys, state.isLocal))
            return false;
    }
    return true;
}

// The provider entry for a preset (or a found local server's overrides) with the chosen model.
function makeEntry(preset, id, model, overrides) {
    var entry = {"id": id, "name": preset.name || id, "type": preset.type || "openai-compat",
                 "baseUrl": preset.baseUrl || "", "model": model || preset.model || ""};
    if (preset.headers)
        entry.headers = preset.headers;
    var extra = overrides || {};
    for (var key in extra)
        entry[key] = extra[key];
    if (model)
        entry.model = model;
    return entry;
}

// `providers` with `entry` in place of the one with its id, or added at the end.
function upsert(providers, entry) {
    var out = [];
    var replaced = false;
    for (var i = 0; i < (providers || []).length; i++) {
        if (providers[i].id === entry.id) {
            out.push(entry);
            replaced = true;
        } else {
            out.push(providers[i]);
        }
    }
    if (!replaced)
        out.push(entry);
    return out;
}

// The model offered first: the preset's own if the provider lists it, else the first listed.
function pickModel(listed, presetModel) {
    var list = listed || [];
    if (presetModel && list.indexOf(presetModel) >= 0)
        return presetModel;
    return list.length > 0 ? list[0] : (presetModel || "");
}
