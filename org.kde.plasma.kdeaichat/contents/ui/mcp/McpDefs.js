.pragma library

// Pure helpers for MCP server definitions (mcp.json, see kdeaichat/mcp_config.py). An env or header
// value is plain text or {secret: NAME}, a field of the KWallet entry `mcp-<id>`. Plain JavaScript,
// so tests run it in node.

function walletEntry(id) {
    return "mcp-" + id;
}

function isRemote(def) {
    return !!(def && def.url);
}

function _pairs(def) {
    var out = [];
    ["env", "headers"].forEach(function(key) {
        var values = def && def[key] ? def[key] : {};
        Object.keys(values).forEach(function(name) { out.push({"group": key, "name": name, "value": values[name]}); });
    });
    return out;
}

// The wallet fields a definition points to, without repeats.
function secretNames(def) {
    var names = [];
    _pairs(def).forEach(function(p) {
        if (p.value && typeof p.value === "object" && typeof p.value.secret === "string" && names.indexOf(p.value.secret) < 0)
            names.push(p.value.secret);
    });
    return names;
}

// The definition as the bridge takes it: placeholders replaced by `secrets` ({NAME: value}), no
// "enabled". missing: the names the wallet had no value for.
function resolve(def, secrets) {
    var out = {};
    var missing = [];
    Object.keys(def || {}).forEach(function(key) {
        if (key !== "enabled")
            out[key] = def[key];
    });
    ["env", "headers"].forEach(function(group) {
        if (!def || !def[group])
            return;
        var values = {};
        Object.keys(def[group]).forEach(function(name) {
            var v = def[group][name];
            if (v && typeof v === "object") {
                var value = (secrets || {})[v.secret];
                if (typeof value === "string" && value !== "")
                    values[name] = value;
                else if (missing.indexOf(v.secret) < 0)
                    missing.push(v.secret);
            } else {
                values[name] = String(v);
            }
        });
        out[group] = values;
    });
    return {"definition": out, "missing": missing};
}

// A fingerprint of the saved definition (placeholders, not secrets): when it changes, the tools are listed again.
function fingerprint(def) {
    return JSON.stringify(def, Object.keys(def || {}).sort());
}

// The tool entries of one server for the runner's registry.
function entries(serverId, tools) {
    return (Array.isArray(tools) ? tools : []).filter(function(t) { return t && typeof t.name === "string" && t.name !== ""; })
        .map(function(t) {
            return {"name": t.name, "description": String(t.description || ""), "schema": t.inputSchema,
                    "source": "mcp:" + serverId, "server": serverId, "risk": "change", "timeoutMs": 90000};
        });
}

// The servers a chat uses: `chosenIds` null/undefined = every enabled server, else the enabled ones in the list.
function chosen(servers, chosenIds) {
    var enabled = (servers || []).filter(function(s) { return s && s.enabled !== false; });
    if (!Array.isArray(chosenIds))
        return enabled;
    return enabled.filter(function(s) { return chosenIds.indexOf(s.id) >= 0; });
}

// A short plain note from an error text.
function shortError(text) {
    var line = String(text === undefined || text === null ? "" : text).split("\n")[0].trim();
    return line.length > 200 ? line.substring(0, 200) + "…" : line;
}

// An id from a name: lowercase letters, digits, - and _ (kdeaichat/mcp_config.py ID_RE), not one in `taken`.
function makeId(name, taken) {
    var base = String(name || "").toLowerCase().replace(/[^a-z0-9_-]+/g, "-").replace(/^[-_]+|[-_]+$/g, "").substring(0, 36) || "server";
    var id = base;
    for (var n = 2; (taken || []).indexOf(id) >= 0; n++)
        id = base + "-" + n;
    return id;
}
