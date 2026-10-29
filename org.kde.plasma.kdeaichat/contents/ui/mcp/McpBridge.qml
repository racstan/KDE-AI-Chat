// The widget's and the settings page's client of the MCP bridge (kdeaichat/mcp_bridge_server.py): starts
// or finds the bridge (helper mcp_bridge_start), resolves a server's {secret} placeholders from its KWallet
// entry (store/Wallet.qml readEntry; the values stay in this process and never go through the helper), and
// calls the bridge's /tools and /call over loopback HTTP with the access token. The bridge exits when idle:
// a refused connection starts it again once.
//
//   resolve(def, cb)        cb({ok, definition} | {ok: false, error})
//   tools(definition, cb)   cb({ok, tools} | {ok: false, error})       one server
//   call(definition, tool, args, seconds, cb)   cb({ok, content, isError} | {ok: false, error})
import QtQuick
import "McpDefs.js" as Defs

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified
QtObject {
    id: bridge

    // function(command, payload, onDone(stdout, exitCode, stderr)).
    property var runHelper: null
    // store/Wallet.qml (readEntry).
    property var wallet: null
    // Replaces XMLHttpRequest in tests.
    property var xhrFactory: null

    property var _info: null
    property var _waiting: []

    function resolve(def, cb) {
        const names = Defs.secretNames(def);
        if (names.length === 0) {
            cb({"ok": true, "definition": Defs.resolve(def, {}).definition});
            return;
        }
        if (!bridge.wallet || typeof bridge.wallet.readEntry !== "function") {
            cb({"ok": false, "error": i18n("KWallet isn't available, so this server's secrets can't be read.")});
            return;
        }
        bridge.wallet.readEntry(Defs.walletEntry(def.id), function(ok, fields) {
            if (!ok) {
                cb({"ok": false, "error": i18n("KWallet didn't give access to this server's secrets.")});
                return;
            }
            const resolved = Defs.resolve(def, fields);
            if (resolved.missing.length > 0)
                cb({"ok": false, "error": i18n("The wallet has no value for: %1", resolved.missing.join(", "))});
            else
                cb({"ok": true, "definition": resolved.definition});
        });
    }

    // cb({port, token}, "") or cb(null, errorText). One start at a time.
    function _bridgeInfo(cb, restart) {
        if (bridge._info && !restart) {
            cb(bridge._info, "");
            return;
        }
        bridge._waiting = bridge._waiting.concat([cb]);
        if (bridge._waiting.length > 1)
            return;
        function finish(info, error) {
            const list = bridge._waiting;
            bridge._waiting = [];
            bridge._info = info;
            list.forEach(function(f) { f(info, error); });
        }
        if (!bridge.runHelper) {
            finish(null, i18n("The helper isn't available."));
            return;
        }
        bridge.runHelper("mcp_bridge_start", {}, function(stdout, exitCode) {
            let result = null;
            try {
                result = JSON.parse(stdout);
            } catch (e) {
                result = null;
            }
            if (exitCode !== 0 || !result || result.status === "error" || !result.port || !result.token)
                finish(null, result && result.message ? String(result.message) : i18n("The MCP bridge didn't start."));
            else
                finish({"port": result.port, "token": result.token}, "");
        });
    }

    function _post(path, body, timeoutMs, cb, retried) {
        bridge._bridgeInfo(function(info, error) {
            if (!info) {
                cb({"ok": false, "error": error});
                return;
            }
            const xhr = bridge.xhrFactory ? bridge.xhrFactory() : new XMLHttpRequest();
            xhr.open("POST", "http://127.0.0.1:" + info.port + path);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("Authorization", "Bearer " + info.token);
            try {
                xhr.timeout = timeoutMs;
            } catch (e) {
                // a stand-in without timeouts
            }
            let done = false;
            function finish(result) {
                if (done)
                    return;
                done = true;
                cb(result);
            }
            xhr.ontimeout = function() { finish({"ok": false, "error": i18n("The MCP bridge didn't answer in time.")}); };
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== 4 || done)
                    return;
                if ((xhr.status === 0 || xhr.status === 401) && !retried) {
                    done = true;
                    bridge._bridgeInfo(function() { bridge._post(path, body, timeoutMs, cb, true); }, true);
                    return;
                }
                if (xhr.status !== 200) {
                    finish({"ok": false, "error": xhr.status === 0 ? i18n("Couldn't reach the MCP bridge.") : i18n("The MCP bridge answered HTTP %1.", xhr.status)});
                    return;
                }
                try {
                    finish({"ok": true, "data": JSON.parse(xhr.responseText)});
                } catch (e) {
                    finish({"ok": false, "error": i18n("The MCP bridge sent something unreadable.")});
                }
            };
            xhr.send(JSON.stringify(body));
        }, false);
    }

    function tools(definition, cb) {
        bridge._post("/tools", {"servers": [definition]}, 120000, function(r) {
            if (!r.ok) {
                cb(r);
                return;
            }
            const entry = (r.data.servers || {})[definition.id] || {};
            if (entry.error)
                cb({"ok": false, "error": Defs.shortError(entry.error)});
            else
                cb({"ok": true, "tools": Array.isArray(entry.tools) ? entry.tools : []});
        }, false);
    }

    function call(definition, tool, args, seconds, cb) {
        bridge._post("/call", {"server": definition, "tool": tool, "arguments": args || {}, "timeout": seconds},
                     (seconds + 15) * 1000, function(r) {
            if (!r.ok) {
                cb(r);
                return;
            }
            cb({"ok": true, "content": String(r.data.content === undefined ? "" : r.data.content), "isError": r.data.isError === true});
        }, false);
    }
}
