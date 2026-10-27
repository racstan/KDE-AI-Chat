// Dictation through Speech Note (the dsnote app): the helper's speechnote_*
// commands start and stop its listening; the text arrives once, after the
// stop. While listening a timer keeps the task alive (Speech Note cancels a
// task that is quiet for 10 s). Used by SttBackend.qml, which relays
// reply({"type": "stt_result"|"stt_error"|"stt_stopped", ...}) and status(text).
//
// `runHelper(command, payload, callback(stdout, exitCode, stderr))` is
// store/HelperRunner.qml's run(); tests pass a fake.
import QtQuick
import "SpeechNote.js" as SpeechNote

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Item {
    id: dictation

    property var configuration: null
    property var runHelper: null
    property int keepAliveMs: SpeechNote.KEEPALIVE_MS
    // "" | "starting" | "listening" | "stopping"
    property string phase: ""
    readonly property bool busy: phase !== ""

    signal reply(var data)
    signal status(string text)

    property int _task: -1
    property int _generation: 0
    property string _pending: ""      // "stop": asked to stop while Speech Note was still starting

    function _model() {
        return String((configuration && configuration.sttSpeechNoteModel) || "");
    }

    function _call(command, payload, done) {
        if (!runHelper) {
            if (done)
                done(SpeechNote.parse("", 1, ""));
            return;
        }
        runHelper(command, payload, function(stdout, exitCode, stderr) {
            if (done)
                done(SpeechNote.parse(stdout, exitCode, stderr));
        });
    }

    function _fail(result) {
        keepAlive.stop();
        phase = "";
        _task = -1;
        _pending = "";
        reply({"type": "stt_error", "engine": "speechnote", "code": result.code || "bus_error",
               "error": i18n(SpeechNote.errorText(result.code))});
    }

    function start() {
        if (busy)
            return;
        phase = "starting";
        _pending = "";
        var generation = ++_generation;
        status(i18n("Starting Speech Note… please wait"));
        _call("speechnote_listen_start", {"model": _model()}, function(result) {
            if (generation !== dictation._generation) {   // cancelled meanwhile: give the microphone back
                if (!SpeechNote.isError(result) && result.task !== undefined)
                    dictation._call("speechnote_listen_cancel", {"task": result.task}, null);
                return;
            }
            if (SpeechNote.isError(result) || result.task === undefined) {
                dictation._fail(result);
                return;
            }
            dictation._task = result.task;
            dictation.phase = "listening";
            dictation.status(i18n("Listening — speak now"));
            keepAlive.restart();
            if (dictation._pending === "stop")
                dictation.stop(false);
        });
    }

    // cancel: drop what was said (Esc); otherwise transcribe it.
    function stop(cancel) {
        if (phase === "starting") {
            if (cancel === true) {
                _generation++;
                phase = "";
                reply({"type": "stt_stopped", "engine": "speechnote"});
            } else {
                _pending = "stop";
            }
            return;
        }
        if (phase !== "listening")
            return;
        keepAlive.stop();
        var task = _task;
        _task = -1;
        if (cancel === true) {
            phase = "";
            _call("speechnote_listen_cancel", {"task": task}, null);
            reply({"type": "stt_stopped", "engine": "speechnote"});
            return;
        }
        phase = "stopping";
        _call("speechnote_listen_stop", {"task": task}, function(result) {
            dictation.phase = "";
            if (SpeechNote.isError(result))
                dictation._fail(result);
            else
                dictation.reply({"type": "stt_result", "engine": "speechnote", "text": String(result.text || "").trim(),
                                 "lang": result.lang || ""});
        });
    }

    Timer {
        id: keepAlive
        interval: dictation.keepAliveMs
        repeat: true
        onTriggered: {
            var task = dictation._task;
            dictation._call("speechnote_keepalive", {"task": task}, function(result) {
                // Speech Note ended the task (or went away): there is nothing left to stop.
                if (result.type === "speechnote_keepalive" && result.alive === false
                        && dictation.phase === "listening" && dictation._task === task)
                    dictation._fail({"code": "bus_error"});
            });
        }
    }
}
