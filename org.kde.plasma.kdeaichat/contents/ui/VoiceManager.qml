// Voice in the chat: dictation (speech-to-text through the local STT service,
// which Phase 6 is rebuilding) and read aloud (voice/ReadAloud.qml, with the
// engine chosen in Settings → Voice).
//
// The chat uses: isRecording, startRecording(), stopRecording(),
// textRecognized(text); isPlaying, playingText, currentPlayingChunk,
// playTTS(text), stopTTS(), pauseTTS(), resumeTTS(), ttsPaused, ttsCanPause;
// statusText; errorOccurred(text).
import QtQuick
import org.kde.plasma.plasma5support 2.0 as P5Support
import "Security.js" as Sec
import "voice" as Voice

Item {
    id: root

    property bool isRecording: false
    readonly property bool isPlaying: readAloud.isPlaying
    readonly property bool ttsPaused: readAloud.paused
    readonly property bool ttsCanPause: readAloud.canPause
    property string playingText: ""
    readonly property string currentPlayingChunk: readAloud.currentChunk
    property string sttStatusText: ""
    readonly property string statusText: sttStatusText || readAloud.statusText
    property string lastRecognizedText: ""
    readonly property string defaultSttModel: "small"
    property string httpToken: ""
    property bool httpTokenRequestInProgress: false
    property string httpTokenRequestSource: ""
    property var pendingHttpCommands: []
    property var sttStatusXhr: null
    // store/HelperRunner.qml's run(), for the read-aloud engines that write files.
    property var runHelper: null
    property var configuration: plasmoid.configuration
    // Title of the notification for errorOccurred (main.qml).
    readonly property string errorTitle: i18n("Voice error")
    // No call mode yet; ComposerStatus.qml and main.qml ask.
    readonly property bool callModeActive: false
    // Tests: e.g. {"system": "mock"} (Qt's mock speech engine).
    property alias ttsPluginOverride: readAloud.pluginOverride

    property bool enabled: configuration.voiceEnabled || false
    property bool ttsEnabled: configuration.voiceTtsEnabled === true
    property bool autoSend: configuration.voiceAutoSend !== undefined ? configuration.voiceAutoSend : true
    property bool ttsAuto: configuration.voiceTtsAuto || false
    onTtsAutoChanged: configuration.voiceTtsAuto = ttsAuto
    // Read aloud switched off: stop it and unload the engine.
    onTtsEnabledChanged: if (!ttsEnabled) readAloud.unload()

    signal textRecognized(string text)
    signal errorOccurred(string errorText)
    signal envChecked(var result)
    signal setupStatus(string status)

    Voice.ReadAloud {
        id: readAloud
        configuration: root.configuration
        runHelper: root.runHelper
        onError: function(message) { root.errorOccurred(message); }
        onIsPlayingChanged: if (!isPlaying) root.playingText = ""
    }

    Component.onCompleted: {
        if (!root.enabled) {
            let killCmd = "systemctl --user disable --now kde-ai-stt.service 2>/dev/null; pkill -f 'voice_helper.py --stt-server' 2>/dev/null";
            voiceDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(killCmd) + " #startup-sync-voice-off-" + Date.now());
        }
    }

    Component.onDestruction: {
        try { if (root.sttStatusXhr) root.sttStatusXhr.abort(); } catch (e) {}
    }

    readonly property alias voiceDs: voiceDs

    P5Support.DataSource {
        id: voiceDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = (data["stdout"] || "").trim();
            disconnectSource(sourceName);
            if (stdout === "") {
                if (sourceName === root.httpTokenRequestSource)
                    root._fallbackPendingHttpCommands();
                return;
            }
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
        running: root.isRecording
        onTriggered: {
            if (root.sttStatusXhr)
                return;
            let xhr = new XMLHttpRequest();
            root.sttStatusXhr = xhr;
            xhr.open("GET", "http://127.0.0.1:9015/status", true);
            if (root.httpToken)
                xhr.setRequestHeader("X-KDE-AI-Chat-Token", root.httpToken);
            xhr.timeout = 2000;
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return;
                if (root.sttStatusXhr === xhr) root.sttStatusXhr = null;
                if (xhr.status === 200) {
                    try {
                        let resp = JSON.parse(xhr.responseText);
                        let device = " [" + (resp.stt_device ? resp.stt_device.toUpperCase() : "CPU") + "]";
                        if (resp.status === "recording") {
                            root.sttStatusText = "Recording..." + device;
                        } else if (resp.status === "transcribing") {
                            root.sttStatusText = "Transcribing..." + device;
                        } else if (resp.status === "idle" && root.isRecording) {
                            // Likely finished or errored
                            if (resp.stt_result && (resp.stt_result.type === "stt_result" || resp.stt_result.type === "stt_error"))
                                handleResponse(resp.stt_result, "http_poll");
                        }
                    } catch(e) {}
                } else if (xhr.status === 401 || xhr.status === 403) {
                    root.httpToken = "";
                    root._requestHttpToken();
                }
            };
            xhr.ontimeout = function() { if (root.sttStatusXhr === xhr) root.sttStatusXhr = null; };
            xhr.onerror = function() { if (root.sttStatusXhr === xhr) root.sttStatusXhr = null; };
            try { xhr.send(); } catch (e) { if (root.sttStatusXhr === xhr) root.sttStatusXhr = null; }
        }
    }

    Timer {
        id: retryTimer
        interval: 2500
        repeat: false
        property var retryQueue: []
        onTriggered: {
            var queue = retryQueue || [];
            if (queue.length === 0)
                return;
            var item = queue.shift();
            retryQueue = queue;
            sendHttpCommand(item.payload, item.port, item.retries + 1);
            if (queue.length > 0)
                restart();
        }
    }

    function handleResponse(resp, sourceName) {
        if (resp.type === "voice_token") {
            if (sourceName !== root.httpTokenRequestSource)
                return;
            root.httpToken = String(resp.token || "");
            root.httpTokenRequestInProgress = false;
            root.httpTokenRequestSource = "";
            if (!root.httpToken) {
                root._fallbackPendingHttpCommands();
                return;
            }
            let queued = root.pendingHttpCommands || [];
            root.pendingHttpCommands = [];
            for (let i = 0; i < queued.length; i++)
                root._sendHttpCommandNow(queued[i].payload, queued[i].port, queued[i].retries);
        } else if (sourceName === root.httpTokenRequestSource) {
            root._fallbackPendingHttpCommands();
        } else if (resp.type === "env_check") {
            root.envChecked(resp);
        } else if (resp.type === "setup_status") {
            root.setupStatus(resp.status);
        } else if (resp.type === "stt_status") {
            let devTag = resp.device ? " [" + resp.device.toUpperCase() + "]" : "";
            if (resp.status === "loading_model") root.sttStatusText = "Loading model..." + devTag;
            else if (resp.status === "recording") root.sttStatusText = "Listening..." + devTag;
            else if (resp.status === "transcribing") root.sttStatusText = "Transcribing..." + devTag;
        } else if (resp.type === "stt_result") {
            root.isRecording = false;
            root.sttStatusText = "";
            root.lastRecognizedText = resp.text || "";
            if (root.lastRecognizedText)
                root.textRecognized(root.lastRecognizedText);
        } else if (resp.type === "stt_error" || resp.type === "error") {
            root.isRecording = false;
            root.sttStatusText = "";
            root.errorOccurred(resp.error || "Voice command failed");
        } else if (resp.type === "stt_started") {
            root.isRecording = true;
        } else if (resp.type === "stt_stopped") {
            root.isRecording = false;
            root.sttStatusText = "";
        }
    }

    function getVenvPython() {
        let venvPath = configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
        return venvPath + "/bin/python3";
    }

    function getHelperPath() {
        let base = String(Qt.resolvedUrl("./voice/voice_helper.py"));
        if (base.indexOf("file://") === 0) base = base.substring(7);
        return base.endsWith("/contents/ui/voice/voice_helper.py") ? base : "";
    }

    function sendCommand(payload, tag) {
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let encoded = Sec.base64Encode(payload || "");
        let safeVenvPy = venvPy.startsWith("~/") ? '"$HOME"' + Sec.quoteForShell(venvPy.substring(1)) : Sec.quoteForShell(venvPy);
        let encodedArg = Sec.rawShellSnippetQuote(encoded);
        let cmd = "if [ -f " + safeVenvPy + " ]; then " + safeVenvPy + " " + Sec.quoteForShell(helperPath) + " --command-b64 " + encodedArg + "; else python3 " + Sec.quoteForShell(helperPath) + " --command-b64 " + encodedArg + "; fi";
        let source = "timeout 90s sh -c " + Sec.rawShellSnippetQuote(cmd) + " #voice-" + (tag || "cmd") + "-" + Date.now();
        voiceDs.connectSource(source);
        return source;
    }

    function _fallbackPendingHttpCommands() {
        let queued = root.pendingHttpCommands || [];
        root.pendingHttpCommands = [];
        root.httpTokenRequestInProgress = false;
        root.httpTokenRequestSource = "";
        for (let i = 0; i < queued.length; i++)
            sendCommand(queued[i].payload);
    }

    function _requestHttpToken() {
        if (root.httpTokenRequestInProgress)
            return;
        root.httpTokenRequestInProgress = true;
        root.httpTokenRequestSource = sendCommand(JSON.stringify({cmd: "get_http_token"}), "token");
    }

    function _sendHttpCommandNow(payload, port, retries) {
        if (retries === undefined) retries = 0;
        let xhr = new XMLHttpRequest();
        let completed = false;
        let retryOrFallback = function() {
            if (completed) return;
            completed = true;
            if (retries < 2) {
                voiceDs.connectSource("systemctl --user start kde-ai-stt.service #start-" + Date.now());
                var retryQueue = retryTimer.retryQueue || [];
                retryQueue.push({"payload": payload, "port": port, "retries": retries});
                retryTimer.retryQueue = retryQueue;
                if (!retryTimer.running)
                    retryTimer.start();
            } else {
                sendCommand(payload);
            }
        };
        try {
            xhr.open("POST", "http://127.0.0.1:" + port + "/command", true);
            xhr.setRequestHeader("Content-Type", "application/json");
            xhr.setRequestHeader("X-KDE-AI-Chat-Token", root.httpToken);
            xhr.timeout = 300000; // 5 mins max
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE || completed)
                    return;
                if (xhr.status === 200) {
                    completed = true;
                    try {
                        let resp = JSON.parse(xhr.responseText);
                        handleResponse(resp, "http");
                    } catch (e) {}
                } else if (xhr.status === 401 || xhr.status === 403) {
                    completed = true;
                    root.httpToken = "";
                    root.pendingHttpCommands = (root.pendingHttpCommands || []).concat([{"payload": payload, "port": port, "retries": retries}]);
                    _requestHttpToken();
                } else {
                    retryOrFallback();
                }
            };
            xhr.ontimeout = retryOrFallback;
            xhr.onerror = retryOrFallback;
            xhr.send(payload);
        } catch (e) {
            retryOrFallback();
        }
    }

    function sendHttpCommand(payload, port, retries) {
        if (!root.httpToken) {
            root.pendingHttpCommands = (root.pendingHttpCommands || []).concat([{"payload": payload, "port": port, "retries": retries === undefined ? 0 : retries}]);
            _requestHttpToken();
            return;
        }
        _sendHttpCommandNow(payload, port, retries);
    }

    function checkEnv() {
        sendCommand(JSON.stringify({
            cmd: "check_env",
            stt_model_path: configuration.voiceSttModelPath || "",
            tts_model_path: "",
            venv_path: configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv",
            espeak_path: configuration.voiceEspeakPath || "",
            gpu_requested: configuration.voiceGpuEnabled || false
        }));
    }

    function runSetup() {
        let base = String(Qt.resolvedUrl("./voice/venv_setup.sh"));
        if (base.indexOf("file://") === 0) base = base.substring(7);
        let venvPath = configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
        let cmd = "NON_INTERACTIVE=1 bash " + Sec.quoteForShell(base) + " " + Sec.quoteForShell(venvPath);
        voiceDs.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #voice-setup-" + Date.now());
    }

    function startRecording() {
        root.isRecording = true;
        root.sttStatusText = "Recording...";
        let lang = configuration.voiceLanguage || "en";
        let model = configuration.voiceSttModel || root.defaultSttModel;
        let modelPath = configuration.voiceSttModelPath || "";
        let gpuReq = configuration.voiceGpuEnabled || false;
        sendHttpCommand(JSON.stringify({cmd: "start_stt", duration: 0, language: lang, model: model, model_path: modelPath, gpu_requested: gpuReq}), 9015);
    }

    function stopRecording() {
        root.sttStatusText = "Processing...";
        sendHttpCommand(JSON.stringify({cmd: "stop_stt"}), 9015);
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
