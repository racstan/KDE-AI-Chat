// A dictation failure reaches the user: VoiceManager turns the helper's
// stt_error into errorOccurred, and the widget shows it as a "Voice error"
// desktop notification through chat/Notifier.qml (the same wiring as
// main.qml, whose text tests/test_stt_parakeet.py checks). Before this the
// handler called a data source that no longer existed, so nothing was shown.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui" as Ui
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 200
    height: 100

    property QtObject plasmoid: QtObject {
        property QtObject configuration: QtObject {
            property bool sttEnabled: true
            property bool voiceTtsEnabled: false
            property bool voiceAutoSend: true
        }
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    property var shown: []

    Chat.Notifier {
        id: notifier
        sender: function(title, text, chatId, isError) {
            root.shown.push({"title": title, "text": text, "chatId": chatId, "isError": isError});
        }
    }

    Ui.VoiceManager {
        id: voice
        onErrorOccurred: function(errorText) {
            notifier.sender(voice.errorTitle, errorText || voice.errorTitle, "", true);
        }
    }

    HarnessTestCase {
        name: "VoiceError"

        // Lets the dictation back end's start-up helper command finish before the runner quits.
        function cleanupTestCase() { wait(2000); }

        function test_dictation_error_is_notified() {
            voice.isRecording = true;
            voice.handleResponse({"type": "stt_error", "code": "model_missing",
                                  "error": "The Parakeet model is not downloaded yet (731 MB). Download it in Settings → Voice."});
            compare(voice.isRecording, false);
            compare(root.shown.length, 1);
            compare(root.shown[0].title, "Voice error");
            verify(root.shown[0].text.indexOf("731 MB") >= 0, root.shown[0].text);
            compare(root.shown[0].isError, true);
            voice.handleResponse({"type": "stt_error"});
            compare(root.shown[1].text, "Dictation failed.");
        }
    }
}
