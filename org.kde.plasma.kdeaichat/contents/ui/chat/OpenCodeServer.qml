// The OpenCode server for OpenCodeMode.qml: makes sure one answers at the configured URL (starting a local one
// through the helper when nothing runs) and loads the password of a server the widget started
// (helper opencode_server_auth) into backends/OpenCodeBackend.js. `chat` is the widget root (main.qml).
import QtQuick
import "../backends/OpenCodeBackend.js" as OpenCodeBackend

QtObject {
    id: server

    property var chat: null

    // Loads the password of the server the widget started (helper opencode_server_auth) into the backend
    // before fn runs. Only a local address gets one; a server the user started has none.
    function withAuth(baseUrl, fn) {
        var match = /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\]):(\d+)/i.exec(String(baseUrl || ""));
        if (!match || !chat.store || !chat.store.runHelper) {
            OpenCodeBackend.setAuthorization("");
            fn();
            return;
        }
        chat.store.runHelper("opencode_server_auth", {"port": Number(match[2])}, function(stdout) {
            var result = {};
            try { result = JSON.parse(String(stdout).trim().split("\n").pop()); } catch (e) { result = {}; }
            OpenCodeBackend.setAuthorization(result.authorization);
            fn();
        });
    }

    // done(ok, message)
    function ensure(baseUrl, directory, done) {
        server.withAuth(baseUrl, function() { server._ensureOpenCodeServer(baseUrl, directory, done); });
    }

    function _ensureOpenCodeServer(baseUrl, directory, done) {
        var xhr = new XMLHttpRequest();
        var finished = false;
        function finish(ok, message) { if (!finished) { finished = true; done(ok, message); } }
        function notRunning() {
            var match = /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\]):(\d+)/i.exec(baseUrl);
            if (!match) {
                finish(false, "OpenCode isn't reachable at " + baseUrl + ".");
                return;
            }
            chat.store.runHelper("opencode_server_start", {"port": Number(match[2]), "directory": directory}, function(stdout) {
                var result = {};
                try { result = JSON.parse(stdout); } catch (e) { result = {}; }
                if (result.status === "started" || result.status === "already-running")
                    server.withAuth(baseUrl, function() { finish(true, ""); });
                else
                    finish(false, "OpenCode isn't running at " + baseUrl + " and couldn't be started: " + (result.message || "unknown error") + ".");
            });
        }
        try {
            xhr.open("GET", baseUrl + "/global/health", true);
            OpenCodeBackend.authorize(xhr);
            xhr.timeout = 1500;
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status >= 200 && xhr.status < 300) finish(true, "");
                else notRunning();
            };
            xhr.ontimeout = notRunning;
            xhr.send();
        } catch (e) {
            notRunning();
        }
    }
}
