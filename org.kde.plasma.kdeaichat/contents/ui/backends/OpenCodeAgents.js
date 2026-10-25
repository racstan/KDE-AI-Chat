.pragma library

// The OpenCode agent list: which agents can be picked for a chat, and what the
// agent selector shows. Plain JavaScript (tested with node): no QML globals.
//
// GET /agent?directory=<workspace> (OpenCode 1.18) answers an array of
// {name, mode: "primary" | "subagent" | "all", hidden, native, ...}. The
// directory matters: agents defined in the workspace (.opencode/agent/*.md,
// its opencode.json) are only listed for it. Subagents and hidden agents
// (compaction, title, summary) can't run a chat, so they are left out.

// Built-in helper agents; only used to filter entries that don't say their mode.
var HELPER_AGENTS = ["compaction", "explore", "general", "summary", "title"];

function _selectable(name, entry) {
    if (!entry || typeof entry !== "object")
        return HELPER_AGENTS.indexOf(String(name).toLowerCase()) < 0;
    if (entry.hidden === true || entry.internal === true || entry.isSubagent === true)
        return false;
    var mode = entry.mode || entry.agentMode || entry.type || entry.kind;
    if (mode)
        return !/sub[-_ ]?agent|internal/i.test(String(mode));
    return HELPER_AGENTS.indexOf(String(name).toLowerCase()) < 0;
}

// payload: the /agent answer (an array), or an object holding one under
// agents/agent/data/items, or a {name: spec} map. Returns [{text, value}].
function normalize(payload) {
    var names = [];
    function add(entry, keyName) {
        var name = typeof entry === "string" ? entry : (entry && (entry.name || entry.id || entry.value || entry.text));
        name = name || keyName || "";
        if (typeof name !== "string" || name === "" || name.length > 128 || names.indexOf(name) >= 0 || names.length >= 100)
            return;
        if (_selectable(name, entry))
            names.push(name);
    }
    function read(value) {
        if (!value)
            return;
        if (Array.isArray(value)) {
            for (var i = 0; i < value.length; i++) add(value[i]);
            return;
        }
        if (typeof value !== "object") {
            add(value);
            return;
        }
        var known = ["agents", "agent", "data", "items"];
        for (var k = 0; k < known.length; k++) {
            if (value[known[k]] !== undefined) {
                read(value[known[k]]);
                return;
            }
        }
        var keys = Object.keys(value);
        for (var j = 0; j < keys.length; j++) {
            if (keys[j] !== "default" && keys[j] !== "default_agent")
                add(value[keys[j]], keys[j]);
        }
    }
    read(payload);
    var result = [];
    for (var n = 0; n < names.length; n++)
        result.push({"text": names[n], "value": names[n]});
    return result;
}

// What the agent selector lists for a chat whose agent is `current`: the
// server's list, plus an entry for `current` when the list doesn't have it, so
// the selector always shows the agent the chat really sends with ("" = no
// agent given: OpenCode uses its default agent). With no list yet (server not
// reached), just the chat's agent.
function comboModel(list, current) {
    var model = (list || []).slice();
    current = current === undefined || current === null ? "" : String(current);
    for (var i = 0; i < model.length; i++) {
        if (model[i].value === current)
            return model;
    }
    if (current === "")
        return [{"text": "Default", "value": ""}].concat(model);
    return model.concat([{"text": model.length > 0 ? current + " (not on server)" : current, "value": current}]);
}

// Index of `current` in comboModel(list, current).
function indexOf(model, current) {
    current = current === undefined || current === null ? "" : String(current);
    for (var i = 0; i < (model || []).length; i++) {
        if (model[i].value === current)
            return i;
    }
    return -1;
}
