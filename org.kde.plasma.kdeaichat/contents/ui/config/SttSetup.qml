// Settings → Voice, dictation with a speech server: the Test button's work.
// It runs the helper's stt_test (kdeaichat/stt_commands.py), which sends the
// recording that comes with the widget to the server with the page's unsaved
// choices as the payload. Nothing is installed or downloaded.
//
// runHelper(command, payload, callback(stdout, exitCode, stderr)) is
// store/HelperRunner.qml's run(); tests pass a fake.
import QtQuick

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

QtObject {
    id: setup

    property var runHelper: null
    // The stt* settings as they are on the page (voice/SttConfig.js payload()).
    property var payload: ({})

    property bool testing: false
    property string testResult: ""

    function _reply(stdout) {
        var lines = String(stdout || "").trim().split("\n");
        for (var i = lines.length - 1; i >= 0; i--) {
            try {
                var data = JSON.parse(lines[i]);
                if (data && typeof data === "object")
                    return data;
            } catch (e) {}
        }
        return null;
    }

    // Transcribes the bundled sample with the page's choices (no microphone).
    function test() {
        if (testing)
            return;
        if (!runHelper) {
            testResult = i18n("The test failed: %1", i18n("The helper is not available."));
            return;
        }
        testing = true;
        testResult = i18n("Transcribing a sample recording…");
        runHelper("stt_test", payload, function(stdout, exitCode, stderr) {
            setup.testing = false;
            var r = setup._reply(stdout);
            if (r && r.type === "stt_result")
                setup.testResult = r.text ? i18n("Heard: “%1” (%2 s)", r.text, r.seconds) : i18n("No speech heard.");
            else
                setup.testResult = i18n("The test failed: %1", (r && r.error) || String(stderr || "").trim().split("\n").pop() || i18n("No answer."));
        });
    }
}
