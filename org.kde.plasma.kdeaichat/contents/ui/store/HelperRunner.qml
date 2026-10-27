// Runs kde_ai_helper.py commands and calls back with their output.
//
// run("prepare_chat_dir", {...}, function(stdout, exitCode, stderr) {...})
// Arguments are visible in the process list, so by default every payload goes
// in a file in the private runtime folder ($XDG_RUNTIME_DIR, 0700) and only
// "@<file name>" is on the command line; the helper reads and deletes it.
// Only the tiny commands in `argvCommands` (status checks and the like, whose
// payload is empty or a folder path) pass it base64-encoded as one argument.
// Never put secrets in a payload at all.
import QtQuick
import QtCore
import org.kde.plasma.plasma5support as P5Support
import "../Security.js" as Sec

P5Support.DataSource {
    id: runner
    engine: "executable"
    connectedSources: []

    property string helperPath: ""
    property var _callbacks: ({})
    property int _counter: 0
    // Commands with no private text in their payload; everything else is private.
    property var argvCommands: ["desktop_status", "storage_usage", "local_servers_scan", "ask_inbox_take",
                                "read_legacy_keyfile", "remove_legacy_keyfile", "prepare_chat_dir",
                                "speechnote_status", "get_pi_models"]
    // Tests: where private payload files go (default: the runtime folder).
    property string privateDir: {
        var dir = String(StandardPaths.writableLocation(StandardPaths.RuntimeLocation) || "");
        return dir.replace(/^file:\/\//, "");
    }

    property Component payloadFile: Component { Settings {} }

    // Writes the payload to <privateDir>/kdeaichat-payload-<n>.ini; returns "@<name>", or "" on failure.
    function _writePrivate(encoded, token) {
        if (!privateDir)
            return "";
        var name = "kdeaichat-payload-" + token.replace(/[^0-9a-z]/gi, "-").replace(/^-+/, "") + ".ini";
        var file = payloadFile.createObject(null, {"location": "file://" + privateDir + "/" + name});
        if (!file)
            return "";
        file.setValue("payload", encoded.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")); // qmllint disable missing-property
        file.sync(); // qmllint disable missing-property
        file.destroy();
        return "@" + name;
    }

    function run(command, payload, onDone) {
        if (!helperPath || !/^[a-z_]{1,64}$/.test(command)) {
            if (onDone) onDone("", 1, "helper unavailable");
            return;
        }
        var token = "#helper-" + (++_counter) + "-" + Date.now();
        if (onDone)
            _callbacks[token] = onDone;
        var encoded = Sec.base64Encode(JSON.stringify(payload || {}));
        var isPrivate = argvCommands.indexOf(command) < 0;
        var argument = isPrivate ? _writePrivate(encoded, token) : "";
        if (isPrivate && !argument) {
            if (onDone) onDone("", 1, "no private folder for the payload");
            delete _callbacks[token];
            return;
        }
        connectSource("python3 " + Sec.quoteForShell(helperPath) + " " + command + " "
            + Sec.rawShellSnippetQuote(argument || encoded) + " " + token);
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
