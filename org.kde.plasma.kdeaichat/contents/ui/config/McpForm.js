.pragma library

// Settings → Tools: turns the "Add server" form into a definition for helper mcp_save (kdeaichat/mcp_config.py)
// and the secrets that go to the KWallet entry `mcp-<id>`. The definition only ever holds {secret: NAME}
// placeholders; the values travel in `secrets` to the wallet and nowhere else. Plain JavaScript, so tests run it in node.

var NAME_RE = /^[A-Za-z0-9_.-]{1,128}$/;

// One argument per line; blank lines are left out.
function parseLines(text) {
    return String(text || "").split("\n").map(function(l) { return l.replace(/\r$/, "").trim(); }).filter(function(l) { return l !== ""; });
}

function secretField(name) {
    return String(name).replace(/[^A-Za-z0-9_.-]/g, "_").substring(0, 80);
}

// rows: [{name, value, secret}] -> {values: {name: text | {secret: FIELD}}, secrets: {FIELD: value}} or {error}.
function pairs(rows, what) {
    var values = {}, secrets = {};
    for (var i = 0; i < (rows || []).length; i++) {
        var row = rows[i];
        var name = String(row.name || "").trim();
        if (name === "" && String(row.value || "") === "")
            continue;
        if (!NAME_RE.test(name))
            return {"error": what + ": “" + name.substring(0, 40) + "” isn't a valid name (letters, digits, . _ -)."};
        if (row.secret === true) {
            if (String(row.value || "") === "")
                return {"error": what + ": enter a value for " + name + ", or turn off “Secret”."};
            var field = secretField(name);
            values[name] = {"secret": field};
            secrets[field] = String(row.value);
        } else {
            values[name] = String(row.value || "");
        }
    }
    return {"values": values, "secrets": secrets};
}

// form: {name, kind: "command" | "url", command, args (text), cwd, url, env: [rows], headers: [rows]};
// takenIds: the ids in use. -> {ok: true, id, definition, secrets} or {ok: false, error}.
function build(form, takenIds, makeId) {
    var name = String(form.name || "").trim();
    if (name === "")
        return {"ok": false, "error": "Give the server a name."};
    var id = makeId(name, takenIds || []);
    var definition = {"id": id, "enabled": true};
    var rows;
    if (form.kind === "url") {
        var url = String(form.url || "").trim();
        if (!/^https?:\/\/[^\s/]+/i.test(url))
            return {"ok": false, "error": "The address must start with http:// or https://."};
        rows = pairs(form.headers, "Headers");
        if (rows.error)
            return {"ok": false, "error": rows.error};
        definition.url = url;
        definition.headers = rows.values;
    } else {
        var command = String(form.command || "").trim();
        if (command === "")
            return {"ok": false, "error": "Enter the program to run."};
        rows = pairs(form.env, "Environment");
        if (rows.error)
            return {"ok": false, "error": rows.error};
        definition.command = command;
        definition.args = parseLines(form.args);
        definition.env = rows.values;
        if (String(form.cwd || "").trim() !== "")
            definition.cwd = String(form.cwd).trim();
    }
    return {"ok": true, "id": id, "definition": definition, "secrets": rows.secrets};
}

// An import candidate (mcp_import) as a definition without secret values, plus the values: {definition, secrets}.
function fromCandidate(candidate) {
    var definition = {"id": candidate.id, "enabled": candidate.enabled !== false};
    var secrets = {};
    function strip(values) {
        var out = {};
        Object.keys(values || {}).forEach(function(key) {
            var v = values[key];
            if (v && typeof v === "object") {
                out[key] = {"secret": v.secret};
                if (typeof v.value === "string")
                    secrets[v.secret] = v.value;
            } else {
                out[key] = String(v);
            }
        });
        return out;
    }
    if (candidate.url) {
        definition.url = candidate.url;
        definition.headers = strip(candidate.headers);
    } else {
        definition.command = candidate.command;
        definition.args = candidate.args || [];
        definition.env = strip(candidate.env);
        if (candidate.cwd)
            definition.cwd = candidate.cwd;
    }
    return {"definition": definition, "secrets": secrets};
}

// "mcp:files:echo" -> "echo (files)"; other keys as they are.
function approvalLabel(key) {
    var m = /^mcp:([^:]*):(.*)$/.exec(String(key));
    return m ? m[2] + " (" + m[1] + ")" : String(key);
}
