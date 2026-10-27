// Dictation back end for VoiceManager. With the Speech Note engine (the default)
// the app does the listening: voice/SpeechNoteDictation.qml. With a speech
// server the helper records and transcribes through its stt_* commands
// (kdeaichat/stt_commands.py): `stt_dictate` records until stop() and prints
// one result when it ends, so the reply arrives once (no polling).
// At start it carries older settings over once (voice/SttConfig.js): a saved
// engine that no longer exists (faster-whisper, Parakeet, whisper.cpp, a custom
// command) becomes Speech Note.
import QtQuick
import "../store" as Store
import "SttConfig.js" as SttConfig

Item {
    id: stt

    property var configuration: null
    // store/HelperRunner.qml's run(); empty: this backend's own runner.
    property var runHelper: null
    readonly property var _run: runHelper || runner.run
    readonly property string engine: SttConfig.migratedEngine(configuration ? configuration.sttEngine : "")
    readonly property bool busy: _dictating || speechNote.busy
    property bool _dictating: false
    property bool _viaSpeechNote: false

    // "Starting Speech Note…", "Listening…": what the chat's status line says.
    signal status(string text)

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
        if (busy)
            return;
        _viaSpeechNote = engine === "speechnote";
        if (_viaSpeechNote) {
            speechNote.start();
            return;
        }
        _dictating = true;
        runner.run("stt_dictate", SttConfig.payload(configuration), function(stdout, exitCode, stderr) {
            stt._dictating = false;
            stt.reply(stt._parse(stdout, exitCode, stderr));
        });
    }

    function stop(cancel) {
        if (_viaSpeechNote) {
            speechNote.stop(cancel === true);
            return;
        }
        runner.run("stt_stop", {"cancel": cancel === true}, null);
    }

    function migrate() {
        if (configuration)
            SttConfig.applyMigration(configuration);
    }

    Component.onCompleted: migrate()

    SpeechNoteDictation {
        id: speechNote
        configuration: stt.configuration
        runHelper: stt._run
        onReply: function(data) { stt.reply(data); }
        onStatus: function(text) { stt.status(text); }
    }

    Store.HelperRunner {
        id: runner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("../kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }
}
