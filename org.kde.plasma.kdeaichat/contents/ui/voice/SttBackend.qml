// Dictation back end for VoiceManager: records and transcribes through the
// helper's stt_* commands (kdeaichat/stt_commands.py) with the chosen engine.
//
// start(): `stt_dictate` records until stop() and prints one result when it
// ends, so the reply arrives once (no polling). At start it copies the old
// voice* settings once and runs `stt_sync_units`, which removes the old
// always-on service and keeps the on-demand faster-whisper socket installed
// only while dictation is on with that engine.
import QtQuick
import "../store" as Store
import "SttConfig.js" as SttConfig

Item {
    id: stt

    property var configuration: null
    readonly property bool busy: _dictating
    property bool _dictating: false

    // One reply object: {"type": "stt_result"|"stt_error"|"stt_stopped", ...}
    signal reply(var data)

    function _parse(stdout, exitCode, stderr) {
        var lines = String(stdout || "").trim().split("\n");
        for (var i = lines.length - 1; i >= 0; i--) {
            try {
                var data = JSON.parse(lines[i]);
                if (data && data.type)
                    return data;
            } catch (e) {}
        }
        return {"type": "stt_error", "error": String(stderr || stdout || "Speech-to-text failed").trim().slice(-300)};
    }

    function start() {
        if (_dictating)
            return;
        _dictating = true;
        runner.run("stt_dictate", SttConfig.payload(configuration), function(stdout, exitCode, stderr) {
            stt._dictating = false;
            stt.reply(stt._parse(stdout, exitCode, stderr));
        });
    }

    function stop(cancel) {
        runner.run("stt_stop", {"cancel": cancel === true}, null);
    }

    function syncUnits() {
        if (!configuration)
            return;
        SttConfig.applyMigration(configuration);
        runner.run("stt_sync_units", SttConfig.payload(configuration), null);
    }

    Component.onCompleted: syncUnits()

    Store.HelperRunner {
        id: runner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("../kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }
}
