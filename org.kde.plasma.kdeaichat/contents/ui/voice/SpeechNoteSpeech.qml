// Reads aloud through Speech Note (the dsnote app): the whole reply goes to
// it in one request (its text is a private payload file, see
// store/HelperRunner.qml) and Speech Note splits the sentences and plays
// them itself. `speechnote_wait_spoken` returns when the speech is over, or
// when it starts a sentence (then it is called again), and keeps the task alive. Same API as voice/FileSpeech.qml.
//
// Pause, resume and stop are separate helper calls, so the wait runs on its
// own runner (`waitHelper`, empty: made here); tests pass fakes for both.
import QtQuick
import "../store" as Store
import "SpeechNote.js" as SpeechNote

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Item {
    id: speech

    property string engine: "speechnote"
    property var runHelper: null
    property var waitHelper: null
    readonly property var _wait: waitHelper || waitRunner.run
    readonly property bool canPause: true

    signal chunkStarted(string text)
    signal finished()
    signal failed(string message, string code)

    property int _generation: 0
    property int _task: -1

    function _call(run, command, payload, done) {
        if (!run) {
            if (done)
                done(SpeechNote.parse("", 1, ""));
            return;
        }
        run(command, payload, function(stdout, exitCode, stderr) {
            if (done)
                done(SpeechNote.parse(stdout, exitCode, stderr));
        });
    }

    function _fail(result) {
        _task = -1;
        failed(i18n(SpeechNote.errorText(result.code)), result.code || "bus_error");
    }

    function start(chunks, settings) {
        stop();
        var generation = _generation;
        var model = String((settings && settings.voiceTtsSpeechNoteModel) || "");
        _call(runHelper, "speechnote_speak", {"text": chunks.join("\n"), "model": model}, function(result) {
            if (generation !== speech._generation) {   // stopped meanwhile
                if (!SpeechNote.isError(result) && result.task !== undefined)
                    speech._call(speech.runHelper, "speechnote_stop", {"task": result.task}, null);
                return;
            }
            if (SpeechNote.isError(result) || result.task === undefined) {
                speech._fail(result);
                return;
            }
            speech._task = result.task;
            speech.chunkStarted("");
            speech._waitSpoken(generation, result.task);
        });
    }

    // Until the speech is over; each sentence Speech Note starts reading ends
    // a wait early (chunkStarted with it, for the highlight) and it waits again.
    function _waitSpoken(generation, task) {
        _call(_wait, "speechnote_wait_spoken", {"task": task, "sentences": true}, function(done) {
            if (generation !== speech._generation)
                return;
            if (done.type === "speechnote_sentence") {
                speech.chunkStarted(String(done.text || ""));
                speech._waitSpoken(generation, task);
                return;
            }
            speech._task = -1;
            if (SpeechNote.isError(done) && done.code !== "timeout")
                speech._fail(done);
            else
                speech.finished();
        });
    }

    function stop() {
        _generation++;
        if (_task >= 0)
            _call(runHelper, "speechnote_stop", {"task": _task}, null);
        _task = -1;
    }

    function pause() { if (_task >= 0) _call(runHelper, "speechnote_pause", {"task": _task}, null); }
    function resume() { if (_task >= 0) _call(runHelper, "speechnote_resume", {"task": _task}, null); }

    Store.HelperRunner {
        id: waitRunner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("../kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }
}
