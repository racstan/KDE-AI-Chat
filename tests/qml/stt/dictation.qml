// voice/SttBackend.qml end to end through the real helper, run by tests/test_stt_qml.py
// (not by the main QML suite: it needs a fake recorder, a fake speech server and a sandbox in the
// environment, so it never records from a real microphone). The speech server engine records with the
// helper and posts the recording to the server (build/stt-qml/server.js has its port).
import QtQuick
import QtTest
import "../../../org.kde.plasma.kdeaichat/contents/ui/voice" as Voice
import "../../../build/stt-qml/server.js" as Server

TestCase {
    id: testCase
    name: "SttDictation"

    property var replies: []
    property var config: null

    // Like plasmoid.configuration (a QObject): writes stick.
    Component {
        id: configComponent
        QtObject {
            property var voiceEnabled
            property var voiceLanguage
            property var sttSettingsMigrated
            property var sttEnabled
            property var sttEngine
            property var sttLanguage
            property var sttRemoteUrl
            property var sttRemoteModel
        }
    }

    Component {
        id: backendComponent
        Voice.SttBackend {
            onReply: function(data) { testCase.replies = testCase.replies.concat([data]); }
        }
    }

    function test_migration_then_dictate_until_stop() {
        config = createTemporaryObject(configComponent, testCase, {
            "voiceEnabled": true, "voiceLanguage": "de", "sttSettingsMigrated": false, "sttEngine": "faster-whisper"});
        var backend = createTemporaryObject(backendComponent, testCase, {"configuration": config});
        // The old settings were carried over once, at start; an engine that no longer exists became Speech Note.
        compare(config.sttSettingsMigrated, true);
        compare(config.sttEnabled, true);
        compare(config.sttLanguage, "de");
        compare(config.sttEngine, "speechnote");
        compare(backend.engine, "speechnote");
        config.sttEngine = "remote";
        config.sttRemoteUrl = "http://127.0.0.1:" + Server.port + "/v1";

        backend.start();
        verify(backend.busy);
        wait(800);
        backend.stop(false);
        tryVerify(function() { return testCase.replies.length === 1; }, 15000);
        var reply = replies[0];
        compare(reply.type, "stt_result", JSON.stringify(reply));
        compare(reply.text, "fake heard de");
        compare(reply.engine, "remote");
        verify(reply.duration >= 0.3);
        verify(!backend.busy);

        // Cancel drops the recording.
        replies = [];
        backend.start();
        wait(500);
        backend.stop(true);
        tryVerify(function() { return testCase.replies.length === 1; }, 15000);
        compare(replies[0].type, "stt_stopped");
        compare(replies[0].cancelled, true);
    }
}
