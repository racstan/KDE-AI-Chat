// Direct mode: the tools of the user's MCP servers (Settings → Tools). Plugs into chat/DirectToolRunner.qml as
// the provider of source "mcp" and the runner for kind "mcp". The servers are read with helper mcp_list, their
// tool lists come from the MCP bridge (mcp/McpBridge.qml) and are cached: the list of servers is looked at
// again after `listTtlMs`, a server's tools after `toolsTtlMs` or when its definition changed. A chat uses the
// enabled servers its setting `mcpServers` names (a list of ids; unset = all). Only direct chats ask providers
// for tools: OpenCode and Pi chats never get these.
//
// The provider answers from the cache at once and refreshes in the background. Only before the first look it
// waits for the lists, and the runner's provider timeout (2 s) decides: a server that is slow to start has no
// tools in that first request, and has them from the next one. A server that fails is left out (its note is
// kept in `notes`, and the Tools page shows the real error through its Test button); a chat is never broken by it.
// `chat` is the widget root (main.qml): store.runHelper, wallet, getSessionProperty.
import QtQuick
import "../mcp" as Mcp
import "../mcp/McpDefs.js" as Defs

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified
QtObject {
    id: mcp

    property var chat: null
    property var runner: null
    // Replaces XMLHttpRequest in tests.
    property var xhrFactory: null
    property int listTtlMs: 20000
    property int toolsTtlMs: 300000
    property int errorTtlMs: 60000

    // The enabled servers as of the last look, and {serverId: short note} for those that failed.
    property var servers: []
    property var notes: ({})

    property double _listedAt: 0
    property bool _refreshing: false
    property var _waiters: []
    property var _cache: ({})    // id -> {fingerprint, at, tools, error}

    readonly property Mcp.McpBridge bridge: Mcp.McpBridge {
        runHelper: mcp.chat && mcp.chat.store ? mcp.chat.store.runHelper : null
        wallet: mcp.chat ? mcp.chat.wallet : null
        xhrFactory: mcp.xhrFactory
    }

    Component.onCompleted: {
        if (!mcp.runner)
            return;
        mcp.runner.registerProvider({"source": "mcp", "tools": mcp.toolsFor});
        mcp.runner.registerRunner("mcp", mcp.runTool);
    }

    // Look at the servers again before the next request (the settings changed).
    function invalidate() {
        mcp._listedAt = 0;
    }

    function toolsFor(sessionId, cb) {
        if (!mcp.chat || !mcp.chat.store || !mcp.chat.store.runHelper) {
            cb([]);
            return;
        }
        if (mcp._listedAt === 0) {
            mcp._refresh(function() { cb(mcp._entriesFor(sessionId)); });
            return;
        }
        cb(mcp._entriesFor(sessionId));
        if (Date.now() - mcp._listedAt >= mcp.listTtlMs)
            mcp._refresh(null);
    }

    function _entriesFor(sessionId) {
        const chosenIds = mcp.chat.getSessionProperty ? mcp.chat.getSessionProperty(sessionId, "mcpServers", null) : null;
        let out = [];
        Defs.chosen(mcp.servers, chosenIds).forEach(function(server) {
            const held = mcp._cache[server.id];
            if (held && held.tools)
                out = out.concat(Defs.entries(server.id, held.tools));
        });
        return out;
    }

    function _refresh(cb) {
        if (cb)
            mcp._waiters = mcp._waiters.concat([cb]);
        if (mcp._refreshing)
            return;
        mcp._refreshing = true;
        mcp.chat.store.runHelper("mcp_list", {}, function(stdout, exitCode) {
            let list = [];
            try {
                list = exitCode === 0 ? (JSON.parse(stdout).servers || []) : [];
            } catch (e) {
                list = [];
            }
            mcp.servers = list.filter(function(s) { return s && s.id && s.enabled !== false; });
            mcp._listedAt = Date.now();
            const keep = {};
            mcp.servers.forEach(function(s) { if (mcp._cache[s.id]) keep[s.id] = mcp._cache[s.id]; });
            mcp._cache = keep;
            const todo = mcp.servers.filter(function(s) { return mcp._stale(s); });
            let remaining = todo.length;
            if (remaining === 0) {
                mcp._finish();
                return;
            }
            todo.forEach(function(s) { mcp._fetch(s, function() { if (--remaining === 0) mcp._finish(); }); });
        });
    }

    function _finish() {
        const waiters = mcp._waiters;
        mcp._waiters = [];
        mcp._refreshing = false;
        const noted = {};
        Object.keys(mcp._cache).forEach(function(id) { if (mcp._cache[id].error) noted[id] = mcp._cache[id].error; });
        mcp.notes = noted;
        waiters.forEach(function(f) { f(); });
    }

    function _stale(server) {
        const held = mcp._cache[server.id];
        if (!held || held.fingerprint !== Defs.fingerprint(server))
            return true;
        return Date.now() - held.at >= (held.error ? mcp.errorTtlMs : mcp.toolsTtlMs);
    }

    function _fetch(server, done) {
        const fingerprint = Defs.fingerprint(server);
        function store(tools, error) {
            const cache = Object.assign({}, mcp._cache);
            cache[server.id] = {"fingerprint": fingerprint, "at": Date.now(), "tools": tools, "error": error};
            mcp._cache = cache;
            done();
        }
        mcp.bridge.resolve(server, function(resolved) {
            if (!resolved.ok) {
                store(null, resolved.error);
                return;
            }
            mcp.bridge.tools(resolved.definition, function(result) {
                if (result.ok)
                    store(result.tools, "");
                else
                    store(null, result.error);
            });
        });
    }

    // The runner's function for kind "mcp": call {id, name (the tool's own), args}, entry (server, ...), done(output, isError).
    function runTool(call, entry, done) {
        const server = mcp.servers.find(function(s) { return s.id === entry.server; });
        if (!server) {
            done(i18n("The MCP server %1 isn't turned on any more.", entry.server), true);
            return;
        }
        mcp.bridge.resolve(server, function(resolved) {
            if (!resolved.ok) {
                done(resolved.error, true);
                return;
            }
            mcp.bridge.call(resolved.definition, call.name, call.args, 85, function(result) {
                if (result.ok)
                    done(result.content, result.isError);
                else
                    done(i18n("The MCP server didn't answer: %1", result.error), true);
            });
        });
    }
}
