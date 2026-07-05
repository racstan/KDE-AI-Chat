import QtQuick
import org.kde.plasma.plasma5support 2.0 as P5Support
import "Security.js" as Sec

Item {
    id: root

    property bool isRecording: false
    property bool isPlaying: false
    property string statusText: ""
    property string lastRecognizedText: ""
    
    // Config aliases for convenience
    property bool enabled: plasmoid.configuration.voiceEnabled || false
    property bool autoSend: plasmoid.configuration.voiceAutoSend !== undefined ? plasmoid.configuration.voiceAutoSend : true
    property bool ttsAuto: plasmoid.configuration.voiceTtsAuto || false
    onTtsAutoChanged: plasmoid.configuration.voiceTtsAuto = ttsAuto
    
    signal textRecognized(string text)
    signal errorOccurred(string errorText)
    signal envChecked(var result)
    signal setupStatus(string status)

    P5Support.DataSource {
        id: voiceDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = (data["stdout"] || "").trim();
            disconnectSource(sourceName);
            if (stdout === "") return;
            let lines = stdout.split("\n");
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                if (!line) continue;
                try {
                    let resp = JSON.parse(line);
                    handleResponse(resp, sourceName);
                } catch (e) {}
            }
        }
    }

    function handleResponse(resp, sourceName) {
        if (resp.type === "env_check") {
            root.envChecked(resp);
        } else if (resp.type === "setup_status") {
            root.setupStatus(resp.status);
        } else if (resp.type === "stt_result") {
            root.isRecording = false;
            root.statusText = "";
            root.lastRecognizedText = resp.text || "";
            if (root.lastRecognizedText) {
                root.textRecognized(root.lastRecognizedText);
            }
        } else if (resp.type === "stt_error") {
            root.isRecording = false;
            root.statusText = "";
            root.errorOccurred(resp.error || "Unknown STT error");
        } else if (resp.type === "tts_done") {
            root.isPlaying = false;
        } else if (resp.type === "tts_error") {
            root.isPlaying = false;
            root.errorOccurred(resp.error || "Unknown TTS error");
        } else if (resp.type === "tts_status") {
            if (resp.status === "playing") root.isPlaying = true;
        }
    }

    function getVenvPython() {
        let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
        return venvPath + "/bin/python3";
    }

    function getHelperPath() {
        let base = Qt.resolvedUrl("./voice/voice_helper.py");
        if (base.indexOf("file://") === 0) base = base.substring(7);
        return base;
    }

    function sendCommand(payload) {
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let cmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payload) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payload) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
        voiceDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #voice-cmd-" + Date.now());
    }

    function checkEnv() {
        let sttPath = plasmoid.configuration.voiceSttModelPath || "";
        let ttsPath = plasmoid.configuration.voiceTtsModelPath || "";
        sendCommand(JSON.stringify({cmd: "check_env", stt_model_path: sttPath, tts_model_path: ttsPath}));
    }

    function runSetup() {
        let base = Qt.resolvedUrl("./voice/voice_setup.sh");
        if (base.indexOf("file://") === 0) base = base.substring(7);
        let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
        let cmd = "bash " + Sec.quoteForShell(base) + " " + Sec.quoteForShell(venvPath);
        voiceDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #voice-setup-" + Date.now());
    }

    function startRecording() {
        root.isRecording = true;
        root.statusText = "Recording...";
        let lang = plasmoid.configuration.voiceLanguage || "en";
        let model = plasmoid.configuration.voiceSttModel || "large-v3-turbo";
        let modelPath = plasmoid.configuration.voiceSttModelPath || "";
        sendCommand(JSON.stringify({cmd: "start_stt", duration: 0, language: lang, model: model, model_path: modelPath}));
    }

    function stopRecording() {
        root.statusText = "Processing...";
        sendCommand(JSON.stringify({cmd: "stop_stt"}));
    }

    function playTTS(text) {
        root.isPlaying = true;
        let voice = plasmoid.configuration.voiceTtsVoice || "af_heart";
        sendCommand(JSON.stringify({cmd: "tts", text: text, voice: voice, lang_code: "a"}));
    }

    function stopTTS() {
        sendCommand(JSON.stringify({cmd: "stop_tts"}));
        root.isPlaying = false;
    }
}
