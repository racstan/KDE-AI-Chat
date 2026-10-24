// Runs kde_ai_helper.py commands and calls back with their output.
//
// run("prepare_chat_dir", {...}, function(stdout, exitCode, stderr) {...})
// The payload is passed base64-encoded as one argument, so keep it small and
// never put secrets in it (arguments are visible in the process list).
import QtQuick
import org.kde.plasma.plasma5support as P5Support
import "../Security.js" as Sec

P5Support.DataSource {
    id: runner
    engine: "executable"
    connectedSources: []

    property string helperPath: ""
    property var _callbacks: ({})
    property int _counter: 0

    function run(command, payload, onDone) {
        if (!helperPath || !/^[a-z_]{1,64}$/.test(command)) {
            if (onDone) onDone("", 1, "helper unavailable");
            return;
        }
        var token = "#helper-" + (++_counter) + "-" + Date.now();
        if (onDone)
            _callbacks[token] = onDone;
        var encoded = Sec.base64Encode(JSON.stringify(payload || {}));
        connectSource("python3 " + Sec.quoteForShell(helperPath) + " " + command + " "
            + Sec.rawShellSnippetQuote(encoded) + " " + token);
    }

    onNewData: function(sourceName, data) {
        disconnectSource(sourceName);
        var token = sourceName.substring(sourceName.indexOf("#helper-"));
        var callback = _callbacks[token];
        delete _callbacks[token];
        var exitCode = Number(data["exit code"]);
        if (exitCode !== 0)
            console.warn("KDE AI Chat: helper command failed:", sourceName.split(" ")[2], data["stderr"] || "");
        if (callback)
            callback(data["stdout"] || "", isNaN(exitCode) ? 1 : exitCode, data["stderr"] || "");
    }
}
