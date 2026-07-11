import QtQuick
import org.kde.plasma.plasma5support 2.0 as P5Support
import "Security.js" as Sec

Item {
    id: root

    property bool isRecording: false
    property bool isPlaying: false
    property bool callModeActive: false
    property string playingText: ""
    property string currentPlayingChunk: ""
    property string statusText: ""
    property string lastRecognizedText: ""
    readonly property string defaultSttModel: "small"
    
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

    Timer {
        id: statusPoller
        interval: 300
        repeat: true
        running: root.isRecording || root.isPlaying
        onTriggered: {
            if (root.isRecording) {
                let xhr = new XMLHttpRequest();
                xhr.open("GET", "http://127.0.0.1:9015/status", true);
                xhr.onreadystatechange = function() {
                    if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                        try {
                            let resp = JSON.parse(xhr.responseText);
                            if (resp.status === "recording") {
                                root.statusText = "Recording... [" + (resp.stt_device ? resp.stt_device.toUpperCase() : "CPU") + "]";
                            } else if (resp.status === "transcribing") {
                                root.statusText = "Transcribing... [" + (resp.stt_device ? resp.stt_device.toUpperCase() : "CPU") + "]";
                            } else if (resp.status === "idle" && root.isRecording) {
                                // Likely finished or errored
                                if (resp.stt_result && resp.stt_result.type === "stt_result") {
                                    handleResponse(resp.stt_result, "http_poll");
                                } else if (resp.stt_result && resp.stt_result.type === "stt_error") {
                                    handleResponse(resp.stt_result, "http_poll");
                                }
                            }
                        } catch(e) {}
                    }
                }
                xhr.send();
            }
            if (root.isPlaying) {
                let xhr = new XMLHttpRequest();
                xhr.open("GET", "http://127.0.0.1:9016/status", true);
                xhr.onreadystatechange = function() {
                    if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                        try {
                            let resp = JSON.parse(xhr.responseText);
                            if (resp.status === "playing") {
                                if (resp.chunk) root.currentPlayingChunk = resp.chunk;
                                root.statusText = "Reading aloud...";
                            } else if (resp.status === "synthesizing") {
                                root.currentPlayingChunk = "";
                                root.statusText = "Generating speech...";
                            } else if (resp.status === "idle" && root.isPlaying) {
                                if (resp.tts_result && resp.tts_result.type === "tts_error") {
                                    handleResponse(resp.tts_result, "http_poll");
                                } else {
                                    root.isPlaying = false;
                                    root.currentPlayingChunk = "";
                                    root.statusText = "";
                                }
                            }
                        } catch(e) {}
                    }
                }
                xhr.send();
            }
        }
    }

    function handleResponse(resp, sourceName) {
        if (resp.type === "env_check") {
            root.envChecked(resp);
        } else if (resp.type === "setup_status") {
            root.setupStatus(resp.status);
        } else if (resp.type === "stt_status") {
            let devTag = resp.device ? " [" + resp.device.toUpperCase() + "]" : "";
            let callTag = root.callModeActive ? "[Beta] Call Mode - " : "";
            if (resp.status === "loading_model") root.statusText = callTag + "Loading model..." + devTag;
            else if (resp.status === "recording") root.statusText = callTag + "Listening..." + devTag;
            else if (resp.status === "transcribing") root.statusText = callTag + "Transcribing..." + devTag;
        } else if (resp.type === "stt_result") {
            if (!root.callModeActive) {
                root.isRecording = false;
                root.statusText = "";
            }
            root.lastRecognizedText = resp.text || "";
            if (root.lastRecognizedText) {
                root.textRecognized(root.lastRecognizedText);
            }
        } else if (resp.type === "stt_error") {
            root.isRecording = false;
            root.callModeActive = false;
            root.statusText = "";
            root.errorOccurred(resp.error || "Unknown STT error");
        } else if (resp.type === "tts_done") {
            root.isPlaying = false;
            root.currentPlayingChunk = "";
            root.statusText = "";
        } else if (resp.type === "tts_error") {
            root.isPlaying = false;
            root.currentPlayingChunk = "";
            root.statusText = "";
            root.errorOccurred(resp.error || "Unknown TTS error");
        } else if (resp.type === "tts_status") {
            if (resp.status === "playing") {
                root.isPlaying = true;
                root.statusText = "Reading aloud...";
                if (resp.chunk) {
                    root.currentPlayingChunk = resp.chunk;
                }
            } else if (resp.status === "synthesizing") {
                root.isPlaying = true;
                root.statusText = "Generating speech...";
            } else if (resp.status === "stopping") {
                root.statusText = "";
            } else if (resp.status === "paused") {
                root.statusText = "Paused";
            }
        } else if (resp.type === "tts_started") {
            root.isPlaying = true;
            root.statusText = "Generating speech...";
        } else if (resp.type === "stt_started") {
            root.isRecording = true;
        } else if (resp.type === "stt_stopped") {
            root.isRecording = false;
            root.callModeActive = false;
            root.statusText = "";
        } else if (resp.type === "tts_stopped") {
            root.isPlaying = false;
            root.currentPlayingChunk = "";
            root.statusText = "";
        }
    }

    function getVenvPython() {
        let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
        return venvPath + "/bin/python3";
    }

    function getHelperPath() {
        let base = String(Qt.resolvedUrl("./voice/voice_helper.py"));
        if (base.indexOf("file://") === 0) base = base.substring(7);
        return base;
    }

    function sendCommand(payload) {
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let safeVenvPy = venvPy.startsWith("~/") ? '"$HOME"' + Sec.quoteForShell(venvPy.substring(1)) : Sec.quoteForShell(venvPy);
        let cmd = "if [ -f " + safeVenvPy + " ]; then " + safeVenvPy + " " + Sec.quoteForShell(helperPath) + " --command-json " + Sec.quoteForShell(payload) + "; else python3 " + Sec.quoteForShell(helperPath) + " --command-json " + Sec.quoteForShell(payload) + "; fi";
        voiceDs.connectSource("timeout 90s sh -c " + Sec.rawShellSnippetQuote(cmd) + " #voice-cmd-" + Date.now());
    }

    function sendHttpCommand(payload, port) {
        let xhr = new XMLHttpRequest();
        xhr.open("POST", "http://127.0.0.1:" + port + "/command", true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.timeout = 300000; // 5 mins max
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        let resp = JSON.parse(xhr.responseText);
                        handleResponse(resp, "http");
                    } catch (e) {}
                } else {
                    sendCommand(payload);
                }
            }
        }
        try {
            xhr.send(payload);
        } catch (e) {
            sendCommand(payload);
        }
    }

    function checkEnv() {
        let sttPath = plasmoid.configuration.voiceSttModelPath || "";
        let ttsPath = plasmoid.configuration.voiceTtsModelPath || "";
        sendCommand(JSON.stringify({
            cmd: "check_env", 
            stt_model_path: sttPath, 
            tts_model_path: ttsPath, 
            venv_path: plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv", 
            espeak_path: plasmoid.configuration.voiceEspeakPath || "",
            gpu_requested: plasmoid.configuration.voiceGpuEnabled || false
        }));
    }

    function runSetup() {
        let base = String(Qt.resolvedUrl("./voice/venv_setup.sh"));
        if (base.indexOf("file://") === 0) base = base.substring(7);
        let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
        let cmd = "NON_INTERACTIVE=1 bash " + Sec.quoteForShell(base) + " " + Sec.quoteForShell(venvPath);
        voiceDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #voice-setup-" + Date.now());
    }

    function startRecording() {
        if (root.callModeActive) {
            root.stopCallMode();
        }
        root.isRecording = true;
        root.statusText = "Recording...";
        let lang = plasmoid.configuration.voiceLanguage || "en";
        let model = plasmoid.configuration.voiceSttModel || root.defaultSttModel;
        let modelPath = plasmoid.configuration.voiceSttModelPath || "";
        let gpuReq = plasmoid.configuration.voiceGpuEnabled || false;
        sendHttpCommand(JSON.stringify({cmd: "start_stt", duration: 0, language: lang, model: model, model_path: modelPath, gpu_requested: gpuReq}), 9015);
    }

    function stopRecording() {
        root.statusText = "Processing...";
        sendHttpCommand(JSON.stringify({cmd: "stop_stt"}), 9015);
    }

    function startCallMode() {
        if (root.isRecording) {
            root.stopRecording();
        }
        if (root.isPlaying) {
            root.stopTTS();
        }
        root.callModeActive = true;
        root.isRecording = true;
        root.statusText = "[Beta] Call Mode - Connecting...";
        
        let lang = plasmoid.configuration.voiceLanguage || "en";
        let model = plasmoid.configuration.voiceSttModel || root.defaultSttModel;
        let modelPath = plasmoid.configuration.voiceSttModelPath || "";
        let gpuReq = plasmoid.configuration.voiceGpuEnabled || false;
        sendHttpCommand(JSON.stringify({
            cmd: "start_stt",
            is_call_mode: true,
            duration: 0,
            language: lang,
            model: model,
            model_path: modelPath,
            gpu_requested: gpuReq
        }), 9015);
    }

    function stopCallMode() {
        root.callModeActive = false;
        root.statusText = "Ending call...";
        if (root.isPlaying) {
            root.stopTTS();
        }
        sendHttpCommand(JSON.stringify({cmd: "stop_stt"}), 9015);
    }

    function playTTS(text) {
        root.isPlaying = true;
        root.playingText = text;
        let voice = plasmoid.configuration.voiceTtsVoice || "";
        let modelPath = plasmoid.configuration.voiceTtsModelPath || "";
        let espeakPath = plasmoid.configuration.voiceEspeakPath || "";
        let gpuReq = plasmoid.configuration.voiceGpuEnabled || false;
        sendHttpCommand(JSON.stringify({cmd: "tts", text: text, voice: voice, lang_code: "a", model_path: modelPath, espeak_path: espeakPath, gpu_requested: gpuReq}), 9016);
    }

    function stopTTS() {
        sendHttpCommand(JSON.stringify({cmd: "stop_tts"}), 9016);
        root.isPlaying = false;
        root.playingText = "";
    }
}
