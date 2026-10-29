// Settings → Tools: the MCP servers in mcp.json (helper mcp_list / mcp_save / mcp_delete / mcp_import) and
// their secrets in KWallet entries `mcp-<id>` (store/Wallet.qml), with the Test button's check through the
// bridge (mcp/McpBridge.qml). A secret's value goes to the wallet and nowhere else: the helper only gets
// {secret: NAME} placeholders. Nothing here is a cfg_ setting. Every change is written at once.
import QtQuick
import "../mcp" as Mcp
import "../mcp/McpDefs.js" as Defs
import "McpForm.js" as Form

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified
QtObject {
    id: store

    // function(command, payload, onDone(stdout, exitCode, stderr)); store/Wallet.qml; XMLHttpRequest stand-in.
    property var runHelper: null
    property var wallet: null
    property var xhrFactory: null

    // [{id, enabled, command | url, ...}] as saved, placeholders instead of secrets.
    property var servers: []
    property bool loaded: false
    // The last problem, in plain words ("" = none).
    property string message: ""
    // {serverId: {state: "testing" | "ok" | "error", count, names, text}}
    property var tests: ({})
    // Import: candidates from other apps, and whether they were read.
    property var candidates: []
    property bool candidatesLoaded: false

    readonly property Mcp.McpBridge bridge: Mcp.McpBridge {
        runHelper: store.runHelper
        wallet: store.wallet
        xhrFactory: store.xhrFactory
    }

    function ids() {
        return store.servers.map(function(s) { return s.id; });
    }

    function _parse(stdout, exitCode) {
        try {
            return exitCode === 0 ? JSON.parse(stdout) : null;
        } catch (e) {
            return null;
        }
    }

    function load(cb) {
        store.runHelper("mcp_list", {}, function(stdout, exitCode) {
            const result = store._parse(stdout, exitCode);
            if (result && Array.isArray(result.servers)) {
                store.servers = result.servers;
                store.loaded = true;
            } else {
                store.message = i18n("Couldn't read the list of MCP servers.");
            }
            if (cb)
                cb();
        });
    }

    // Saves one definition (placeholders only) after putting its secrets in the wallet; cb(ok, errorText).
    function _saveOne(definition, secrets, cb) {
        const entry = Defs.walletEntry(definition.id);
        function save() {
            store.runHelper("mcp_save", {"server": definition}, function(stdout, exitCode) {
                const result = store._parse(stdout, exitCode);
                if (result && result.status === "ok") {
                    cb(true, "");
                    return;
                }
                if (Object.keys(secrets).length > 0 && store.ids().indexOf(definition.id) < 0)
                    store.wallet.writeEntry(entry, {}, function() {});
                cb(false, result && result.message ? String(result.message) : i18n("The helper couldn't save the server."));
            });
        }
        if (Object.keys(secrets).length === 0) {
            save();
            return;
        }
        if (!store.wallet || typeof store.wallet.writeEntry !== "function") {
            cb(false, i18n("KWallet isn't available, so the secrets can't be stored."));
            return;
        }
        store.wallet.writeEntry(entry, secrets, function(ok) {
            if (ok)
                save();
            else
                cb(false, i18n("KWallet didn't allow storing the secrets. Nothing was saved."));
        });
    }

    // The "Add server" form (config/McpForm.js build()); cb(ok, errorText).
    function add(form, cb) {
        const built = Form.build(form, store.ids(), Defs.makeId);
        if (!built.ok) {
            cb(false, built.error);
            return;
        }
        store._saveOne(built.definition, built.secrets, function(ok, error) {
            if (ok)
                store.load(function() { cb(true, ""); });
            else
                cb(false, error);
        });
    }

    function setEnabled(id, on) {
        const server = store.servers.find(function(s) { return s.id === id; });
        if (!server)
            return;
        store.runHelper("mcp_save", {"server": Object.assign({}, server, {"enabled": on})}, function(stdout, exitCode) {
            const result = store._parse(stdout, exitCode);
            if (!result || result.status !== "ok")
                store.message = i18n("Couldn't change the server.");
            store.load(null);
        });
    }

    function remove(id) {
        store.runHelper("mcp_delete", {"id": id}, function(stdout, exitCode) {
            const result = store._parse(stdout, exitCode);
            if (!result || result.status !== "ok") {
                store.message = i18n("Couldn't delete the server.");
                return;
            }
            if (store.wallet && typeof store.wallet.writeEntry === "function")
                store.wallet.writeEntry(Defs.walletEntry(id), {}, function() {});
            const next = Object.assign({}, store.tests);
            delete next[id];
            store.tests = next;
            store.load(null);
        });
    }

    function _setTest(id, value) {
        const next = Object.assign({}, store.tests);
        next[id] = value;
        store.tests = next;
    }

    // Lists the server's tools through the bridge and keeps the count or the error in `tests`.
    function test(id) {
        const server = store.servers.find(function(s) { return s.id === id; });
        if (!server)
            return;
        store._setTest(id, {"state": "testing", "count": 0, "names": "", "text": ""});
        store.bridge.resolve(server, function(resolved) {
            if (!resolved.ok) {
                store._setTest(id, {"state": "error", "count": 0, "names": "", "text": resolved.error});
                return;
            }
            store.bridge.tools(resolved.definition, function(result) {
                if (result.ok)
                    store._setTest(id, {"state": "ok", "count": result.tools.length, "text": "",
                                        "names": result.tools.slice(0, 12).map(function(t) { return String(t.name); }).join(", ")});
                else
                    store._setTest(id, {"state": "error", "count": 0, "names": "", "text": result.error});
            });
        });
    }

    function loadCandidates() {
        store.runHelper("mcp_import", {}, function(stdout, exitCode) {
            const result = store._parse(stdout, exitCode);
            store.candidates = result && Array.isArray(result.servers) ? result.servers : [];
            store.candidatesLoaded = true;
            if (!result)
                store.message = i18n("Couldn't look for servers in other apps.");
        });
    }

    // Imports the candidates with these ids, one after another; cb(importedCount, [problems]).
    function importCandidates(wanted, cb) {
        const list = store.candidates.filter(function(c) { return wanted.indexOf(c.id) >= 0 && !c.exists && !c.problem; });
        const problems = [];
        let imported = 0;
        let i = 0;
        function next() {
            if (i >= list.length) {
                store.load(function() { cb(imported, problems); });
                return;
            }
            const candidate = list[i++];
            const parts = Form.fromCandidate(candidate);
            store._saveOne(parts.definition, parts.secrets, function(ok, error) {
                if (ok)
                    imported++;
                else
                    problems.push(candidate.id + ": " + error);
                next();
            });
        }
        next();
    }
}
