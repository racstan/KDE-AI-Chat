// Direct mode tools: talks to the tool bridge (kdeaichat/tool_bridge_server.py), which
// runs the user's MCP servers and the web_search / fetch_url tools. It is started through
// the helper (tools_bridge_start) the first time a request needs it, and only when
// something is configured. The tool list is cached and loaded again when the settings
// change or the bridge was restarted. A call that finds the bridge gone (it exits when idle)
// restarts it, sends the configuration again and retries once.
// `chat` is the widget root (main.qml).
import QtQuick

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

QtObject {
    id: bridge

    property var chat: null
    // Replaces XMLHttpRequest in tests.
    property var xhrFactory: null
    // Runs a helper command: function(command, payload, onDone(stdout)). Tests replace it.
    property var runHelper: function(command, payload, onDone) { chat.store.runHelper(command, payload, onDone); }

    readonly property int toolsTimeoutMs: 60000
    readonly property int callTimeoutMs: 150000

    // What the last successful load found: [{name, server, description, inputSchema}] and [{server, message}].
    property var tools: []
    property var errors: []
    // {baseUrl, token} of the running bridge, once known.
    property var connection: null

    property string _loadedKey: ""
    property bool _loading: false
    property var _waiters: []

    function _config() {
        var cfg = chat.plasmoid.configuration;
        var provider = String(cfg.webSearchProvider || "none");
        return {"servers": String(cfg.toolServers || "").trim(), "search": provider, "searxngUrl": String(cfg.searxngUrl || "").trim(),
                "fetch": cfg.webFetchEnabled === true};
    }

    // Tools are offered when there are servers, a search provider or page reading.
    function isEnabled() {
        var c = _config();
        return c.servers !== "" || (c.search !== "none" && c.search !== "") || c.fetch;
    }

    // {servers, errors}: the servers object from the settings text. Bad JSON gives no servers and an error.
    function parseServers(text) {
        var raw = String(text || "").trim();
        if (raw === "")
            return {"servers": {}, "errors": []};
        try {
            var value = JSON.parse(raw);
            if (value && typeof value === "object" && !Array.isArray(value))
                return {"servers": value, "errors": []};
        } catch (e) {
            return {"servers": {}, "errors": [{"server": "", "message": i18n("The tool servers are not valid JSON: %1", String(e.message || e))}]};
        }
        return {"servers": {}, "errors": [{"server": "", "message": i18n("The tool servers must be a JSON object.")}]};
    }

    function _requestBody() {
        var c = _config();
        var parsed = parseServers(c.servers);
        return {"body": {"servers": parsed.servers, "web": {"search": c.search === "" ? "none" : c.search, "searxngUrl": c.searxngUrl, "fetch": c.fetch}},
                "errors": parsed.errors};
    }

    // Starts the bridge if needed; done(ok, message). fresh: ask again even if known.
    function _start(fresh, done) {
        if (bridge.connection && !fresh) {
            done(true, "");
            return;
        }
        bridge.runHelper("tools_bridge_start", {}, function(stdout) {
            var result = {};
            try { result = JSON.parse(String(stdout).trim().split("\n").pop()); } catch (e) { result = {}; }
            if (result.port && result.token && result.status !== "error") {
                bridge.connection = {"baseUrl": "http://127.0.0.1:" + result.port, "token": String(result.token)};
                done(true, "");
            } else {
                bridge.connection = null;
                done(false, result.message || i18n("The tool bridge couldn't be started."));
            }
        });
    }

    // POSTs JSON to the bridge; done({status, data}). status 0: no answer (connection error or timeout).
    function _post(path, body, timeoutMs, done) {
        var xhr = bridge.xhrFactory ? bridge.xhrFactory() : new XMLHttpRequest();
        var finished = false;
        function finish(status, text) {
            if (finished)
                return;
            finished = true;
            var data = null;
            try { data = JSON.parse(text); } catch (e) { data = null; }
            done({"status": status, "data": data});
        }
        xhr.open("POST", bridge.connection.baseUrl + path);
        xhr.setRequestHeader("Authorization", "Bearer " + bridge.connection.token);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.timeout = timeoutMs;
        xhr.ontimeout = function() { finish(0, ""); };
        xhr.onerror = function() { finish(0, ""); };
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4)
                finish(xhr.status, xhr.responseText);
        };
        xhr.send(JSON.stringify(body));
    }

    // Sends the configuration; done({ok, status, message}). Remembers what it loaded.
    function _applyTools(done) {
        var built = _requestBody();
        var key = JSON.stringify(built.body);
        _post("/tools", built.body, bridge.toolsTimeoutMs, function(res) {
            if (res.status === 200 && res.data && Array.isArray(res.data.tools)) {
                bridge.tools = res.data.tools;
                bridge.errors = built.errors.concat(Array.isArray(res.data.errors) ? res.data.errors : []);
                bridge._loadedKey = key;
                done({"ok": true, "status": 200, "message": ""});
                return;
            }
            var message = res.data && res.data.error ? String(res.data.error) : (res.status === 0 ? i18n("The tool bridge did not answer.") : i18n("The tool bridge refused the request (HTTP %1).", res.status));
            done({"ok": false, "status": res.status, "message": message});
        });
    }

    // Loads (or reloads) the tool list; callback(ok). Waits for a load already running. ok is false when
    // the bridge failed; `errors` then says why. Nothing starts when no tools are configured.
    function load(callback) {
        if (!isEnabled()) {
            bridge.tools = [];
            bridge.errors = [];
            bridge._loadedKey = "";
            if (callback) callback(true, false);
            return;
        }
        var key = JSON.stringify(_requestBody().body);
        if (bridge._loadedKey === key && bridge.connection) {
            if (callback) callback(true, false);
            return;
        }
        bridge._waiters = bridge._waiters.concat([callback || function() {}]);
        if (bridge._loading)
            return;
        bridge._loading = true;
        function finish(ok) {
            bridge._loading = false;
            var waiters = bridge._waiters;
            bridge._waiters = [];
            for (var i = 0; i < waiters.length; i++)
                waiters[i](ok, true);
        }
        function failed(message) {
            bridge.tools = [];
            bridge.errors = _requestBody().errors.concat([{"server": "", "message": message}]);
            bridge._loadedKey = "";
            finish(false);
        }
        _start(false, function(ok, message) {
            if (!ok) {
                failed(message);
                return;
            }
            _applyTools(function(res) {
                if (res.ok) {
                    finish(true);
                } else if (res.status === 0 || res.status === 401) {
                    // The bridge was stopped (idle) and may have been replaced: fresh start, then again.
                    _start(true, function(ok2, message2) {
                        if (!ok2) { failed(message2); return; }
                        _applyTools(function(res2) { if (res2.ok) finish(true); else failed(res2.message); });
                    });
                } else {
                    failed(res.message);
                }
            });
        });
    }

    // Loads the list again even if the settings are the same (the Check servers button).
    function reload(callback) {
        bridge._loadedKey = "";
        bridge.load(callback);
    }

    // One line per server that failed (or "" when all is well), for the notice in the chat.
    function errorSummary() {
        return bridge.errors.map(function(e) { return (e.server ? e.server + ": " : "") + e.message; }).join("; ");
    }

    function _callOnce(name, args, done) {
        _post("/call", {"name": name, "arguments": args || {}}, bridge.callTimeoutMs, done);
    }

    function _output(res) {
        if (res.status === 200 && res.data && res.data.output !== undefined)
            return {"output": String(res.data.output), "isError": res.data.isError === true};
        return null;
    }

    // Runs a tool the user approved: callback(output, isError).
    function call(name, args, callback) {
        function give(text, isError) { callback(text, isError); }
        function failure(res) {
            var detail = res.data && res.data.error ? String(res.data.error) : "";
            if (res.status === 0)
                return i18n("The tool bridge did not answer.");
            return detail !== "" ? detail : i18n("The tool failed (HTTP %1).", res.status);
        }
        function attempt(retried) {
            if (!bridge.connection) {
                _start(false, function(ok, message) { if (ok) attempt(retried); else give(message, true); });
                return;
            }
            _callOnce(name, args, function(res) {
                var out = _output(res);
                if (out) {
                    give(out.output, out.isError);
                    return;
                }
                var gone = res.status === 0 || res.status === 401 || res.status === 404;
                if (!gone || retried) {
                    give(failure(res), true);
                    return;
                }
                // The bridge is gone or was restarted without our configuration: start it, send the configuration, once more.
                _start(true, function(ok, message) {
                    if (!ok) { give(message, true); return; }
                    _applyTools(function(applied) {
                        if (!applied.ok) { give(applied.message, true); return; }
                        attempt(true);
                    });
                });
            });
        }
        attempt(false);
    }
}
