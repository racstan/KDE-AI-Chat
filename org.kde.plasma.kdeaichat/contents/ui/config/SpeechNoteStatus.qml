// What Settings → Voice knows about Speech Note: installed or not, its models.
// refresh() asks the helper's speechnote_status with start:true (the model
// lists are empty unless Speech Note's service runs; it stops by itself
// after a minute idle). Nothing is changed in Speech Note.
//
// runHelper(command, payload, callback(stdout, exitCode, stderr)) is
// store/HelperRunner.qml's run(); tests pass a fake.
import QtQuick
import "../voice/SpeechNote.js" as SpeechNote

QtObject {
    id: status

    property var runHelper: null

    property bool loading: false
    property bool loaded: false
    property bool installed: false
    property string kind: ""            // "native" | "flatpak" | ""
    property var sttModels: []          // [{id, name, lang}]
    property var ttsModels: []
    // Why the models could not be listed (a helper error code), "" when fine.
    property string errorCode: ""
    property string errorMessage: ""

    property int _generation: 0

    function refresh() {
        if (loading)
            return;
        loading = true;
        errorCode = "";
        errorMessage = "";
        var generation = ++_generation;
        if (!runHelper) {
            _apply(SpeechNote.parse("", 1, ""));
            return;
        }
        runHelper("speechnote_status", {"start": true}, function(stdout, exitCode, stderr) {
            if (generation === status._generation)
                status._apply(SpeechNote.parse(stdout, exitCode, stderr));
        });
    }

    function _apply(reply) {
        loading = false;
        loaded = true;
        if (SpeechNote.isError(reply)) {
            // Not installed is an answer, not a failure; the others leave Speech Note installed but unusable.
            installed = reply.code !== "not_installed";
            kind = "";
            sttModels = [];
            ttsModels = [];
            errorCode = reply.code === "not_installed" ? "" : reply.code;
            errorMessage = reply.error || "";
            return;
        }
        installed = reply.installed === true;
        kind = String(reply.kind || "");
        sttModels = reply.stt_models || [];
        ttsModels = reply.tts_models || [];
    }
}
