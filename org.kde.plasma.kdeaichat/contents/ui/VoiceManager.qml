// Voice in the chat: dictation (voice/SttBackend.qml: the helper records and
// transcribes with the engine chosen in Settings → Voice) and read aloud
// (voice/ReadAloud.qml). Each has its own switch (sttEnabled,
// voiceTtsEnabled), both off by default; while off nothing runs.
//
// The chat uses: isRecording, startRecording(), stopRecording(),
// textRecognized(text); isPlaying, playingText, currentPlayingChunk, currentPlayingWordStart,
// cancelRecording(), playTTS(text), stopTTS(), pauseTTS(), resumeTTS(), ttsPaused, ttsCanPause;
// statusText; errorOccurred(text).
import QtQuick
import "voice" as Voice
import "voice/TtsEngines.js" as Engines

// i18n() and plasmoid are provided by Plasma at runtime.
// qmllint disable unqualified

Item {
    id: root

    property bool isRecording: false
    readonly property bool isPlaying: readAloud.isPlaying
    readonly property bool ttsPaused: readAloud.paused
    readonly property bool ttsCanPause: readAloud.canPause
    property string playingText: ""
    readonly property string currentPlayingChunk: readAloud.currentChunk
    readonly property int currentPlayingWordStart: readAloud.currentWordStart
    property string sttStatusText: ""
    readonly property string statusText: sttStatusText || readAloud.statusText
    property string lastRecognizedText: ""
    // store/HelperRunner.qml's run(), for the speech server and Speech Note.
    property var runHelper: null
    // The widget's popup is open (main.qml): Speech Note is warmed up and kept ready (voice/SpeechNoteWarm.qml).
    property bool popupOpen: false
    property var configuration: plasmoid.configuration
    // Title of the notification for errorOccurred (main.qml).
    readonly property string errorTitle: i18n("Voice error")
    // No call mode yet; ComposerStatus.qml and main.qml ask.
    readonly property bool callModeActive: false
    // Tests: e.g. {"system": "mock"} (Qt's mock speech engine).
    property alias ttsPluginOverride: readAloud.pluginOverride
    // Tests: the runner for Speech Note's wait-until-spoken call.
    property alias waitHelper: readAloud.waitHelper

    // Dictation switch (migrated once from the old voiceEnabled by SttConfig.js).
    readonly property bool sttEnabled: configuration.sttEnabled === true
    readonly property bool ttsEnabled: configuration.voiceTtsEnabled === true
    property bool autoSend: configuration.voiceAutoSend !== undefined ? configuration.voiceAutoSend : true
    property bool ttsAuto: configuration.voiceTtsAuto || false
    onTtsAutoChanged: configuration.voiceTtsAuto = ttsAuto
    // Read aloud switched off: stop it and unload the engine.
    onTtsEnabledChanged: if (!ttsEnabled) readAloud.unload()
    onSttEnabledChanged: {
        if (!sttEnabled && isRecording)
            sttBackend.stop(true);
    }

    // A read-aloud engine of an earlier build (Kokoro, Piper, a custom command, ...) becomes Speech Note.
    Component.onCompleted: {
        var engine = Engines.migratedEngine(configuration.voiceTtsEngine);
        if (configuration.voiceTtsEngine !== undefined && configuration.voiceTtsEngine !== engine)
            configuration.voiceTtsEngine = engine;
    }

    signal textRecognized(string text)
    signal errorOccurred(string errorText)

    Voice.SpeechNoteWarm {
        configuration: root.configuration
        runHelper: root.runHelper
        popupOpen: root.popupOpen
    }

    Voice.ReadAloud {
        id: readAloud
        configuration: root.configuration
        runHelper: root.runHelper
        onError: function(message) { root.errorOccurred(message); }
        onIsPlayingChanged: if (!isPlaying) root.playingText = ""
    }

    // Dictation: the helper records and transcribes with the chosen engine.
    Voice.SttBackend {
        id: sttBackend
        configuration: root.configuration
        runHelper: root.runHelper
        onReply: function(data) { root.handleResponse(data); }
        onStatus: function(text) { if (root.isRecording) root.sttStatusText = text; }
    }

    function handleResponse(resp) {
        if (resp.type === "stt_result") {
            root.isRecording = false;
            root.sttStatusText = "";
            root.lastRecognizedText = resp.text || "";
            if (root.lastRecognizedText)
                root.textRecognized(root.lastRecognizedText);
        } else if (resp.type === "stt_error" || resp.type === "error") {
            root.isRecording = false;
            root.sttStatusText = "";
            root.errorOccurred(resp.error || i18n("Dictation failed."));
        } else if (resp.type === "stt_stopped") {
            root.isRecording = false;
            root.sttStatusText = "";
        }
    }

    function startRecording() {
        if (!root.sttEnabled)
            return;
        root.isRecording = true;
        root.sttStatusText = i18n("Listening…");
        sttBackend.start();
    }

    function stopRecording() {
        root.sttStatusText = i18n("Transcribing…");
        sttBackend.stop(false);
    }

    // Esc while recording: drop what was said.
    function cancelRecording() {
        if (!root.isRecording)
            return;
        sttBackend.stop(true);
        root.isRecording = false;
        root.sttStatusText = "";
    }

    // Read aloud (voice/ReadAloud.qml), the API the chat uses.
    function playTTS(text) {
        if (!root.ttsEnabled)
            return;
        if (readAloud.speak(text))
            root.playingText = text;
    }
    function stopTTS() {
        readAloud.stop();
        root.playingText = "";
    }
    function pauseTTS() { readAloud.pause(); }
    function resumeTTS() { readAloud.resume(); }
}
