// voice/SttBackend.qml end to end through the real helper, run by tests/test_stt_qml.py
// (not by the main QML suite: it needs a fake recorder and a sandbox in the environment,
// so it never records from a real microphone).
import QtQuick
import QtTest
import "../../../org.kde.plasma.kdeaichat/contents/ui/voice" as Voice

TestCase {
    id: testCase
    name: "SttDictation"

    readonly property string fakeStt: decodeURIComponent(String(Qt.resolvedUrl("../../../build/stt-qml/fake-stt")).replace(/^file:\/\//, ""))
    property var replies: []
    property var config: null

    // Like plasmoid.configuration (a QObject): writes stick.
    Component {
        id: configComponent
        QtObject {
            property var voiceEnabled
            property var voiceSttModel
            property var voiceSttModelPath
            property var voiceLanguage
            property var voiceGpuEnabled
            property var sttSettingsMigrated
            property var sttEnabled
            property var sttEngine
            property var sttModel
            property var sttDevice
            property var sttLanguage
            property var sttCommand
            property var sttWhisperCppBinary
            property var sttWhisperCppModel
            property var sttWhisperCppServer
            property var sttRemoteUrl
            property var sttRemoteModel
            property var sttIdleMinutes
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
            "voiceEnabled": true, "voiceSttModel": "base", "voiceLanguage": "de", "voiceGpuEnabled": false,
            "sttSettingsMigrated": false, "sttEngine": "command", "sttCommand": fakeStt + " {wav} {lang}"});
        var backend = createTemporaryObject(backendComponent, testCase, {"configuration": config});
        // The old settings were carried over once, at start.
        compare(config.sttSettingsMigrated, true);
        compare(config.sttEnabled, true);
        compare(config.sttModel, "base");
        compare(config.sttLanguage, "de");

        backend.start();
        verify(backend.busy);
        wait(800);
        backend.stop(false);
        tryVerify(function() { return testCase.replies.length === 1; }, 15000);
        var reply = replies[0];
        compare(reply.type, "stt_result", JSON.stringify(reply));
        compare(reply.text, "fake heard de");
        compare(reply.engine, "command");
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
