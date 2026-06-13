import "MainDatabase.js" as MainDatabase
import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import "Security.js" as Sec
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support

QQC2.ScrollView {
    id: page

    property bool voiceEnvChecked: false
    property bool voiceEnvChecking: false
    property var voiceEnvResult: null
    property bool ttsPlaying: false
    property bool sttTesting: false
    property int sttCountdown: 0
    property string sttTestResult: ""
    property string ttsTestResult: ""
    property string storageExportStatus: ""

    property string sttStatus: ""
    property string activeSttSource: ""
    property bool sttServiceActive: false
    property bool sttServiceEnabled: false
    property bool ttsServiceActive: false
    property bool ttsServiceEnabled: false
    // Computed binding — QML tracks dependencies (voiceEnvChecked, voiceEnvResult, voiceEnvChecking)
    property string statusText: {
        if (page.voiceEnvChecking)
            return i18n("Checking environment status...");

        if (!page.voiceEnvChecked)
            return i18n("Not checked — click Check Status");

        var r = page.voiceEnvResult;
        if (r && r.error)
            return i18n("Check failed: %1").arg(r.error);

        var ok = r && r.venv_ready && r.numpy_ok && r.sounddevice_ok;
        if (!ok)
            return i18n("Needs setup — run CPU Venv Setup or GPU Venv Setup");

        var sttReady = r.stt_ready;
        var ttsReady = r.tts_ready;
        if (sttReady && ttsReady)
            return i18n("Environment and models ready");

        if (!sttReady && !ttsReady)
            return i18n("Environment ready. STT & TTS models need to be downloaded.");

        if (!sttReady)
            return i18n("Environment ready. STT model needs to be downloaded.");

        return i18n("Environment ready. TTS model needs to be downloaded.");
    }
    property color statusColor: {
        if (page.voiceEnvChecking)
            return Kirigami.Theme.neutralTextColor;

        if (!page.voiceEnvChecked)
            return Kirigami.Theme.disabledTextColor;

        var r = page.voiceEnvResult;
        if (r && r.error)
            return Kirigami.Theme.negativeTextColor;

        var ok = r && r.venv_ready && r.numpy_ok && r.sounddevice_ok;
        if (!ok)
            return Kirigami.Theme.negativeTextColor;

        var sttReady = r.stt_ready;
        var ttsReady = r.tts_ready;
        if (sttReady && ttsReady)
            return Kirigami.Theme.positiveTextColor;

        return Kirigami.Theme.neutralTextColor;
    }
    property string cfg_promptTemplates: plasmoid.configuration.promptTemplates || "[]"
    property bool cfg_showInteractiveGuides: plasmoid.configuration.showInteractiveGuides
    property alias cfg_voiceEnabled: voiceEnabledToggle.checked
    property alias cfg_voiceTtsEnabled: voiceTtsEnabledToggle.checked
    property alias cfg_voiceAutoSend: voiceAutoSendToggle.checked
    property alias cfg_voiceSttModelPath: voiceSttModelPathField.text
    property alias cfg_voiceTtsModelPath: voiceTtsModelPathField.text
    property alias cfg_voiceVenvPath: voiceVenvPathField.text
    property alias cfg_voiceEspeakPath: voiceEspeakPathField.text
    property string cfg_voiceSttModel: plasmoid.configuration.voiceSttModel || "large-v3-turbo"
    property string cfg_voiceTtsModel: {
        let path = cfg_voiceTtsModelPath || "";
        if (path.trim() === "")
            return "espeak-ng";
        let p = path.toLowerCase();
        if (p.indexOf("kokoro") >= 0 || p.indexOf("voices.bin") >= 0)
            return "kokoro-82m";
        if (p.indexOf("piper") >= 0 || p.indexOf(".onnx") >= 0)
            return "piper";
        if (p.indexOf("f5") >= 0)
            return "f5-tts";
        if (p.indexOf("coqui") >= 0)
            return "coqui-tts";
        return "kokoro-82m";
    }
    property string cfg_voiceLanguage: plasmoid.configuration.voiceLanguage || "en"
    property string cfg_voiceTtsVoice: plasmoid.configuration.voiceTtsVoice || "af_heart"
    property bool setupRunning: false
    property int setupProgress: 0
    property string setupStatusText: ""
    property string setupLogs: ""
    property var activeSetupSource: null

    Component.onCompleted: {
        if (voiceEnabledToggle.checked) {
            runEnvCheck();
        }
    }

    function handleVoicePageResponse(resp, sourceName) {
        if (resp.type === "env_check") {
            page.voiceEnvResult = resp;
            page.voiceEnvChecked = true;
            page.voiceEnvChecking = false;
        } else if (resp.type === "stt_status") {
            page.sttStatus = resp.status;
            if (resp.status === "loading_model") {
                page.sttTestResult = i18n("Loading model...");
            } else if (resp.status === "recording") {
                page.sttCountdown = 5;
                page.sttTestResult = i18n("Recording...");
                sttTimer.restart();
            } else if (resp.status === "transcribing") {
                sttTimer.stop();
                page.sttTestResult = i18n("Transcribing...");
            }
        } else if (resp.type === "stt_result") {
            page.sttTesting = false;
            page.sttStatus = "";
            sttTimer.stop();
            page.sttTestResult = resp.text || i18n("(no speech detected)");


        } else if (resp.type === "stt_error") {
            page.sttTesting = false;
            page.sttStatus = "";
            sttTimer.stop();
            page.sttTestResult = i18n("Error: ") + (resp.error || i18n("Unknown"));
        } else if (resp.type === "tts_done") {
            page.ttsPlaying = false;
            page.ttsTestResult = i18n("Done playing.");
        } else if (resp.type === "tts_error") {
            page.ttsPlaying = false;
            page.ttsTestResult = i18n("Error: ") + (resp.error || i18n("Unknown"));
        } else if (resp.type === "tts_status") {
            if (resp.status === "playing") {
                page.ttsPlaying = true;
                page.ttsTestResult = i18n("Playing...");
            } else if (resp.status === "synthesizing") {
                page.ttsTestResult = i18n("Synthesizing...");
            }
        }
    }

    function runSetupInApp(mode, extraArg) {
        if (page.setupRunning)
            return ;

        page.setupRunning = true;
        page.setupProgress = 0;
        page.setupStatusText = i18n("Starting setup...");
        page.setupLogs = "";
        let setupPath = getSetupPath();
        let venvPath = getVenvPath();
        if (setupPath === "" || venvPath === "") {
            page.setupRunning = false;
            page.setupStatusText = i18n("Error: Setup path or virtual environment path is invalid.");
            return ;
        }
        let m = mode || "cpu";
        let extra = extraArg ? (" " + Sec.quoteForShell(extraArg)) : "";
        let cmd = "bash " + Sec.quoteForShell(setupPath) + " " + Sec.quoteForShell(venvPath) + " " + Sec.quoteForShell(m) + extra + " #in-app-setup-" + Date.now();
        page.activeSetupSource = cmd;
        voicePageDs.connectSource(cmd);
    }

    function cancelSetup() {
        if (page.activeSetupSource) {
            voicePageDs.disconnectSource(page.activeSetupSource);
            page.activeSetupSource = null;
        }
        page.setupRunning = false;
        page.setupStatusText = i18n("Setup cancelled.");
    }

    function getVenvPath() {
        let path = page.cfg_voiceVenvPath || "~/.local/share/kdeaichat/venv";
        if (path.charAt(0) === "~") {
            let home = StandardPaths.writableLocation(StandardPaths.HomeLocation).toString();
            if (home.indexOf("file://") === 0) {
                home = home.substring(7);
                try {
                    home = decodeURIComponent(home);
                } catch (e) {
                }
            }
            path = home + path.substring(1);
        }
        return path;
    }

    function getVenvPython() {
        let venvPath = getVenvPath();
        return venvPath + "/bin/python3";
    }

    function getHelperPath() {
        let base = Qt.resolvedUrl("./voice/voice_helper.py").toString();
        if (base === "")
            return "";

        if (base.indexOf("file://") === 0) {
            base = base.substring(7);
            try {
                base = decodeURIComponent(base);
            } catch (e) {
            }
        }
        return base;
    }

    function getKdeAiHelperPath() {
        let base = Qt.resolvedUrl("./kde_ai_helper.py").toString();
        if (base === "")
            return "";

        if (base.indexOf("file://") === 0) {
            base = base.substring(7);
            try {
                base = decodeURIComponent(base);
            } catch (e) {
            }
        }
        return base;
    }

    function getSetupPath() {
        let base = Qt.resolvedUrl("./voice/voice_setup.sh").toString();
        if (base === "")
            return "";

        if (base.indexOf("file://") === 0) {
            base = base.substring(7);
            try {
                base = decodeURIComponent(base);
            } catch (e) {
            }
        }
        return base;
    }

    function getSetupCommand(mode) {
        let setupPath = getSetupPath();
        let venvPath = getVenvPath();
        if (setupPath === "")
            return i18n("Installation path not found — reinstall widget");

        let m = mode || "cpu";
        return "bash " + Sec.quoteForShell(setupPath) + " " + Sec.quoteForShell(venvPath) + " " + Sec.quoteForShell(m);
    }

    function commandCopied(mode) {
        let cmd = getSetupCommand(mode);
        if (!cmd || cmd.trim() === "") {
            copiedText = "error";
            copiedTimer.restart();
            return ;
        }
        copiedText = "copying";
        copiedTimer.stop();
        Qt.callLater(function() {
            let targetStatus = (mode === "gpu") ? "copied_gpu" : "copied_cpu";
            try {
                clipboardHelper.text = cmd;
                clipboardHelper.selectAll();
                clipboardHelper.copy();
                copiedText = targetStatus;
            } catch (e) {
                console.error("TextField clipboard copy failed:", e);
            }
            try {
                MainDatabase.copyToClipboard(cmd);
                copiedText = targetStatus;
            } catch (e2) {
                console.error("MainDatabase clipboard copy failed:", e2);
            }
            copiedTimer.restart();
        });
    }

    function runSetupInTerminal(mode, extraArg) {
        let setupPath = getSetupPath();
        let venvPath = getVenvPath();
        if (setupPath === "" || venvPath === "")
            return ;

        let m = mode || "cpu";
        let extra = extraArg ? (" " + Sec.quoteForShell(extraArg)) : "";
        let cmd = "if command -v konsole >/dev/null 2>&1; then konsole --hold -e bash " + Sec.quoteForShell(setupPath) + " " + Sec.quoteForShell(venvPath) + " " + Sec.quoteForShell(m) + extra + "; elif command -v x-terminal-emulator >/dev/null 2>&1; then x-terminal-emulator -e bash " + Sec.quoteForShell(setupPath) + " " + Sec.quoteForShell(venvPath) + " " + Sec.quoteForShell(m) + extra + "; fi #voice-setup-term-" + Date.now();
        voicePageDs.connectSource(cmd);
    }

    function runInTerminal(payload) {
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let innerCmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(JSON.stringify(payload)) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(JSON.stringify(payload)) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi; echo; read -n 1 -s -r -p 'Press any key to exit...' </dev/tty";
        let cmd = "if command -v konsole >/dev/null 2>&1; then konsole --hold -e bash -c " + Sec.rawShellSnippetQuote(innerCmd) + "; elif command -v x-terminal-emulator >/dev/null 2>&1; then x-terminal-emulator -e bash -c " + Sec.rawShellSnippetQuote(innerCmd) + "; fi #voice-term-" + Date.now();
        voicePageDs.connectSource(cmd);
    }

    function runEnvCheck() {
        page.voiceEnvChecking = true;
        page.voiceEnvChecked = false;
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let sttPath = page.cfg_voiceSttModelPath || "";
        let ttsPath = page.cfg_voiceTtsModelPath || "";
        let espeakPath = page.cfg_voiceEspeakPath || "";
        let payload = JSON.stringify({
            "cmd": "check_env",
            "stt_model_path": sttPath,
            "tts_model_path": ttsPath,
            "espeak_path": espeakPath,
            "venv_path": getVenvPath(),
            "stt_model": page.cfg_voiceSttModel || "large-v3-turbo",
            "tts_model": page.cfg_voiceTtsModel || "kokoro-82m"
        });
        let innerCmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payload) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payload) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
        let cmd = "sh -c " + Sec.rawShellSnippetQuote(innerCmd) + " #voice-env-" + Date.now();
        voicePageDs.connectSource(cmd);
    }

    function sendVoiceCommand(payloadStr) {
        let payload = JSON.parse(payloadStr);
        let cmd = payload.cmd || "";
        let port = (cmd === "tts" || cmd === "stop_tts") ? 9016 : 9015;
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let innerCmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payloadStr) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payloadStr) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
        let fallbackSource = "sh -c " + Sec.rawShellSnippetQuote(innerCmd) + " #voice-cmd-" + Date.now();
        let xhr = new XMLHttpRequest();
        xhr.open("POST", "http://127.0.0.1:" + port + "/command", true);
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        let resp = JSON.parse(xhr.responseText);
                        handleVoicePageResponse(resp, fallbackSource);
                    } catch (e) {
                        voicePageDs.connectSource(fallbackSource);
                    }
                } else {
                    voicePageDs.connectSource(fallbackSource);
                }
            }
        };
        try {
            xhr.send(payloadStr);
        } catch (e) {
            voicePageDs.connectSource(fallbackSource);
        }
        return fallbackSource;
    }

    function setupVoiceServices() {
        let venvPy = getVenvPython();
        let espeakPath = page.cfg_voiceEspeakPath || "";
        let payload = JSON.stringify({
            "venvPy": venvPy,
            "espeakPath": espeakPath
        });
        let b64Payload = Qt.btoa(unescape(encodeURIComponent(payload)));
        let cmd = "python3 " + Sec.quoteForShell(getKdeAiHelperPath()) + " setup_voice_services " + Sec.quoteForShell(b64Payload);
        voicePageDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #voice-setup-services");
    }

    function deleteVoiceSetup() {
        page.voiceEnvChecking = true;
        page.voiceEnvChecked = false;
        let venvPy = getVenvPython();
        let payload = JSON.stringify({
            "venvPy": venvPy
        });
        let b64Payload = Qt.btoa(unescape(encodeURIComponent(payload)));
        let cmd = "python3 " + Sec.quoteForShell(getKdeAiHelperPath()) + " delete_voice_setup " + Sec.quoteForShell(b64Payload);
        voicePageDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #voice-delete-setup");
    }

    function refreshServiceStatuses() {
        if (!voiceEnabledToggle.checked)
            return ;

        voicePageDs.connectSource("systemctl --user is-active kde-ai-stt.service #check-stt-active");
        voicePageDs.connectSource("systemctl --user is-enabled kde-ai-stt.service #check-stt-enabled");
        voicePageDs.connectSource("systemctl --user is-active kde-ai-tts.service #check-tts-active");
        voicePageDs.connectSource("systemctl --user is-enabled kde-ai-tts.service #check-tts-enabled");
    }

    function toggleSttService() {
        if (page.sttServiceActive) {
            voicePageDs.connectSource("systemctl --user stop kde-ai-stt.service #toggle-stt-service-" + Date.now());
        } else {
            let venvPy = getVenvPython();
            let espeakPath = page.cfg_voiceEspeakPath || "";
            let payload = JSON.stringify({
                "venvPy": venvPy,
                "espeakPath": espeakPath
            });
            let b64Payload = Qt.btoa(unescape(encodeURIComponent(payload)));
            let setupCmd = "python3 " + Sec.quoteForShell(getKdeAiHelperPath()) + " setup_voice_services " + Sec.quoteForShell(b64Payload);
            let fullCmd = setupCmd + " && systemctl --user start kde-ai-stt.service";
            voicePageDs.connectSource("sh -c " + Sec.quoteForShell(fullCmd) + " #toggle-stt-service-" + Date.now());
        }
        refreshDelayTimer.restart();
    }

    function toggleSttBoot() {
        if (page.sttServiceEnabled) {
            voicePageDs.connectSource("systemctl --user disable kde-ai-stt.service #toggle-stt-boot-" + Date.now());
        } else {
            let venvPy = getVenvPython();
            let espeakPath = page.cfg_voiceEspeakPath || "";
            let payload = JSON.stringify({
                "venvPy": venvPy,
                "espeakPath": espeakPath
            });
            let b64Payload = Qt.btoa(unescape(encodeURIComponent(payload)));
            let setupCmd = "python3 " + Sec.quoteForShell(getKdeAiHelperPath()) + " setup_voice_services " + Sec.quoteForShell(b64Payload);
            let fullCmd = setupCmd + " && systemctl --user enable kde-ai-stt.service";
            voicePageDs.connectSource("sh -c " + Sec.quoteForShell(fullCmd) + " #toggle-stt-boot-" + Date.now());
        }
        refreshDelayTimer.restart();
    }

    function toggleTtsService() {
        if (page.ttsServiceActive) {
            voicePageDs.connectSource("systemctl --user stop kde-ai-tts.service #toggle-tts-service-" + Date.now());
        } else {
            let venvPy = getVenvPython();
            let espeakPath = page.cfg_voiceEspeakPath || "";
            let payload = JSON.stringify({
                "venvPy": venvPy,
                "espeakPath": espeakPath
            });
            let b64Payload = Qt.btoa(unescape(encodeURIComponent(payload)));
            let setupCmd = "python3 " + Sec.quoteForShell(getKdeAiHelperPath()) + " setup_voice_services " + Sec.quoteForShell(b64Payload);
            let fullCmd = setupCmd + " && systemctl --user start kde-ai-tts.service";
            voicePageDs.connectSource("sh -c " + Sec.quoteForShell(fullCmd) + " #toggle-tts-service-" + Date.now());
        }
        refreshDelayTimer.restart();
    }

    function toggleTtsBoot() {
        if (page.ttsServiceEnabled) {
            voicePageDs.connectSource("systemctl --user disable kde-ai-tts.service #toggle-tts-boot-" + Date.now());
        } else {
            let venvPy = getVenvPython();
            let espeakPath = page.cfg_voiceEspeakPath || "";
            let payload = JSON.stringify({
                "venvPy": venvPy,
                "espeakPath": espeakPath
            });
            let b64Payload = Qt.btoa(unescape(encodeURIComponent(payload)));
            let setupCmd = "python3 " + Sec.quoteForShell(getKdeAiHelperPath()) + " setup_voice_services " + Sec.quoteForShell(b64Payload);
            let fullCmd = setupCmd + " && systemctl --user enable kde-ai-tts.service";
            voicePageDs.connectSource("sh -c " + Sec.quoteForShell(fullCmd) + " #toggle-tts-boot-" + Date.now());
        }
        refreshDelayTimer.restart();
    }

    clip: true
    contentWidth: availableWidth
    contentHeight: contentContainer.implicitHeight
    onCfg_showInteractiveGuidesChanged: {
        plasmoid.configuration.showInteractiveGuides = cfg_showInteractiveGuides;
    }

    Timer {
        id: refreshDelayTimer

        interval: 1500
        repeat: false
        onTriggered: refreshServiceStatuses()
    }

    Timer {
        id: copiedTimer

        interval: 2000
        onTriggered: page.copiedText = ""
    }

    Timer {
        id: serviceStatusTimer

        interval: 3000
        running: voiceEnabledToggle.checked
        repeat: true
        triggeredOnStart: true
        onTriggered: refreshServiceStatuses()
    }

    // Countdown timer: fires every second, stops stt at 0
    Timer {
        id: sttTimer

        interval: 1000
        repeat: true
        onTriggered: {
            page.sttCountdown -= 1;
            if (page.sttCountdown <= 0) {
                stop();
                page.sttTesting = false;
                // The helper auto-stops at duration; send stop in case it's still running
                sendVoiceCommand(JSON.stringify({
                    "cmd": "stop_stt"
                }));
            }
        }
    }

    P5Support.DataSource {
        id: voicePageDs

        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = (data["stdout"] || "");
            let stderr = (data["stderr"] || "");
            let exitCode = data["exit code"];
            if (sourceName.indexOf("#in-app-setup-") >= 0) {
                if (stdout !== "") {
                    page.setupLogs += stdout;
                    // Parse line-by-line for JSON status messages from venv_setup.sh
                    let lines = stdout.split("\n");
                    for (let i = 0; i < lines.length; i++) {
                        let line = lines[i].trim();
                        if (line.indexOf("{") === 0) {
                            try {
                                let resp = JSON.parse(line);
                                if (resp.type === "setup_status") {
                                    page.setupStatusText = resp.status;
                                    page.setupProgress = resp.percent;
                                }
                            } catch (e) {
                            }
                        }
                    }
                }
                if (stderr !== "")
                    page.setupLogs += stderr;

            }
            let stdoutTrim = stdout.trim();
            if (stdoutTrim !== "" && sourceName.indexOf("#in-app-setup-") < 0) {
                if (sourceName.indexOf("#check-stt-active") >= 0) {
                    page.sttServiceActive = (stdoutTrim === "active");
                } else if (sourceName.indexOf("#check-stt-enabled") >= 0) {
                    page.sttServiceEnabled = (stdoutTrim === "enabled");
                } else if (sourceName.indexOf("#check-tts-active") >= 0) {
                    page.ttsServiceActive = (stdoutTrim === "active");
                } else if (sourceName.indexOf("#check-tts-enabled") >= 0) {
                    page.ttsServiceEnabled = (stdoutTrim === "enabled");
                } else if (stdoutTrim.indexOf("VOICE_SERVICES_SETUP_OK") >= 0) {
                    if (voiceEnabledToggle.checked)
                        voicePageDs.connectSource("systemctl --user start kde-ai-stt.service #start-stt-auto");

                    if (voiceTtsEnabledToggle.checked)
                        voicePageDs.connectSource("systemctl --user start kde-ai-tts.service #start-tts-auto");

                    Qt.callLater(refreshServiceStatuses);
                } else if (stdoutTrim.indexOf("DELETE_SETUP_OK") >= 0) {
                    page.voiceEnvResult = null;
                    page.voiceEnvChecked = false;
                    page.voiceEnvChecking = false;
                    Qt.callLater(runEnvCheck);
                    Qt.callLater(refreshServiceStatuses);
                } else {
                    let lines = stdoutTrim.split("\n");
                    for (let i = 0; i < lines.length; i++) {
                        let line = lines[i].trim();
                        if (!line)
                            continue;

                        try {
                            let resp = JSON.parse(line);
                            handleVoicePageResponse(resp, sourceName);
                        } catch (e) {
                        }
                    }
                }
            }
            if (exitCode !== undefined) {
                if (sourceName.indexOf("#in-app-setup-") >= 0) {
                    page.setupRunning = false;
                    if (exitCode !== 0) {
                        page.setupStatusText = i18n("Setup failed (exit %1). See logs above.").arg(exitCode);
                    } else {
                        page.setupStatusText = i18n("Setup completed successfully!");
                        page.setupProgress = 100;
                        setupVoiceServices();
                        Qt.callLater(runEnvCheck);
                        Qt.callLater(refreshServiceStatuses);
                    }
                    page.activeSetupSource = null;
                } else if (exitCode !== 0) {
                    if (sourceName.indexOf("#check-stt") < 0 && sourceName.indexOf("#check-tts") < 0) {
                        if (page.sttTesting && sourceName === page.activeSttSource) {
                            page.sttTesting = false;
                            page.sttStatus = "";
                            sttTimer.stop();
                            page.sttTestResult = i18n("Command failed (exit %1)").arg(exitCode) + (stderr ? "\n" + stderr.trim() : "");
                        }
                        if (sourceName.indexOf("voice-env-") >= 0) {
                            page.voiceEnvResult = {
                                "type": "env_check",
                                "error": stderr.trim() || i18n("Unknown error")
                            };
                            page.voiceEnvChecked = true;
                            page.voiceEnvChecking = false;
                        }
                        page.ttsPlaying = false;
                    }
                }
                if (sourceName.indexOf("voice-env-") >= 0)
                    page.voiceEnvChecking = false;

                disconnectSource(sourceName);
                if (sourceName === page.activeSttSource)
                    page.activeSttSource = "";

            }
        }
    }

    FolderDialog {
        id: sttFolderDialog

        title: i18n("Select STT Model Directory")
        onAccepted: {
            let path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            voiceSttModelPathField.text = path;
        }
    }

    FolderDialog {
        id: ttsFolderDialog

        title: i18n("Select TTS Model Directory")
        onAccepted: {
            let path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            voiceTtsModelPathField.text = path;
        }
    }

    FileDialog {
        id: ttsFileDialog

        title: i18n("Select TTS Model File (.onnx / .pth)")
        nameFilters: [ "Model files (*.onnx *.pth *.bin *.pt)", "All files (*)" ]
        onAccepted: {
            let path = selectedFile.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            voiceTtsModelPathField.text = path;
        }
    }

    FileDialog {
        id: espeakFileDialog

        title: i18n("Select espeak-ng/espeak executable")
        onAccepted: {
            let path = selectedFile.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            voiceEspeakPathField.text = path;
        }
    }

    FolderDialog {
        id: venvFolderDialog

        title: i18n("Select Python Virtual Environment Directory")
        onAccepted: {
            let path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));

            voiceVenvPathField.text = path;
        }
    }

    Item {
        id: contentContainer

        width: page.availableWidth
        implicitHeight: formLayout.implicitHeight

        QQC2.TextField {
            id: clipboardHelper

            width: 0
            height: 0
            opacity: 0
            activeFocusOnTab: false
        }

        Kirigami.FormLayout {
            id: formLayout

            width: parent.width

            // ── Guides Toggle ──────────────────────────────────────────────
            QQC2.CheckBox {
                id: showGuidesToggle

                Kirigami.FormData.label: i18n("Interactive Guides:")
                Layout.maximumWidth: formLayout.fieldMaxWidth
                text: checked ? i18n("Guides visible — showing setup instructions") : i18n("Guides hidden")
                checked: page.cfg_showInteractiveGuides
                onToggled: {
                    page.cfg_showInteractiveGuides = checked;
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: i18n("Show or hide the setup guide cards below each section.")
            }

            // ── Prompt Templates Guide ────────────────────────────────────
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Prompt Templates")
            }

            Rectangle {
                visible: page.cfg_showInteractiveGuides
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                implicitHeight: templateGuideLayout.implicitHeight + Kirigami.Units.gridUnit
                radius: 5
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                border.width: 1

                RowLayout {
                    id: templateGuideLayout

                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.6
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: "help-hint"
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                        Layout.alignment: Qt.AlignTop
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        textFormat: Text.RichText
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                        color: Kirigami.Theme.textColor
                        text: "<b>Prompt Templates</b> let you save frequently used system prompts.<br>" + "Each template you create becomes a <b>slash command</b> in the chat.<br><br>" + "<b>How to use:</b><br>" + "1. Give your template a <b>name</b> (e.g. \"code-reviewer\").<br>" + "2. Write the <b>system prompt</b> for that template.<br>" + "3. In chat, type <b>/code-reviewer</b> and send — the AI will use that system prompt.<br><br>" + "<b>Examples:</b><br>" + "• Name: <code>translator</code> → Prompt: <i>You are a professional translator...</i><br>" + "• Name: <code>code-review</code> → Prompt: <i>Review this code for bugs...</i><br>" + "• Name: <code>summarize</code> → Prompt: <i>Summarize the following text...</i>"
                    }

                }

            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: i18n("Template names become /commands in chat. Type /name to apply a template.")
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    id: newTemplateName

                    placeholderText: i18n("Template name (e.g. code-review)")
                    Layout.fillWidth: true
                }

                QQC2.TextField {
                    id: newTemplatePrompt

                    placeholderText: i18n("System prompt for this template")
                    Layout.fillWidth: true
                }

                QQC2.Button {
                    text: i18n("Add")
                    icon.name: "list-add"
                    enabled: newTemplateName.text.trim().length > 0
                    onClicked: {
                        if (!newTemplateName.text.trim())
                            return ;

                        let arr = JSON.parse(page.cfg_promptTemplates || "[]");
                        arr.push({
                            "name": newTemplateName.text.trim(),
                            "prompt": newTemplatePrompt.text.trim()
                        });
                        page.cfg_promptTemplates = JSON.stringify(arr);
                        newTemplateName.text = "";
                        newTemplatePrompt.text = "";
                    }
                }

                QQC2.Button {
                    text: i18n("View Templates")
                    icon.name: "view-list-details"
                    onClicked: templateDialog.open()
                }

            }

            // ── Voice & Audio ─────────────────────────────────────────────
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Voice & Audio (Experimental)")
            }

            Rectangle {
                visible: page.cfg_showInteractiveGuides
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                implicitHeight: voiceGuideLayout.implicitHeight + Kirigami.Units.gridUnit
                radius: 5
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
                border.width: 1

                RowLayout {
                    id: voiceGuideLayout

                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.6
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Icon {
                        source: "help-hint"
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.5
                        Layout.alignment: Qt.AlignTop
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        textFormat: Text.RichText
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.95
                        color: Kirigami.Theme.textColor
                        onLinkActivated: function(link) {
                            Qt.openUrlExternally(link);
                        }
                        text: "<b>Voice features</b> let you speak to the AI and hear responses read aloud.<br>" + "Click <b>Run CPU Venv Setup</b> or <b>Run GPU Venv Setup</b> to configure the virtual environment and install dependencies.<br><br>" + "<b>How to use:</b><br>" + "1. <b>Enable</b> voice features below.<br>" + "2. Click <b>Run CPU Venv Setup</b> or <b>Run GPU Venv Setup</b> to install dependencies in a terminal.<br>" + "3. Click <b>Check Status</b> to verify installation.<br>" + "4. Click the <b>microphone</b> button in chat to record voice input.<br><br>" + "<b>Models:</b> Uses <b>Faster Whisper</b> (STT) and <b>Kokoro</b> (TTS).<br>" + "You can point to existing model directories instead of downloading.<br><br>" + "<b>System Requirements & Package Manager Links:</b><br>" + "• <b>espeak-ng (Phonemizer)</b>: Required for text phonemization. Without this, Kokoro TTS fails. (<a href='https://github.com/espeak-ng/espeak-ng'>espeak-ng GitHub</a> | <a href='https://github.com/bootphon/phonemizer'>Phonemizer GitHub</a>)<br>" + "• <b>Clipboard utilities</b>: <code>wl-clipboard</code> (for Wayland) or <code>xclip</code> (for X11).<br>" + "• <b>Audio playback</b>: <code>pulseaudio-utils</code> (for paplay) or <code>alsa-utils</code> (for aplay).<br><br>" + "<b>Quick Install Command:</b><br>" + "• Ubuntu/Debian: <code>sudo apt install espeak-ng wl-clipboard xclip pulseaudio-utils</code><br>" + "• Arch Linux: <code>sudo pacman -S espeak-ng wl-clipboard xclip pulseaudio-utils</code><br>" + "• Fedora: <code>sudo dnf install espeak-ng wl-clipboard xclip pulseaudio-utils</code>"
                    }

                }

            }

            QQC2.CheckBox {
                id: voiceEnabledToggle

                Kirigami.FormData.label: i18n("Enable voice features:")
                Layout.maximumWidth: formLayout.fieldMaxWidth
                checked: plasmoid.configuration.voiceEnabled || false
                text: checked ? i18n("Enabled — mic button appears in chat") : i18n("Disabled")
                onToggled: {
                    if (checked)
                        setupVoiceServices();
                    else
                        voicePageDs.connectSource("systemctl --user stop kde-ai-stt.service #stop-stt-auto");
                }
            }

            // ── Virtual Environment Setup (Venv) Panel ────────────────────
            Rectangle {
                id: venvSetupPanel

                visible: voiceEnabledToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                implicitHeight: venvLayout.implicitHeight + Kirigami.Units.gridUnit * 1.5
                radius: 5
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.02)
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                border.width: 1

                ColumnLayout {
                    id: venvLayout

                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: i18n("Virtual Environment (Venv) Setup")
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    }

                    // Venv Path
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: i18n("Venv path:")
                            font.bold: true
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                        }

                        QQC2.TextField {
                            id: voiceVenvPathField

                            Layout.fillWidth: true
                            placeholderText: i18n("Default (~/.local/share/kdeaichat/venv)")
                        }

                        QQC2.Button {
                            icon.name: "folder-open"
                            QQC2.ToolTip.text: i18n("Browse for Python virtual environment directory")
                            onClicked: venvFolderDialog.open()
                        }

                    }

                    // Setup Action Row (Normal Mode)
                    RowLayout {
                        visible: !page.setupRunning
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Button {
                            text: i18n("Run CPU Venv Setup")
                            icon.name: "utilities-terminal"
                            QQC2.ToolTip.text: i18n("Setup Voice Environment utilizing CPU")
                            onClicked: page.runSetupInApp("cpu")
                        }

                        QQC2.Button {
                            text: i18n("Run GPU Venv Setup")
                            icon.name: "utilities-terminal"
                            QQC2.ToolTip.text: i18n("Setup Voice Environment utilizing NVIDIA CUDA GPU")
                            onClicked: page.runSetupInApp("gpu")
                        }

                        QQC2.Button {
                            text: i18n("Delete Venv Setup")
                            icon.name: "edit-delete"
                            onClicked: confirmDeleteSetupDialog.open()
                        }

                    }

                    // Setup Action Row (Running Mode)
                    RowLayout {
                        visible: page.setupRunning
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.ProgressBar {
                            id: setupProgressBar

                            Layout.fillWidth: true
                            value: page.setupProgress / 100
                        }

                        QQC2.Button {
                            text: i18n("Cancel Setup")
                            icon.name: "dialog-cancel"
                            onClicked: cancelSetup()
                        }

                    }

                    QQC2.Label {
                        visible: page.setupRunning || page.setupStatusText.length > 0
                        text: page.setupStatusText
                        font.italic: true
                        color: Kirigami.Theme.highlightColor
                    }

                    // Expandable Logs Terminal Box
                    QQC2.Button {
                        id: showLogsButton

                        property bool logsExpanded: false

                        visible: page.setupRunning || page.setupLogs.length > 0
                        text: logsExpanded ? i18n("Hide Setup Logs") : i18n("Show Setup Logs")
                        icon.name: logsExpanded ? "arrow-up" : "arrow-down"
                        onClicked: logsExpanded = !logsExpanded
                    }

                    Rectangle {
                        visible: (page.setupRunning || page.setupLogs.length > 0) && showLogsButton.logsExpanded
                        Layout.fillWidth: true
                        implicitHeight: Kirigami.Units.gridUnit * 8
                        radius: 4
                        color: "#1e1e1e"
                        border.color: "#3c3c3c"
                        border.width: 1

                        QQC2.ScrollView {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            clip: true

                            QQC2.TextArea {
                                readOnly: true
                                text: page.setupLogs
                                font.family: "monospace"
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                color: "#00ff00"
                                background: null
                                wrapMode: Text.WrapAnywhere
                                onTextChanged: {
                                    cursorPosition = text.length;
                                }
                            }

                        }

                    }

                    RowLayout {
                        visible: !page.setupRunning
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font: Kirigami.Theme.smallFont
                            opacity: 0.6
                            text: i18n("Note: GPU Venv Setup requires NVIDIA CUDA drivers & library dependencies.")
                        }

                    }

                    // Verification Grid Trigger Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: i18n("Verification status:")
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        QQC2.Button {
                            text: i18n("Check Status")
                            icon.name: "view-refresh"
                            onClicked: runEnvCheck()
                        }

                    }

                    // Grid itself
                    Rectangle {
                        visible: voiceEnvChecked
                        Layout.fillWidth: true
                        implicitHeight: statusGrid.implicitHeight + Kirigami.Units.gridUnit
                        radius: 4
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                        border.width: 1

                        GridLayout {
                            id: statusGrid

                            anchors.margins: Kirigami.Units.gridUnit * 0.5
                            columns: 2
                            columnSpacing: Kirigami.Units.gridUnit
                            rowSpacing: Kirigami.Units.smallSpacing * 0.5
                            anchors.fill: parent

                            QQC2.Label {
                                text: i18n("STT:")
                                font.bold: true
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }

                            QQC2.Label {
                                text: {
                                    if (!page.voiceEnvResult)
                                        return i18n("Not checked");
                                    if (page.voiceEnvResult.stt_ready)
                                        return "✓ " + i18n("Ready");
                                    if (!page.voiceEnvResult.venv_ready)
                                        return "✗ " + i18n("Venv not ready — run setup");
                                    if (!page.voiceEnvResult.faster_whisper_ok)
                                        return "✗ " + i18n("faster-whisper not installed");
                                    if (!page.voiceEnvResult.stt_model_path_ok)
                                        return "✗ " + i18n("Model path missing or invalid");
                                    return "✗ " + i18n("Not ready");
                                }
                                color: page.voiceEnvResult && page.voiceEnvResult.stt_ready ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }

                            QQC2.Label {
                                text: i18n("TTS:")
                                font.bold: true
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }

                            QQC2.Label {
                                text: {
                                    if (!page.voiceEnvResult)
                                        return i18n("Not checked");
                                    if (page.voiceEnvResult.tts_ready)
                                        return "✓ " + i18n("Ready");
                                    if (page.cfg_voiceTtsModel === "espeak-ng" && page.voiceEnvResult.espeak_available)
                                        return "✓ " + i18n("Ready (eSpeak-NG fallback)");
                                    if (!page.voiceEnvResult.espeak_available && page.cfg_voiceTtsModel !== "piper")
                                        return "✗ " + i18n("Phonemizer (espeak-ng) missing");
                                    let hasPath = page.cfg_voiceTtsModelPath && page.cfg_voiceTtsModelPath.trim().length > 0;
                                    if (!hasPath && page.cfg_voiceTtsModel !== "espeak-ng")
                                        return "✗ " + i18n("Model path not set");
                                    if (!page.voiceEnvResult.tts_model_path_ok)
                                        return "✗ " + i18n("Model not found at path");
                                    return "✗ " + i18n("Not ready");
                                }
                                color: page.voiceEnvResult && page.voiceEnvResult.tts_ready ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }

                            QQC2.Label {
                                text: i18n("Phonemizer:")
                                font.bold: true
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }

                            QQC2.Label {
                                text: page.voiceEnvResult && page.voiceEnvResult.espeak_available ? "✓ " + i18n("espeak-ng available") : "✗ " + i18n("espeak-ng missing")
                                color: page.voiceEnvResult && page.voiceEnvResult.espeak_available ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                            }

                        }

                    }

                }

            }

            // ── STT Configuration Panel ───────────────────────────────────
            Rectangle {
                id: sttConfigPanel

                visible: voiceEnabledToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                implicitHeight: sttLayout.implicitHeight + Kirigami.Units.gridUnit * 1.5
                radius: 5
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.02)
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                border.width: 1

                ColumnLayout {
                    id: sttLayout

                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: i18n("Speech-to-Text (STT)")
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    }

                    // STT Model Path Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: i18n("STT Model Path:")
                            font.bold: true
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                        }

                        QQC2.TextField {
                            id: voiceSttModelPathField

                            Layout.fillWidth: true
                            placeholderText: i18n("e.g. /path/to/whisper/model/folder")
                        }

                        QQC2.Button {
                            icon.name: "folder-open"
                            QQC2.ToolTip.text: i18n("Browse for STT model directory")
                            onClicked: sttFolderDialog.open()
                        }

                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        textFormat: Text.RichText
                        wrapMode: Text.Wrap
                        font: Kirigami.Theme.smallFont
                        opacity: 0.8
                        text: i18n("<b>Note:</b> You must provide a local directory path containing the Whisper model files (such as <code>model.bin</code>).")
                    }

                    QQC2.Button {
                        text: i18n("Download Models (Hugging Face)")
                        icon.name: "internet-services"
                        Layout.alignment: Qt.AlignLeft
                        onClicked: {
                            Qt.openUrlExternally("https://huggingface.co/models?search=faster-whisper");
                        }
                    }

                    // Language
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: i18n("STT Language:")
                            font.bold: true
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                        }

                        QQC2.ComboBox {
                            id: voiceLanguageCombo

                            Layout.fillWidth: true
                            model: ["en", "auto", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh", "ar", "hi"]
                            currentIndex: {
                                let l = page.cfg_voiceLanguage || "en";
                                for (let i = 0; i < model.length; i++) if (model[i] === l) {
                                    return i;
                                }
                                return 0;
                            }
                            onActivated: page.cfg_voiceLanguage = currentValue
                        }

                    }

                    // Auto-send Toggle
                    QQC2.CheckBox {
                        id: voiceAutoSendToggle

                        text: i18n("Auto-send voice input (sends automatically after speech finishes)")
                        Layout.fillWidth: true
                    }

                    // Test STT (only visible when STT service is running)
                    RowLayout {
                        visible: page.sttServiceActive
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: i18n("Test STT:")
                            font.bold: true
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                        }

                        QQC2.Button {
                            text: {
                                if (page.sttTesting) {
                                    if (page.sttStatus === "loading_model")
                                        return i18n("Loading model...");
                                    else if (page.sttStatus === "recording")
                                        return i18n("Recording... (%1s)", page.sttCountdown);
                                    else if (page.sttStatus === "transcribing")
                                        return i18n("Transcribing...");
                                    else
                                        return i18n("Initializing...");
                                }
                                return i18n("Record & Transcribe (5s)");
                            }
                            icon.name: page.sttTesting ? "media-record" : "audio-input-microphone"
                            highlighted: page.sttTesting
                            onClicked: {
                                if (page.sttTesting) {
                                    sttTimer.stop();
                                    page.sttTesting = false;
                                    page.sttStatus = "";
                                    page.sttCountdown = 0;
                                    if (page.activeSttSource !== "") {
                                        voicePageDs.disconnectSource(page.activeSttSource);
                                        page.activeSttSource = "";
                                    }
                                    return ;
                                }
                                page.sttTesting = true;
                                page.sttStatus = "loading_model";
                                page.sttCountdown = 5;
                                page.sttTestResult = "";
                                let lang = page.cfg_voiceLanguage || "en";
                                let model = page.cfg_voiceSttModel || "large-v3-turbo";
                                let modelPath = page.cfg_voiceSttModelPath || "";
                                page.activeSttSource = sendVoiceCommand(JSON.stringify({
                                    "cmd": "start_stt",
                                    "duration": 5,
                                    "language": lang,
                                    "model": model,
                                    "model_path": modelPath
                                }));
                            }
                        }

                    }

                    QQC2.Label {
                        visible: !page.sttServiceActive
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        text: i18n("Start the STT service to enable testing.")
                    }

                    // STT Result Text Box
                    Rectangle {
                        visible: page.sttTestResult.length > 0
                        Layout.fillWidth: true
                        implicitHeight: Math.max(Kirigami.Units.gridUnit * 2.5, testResultText.implicitHeight + Kirigami.Units.smallSpacing * 2)
                        radius: 4
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                        border.width: 1

                        QQC2.Label {
                            id: testResultText

                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            text: page.sttTestResult
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            font.italic: page.sttTestResult.indexOf("...") >= 0
                            opacity: page.sttTestResult.indexOf("...") >= 0 ? 0.7 : 1
                        }

                    }

                    // STT Service
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: i18n("STT Service:")
                            font.bold: true
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                        }

                        QQC2.Button {
                            text: page.sttServiceActive ? i18n("Stop Service") : i18n("Start Service")
                            icon.name: page.sttServiceActive ? "media-playback-stop" : "media-playback-start"
                            onClicked: toggleSttService()
                        }

                        QQC2.Button {
                            text: page.sttServiceEnabled ? i18n("Disable Autostart") : i18n("Enable Autostart")
                            icon.name: page.sttServiceEnabled ? "box-unlocked" : "box-locked"
                            onClicked: toggleSttBoot()
                        }

                        QQC2.Label {
                            text: page.sttServiceActive ? i18n("Active (Running)") : i18n("Inactive (Stopped)")
                            font.bold: true
                            color: page.sttServiceActive ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
                        }

                    }

                }

            }

            // ── TTS Configuration Panel ───────────────────────────────────
            Rectangle {
                id: ttsConfigPanel

                visible: voiceEnabledToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                implicitHeight: ttsLayout.implicitHeight + Kirigami.Units.gridUnit * 1.5
                radius: 5
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.02)
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                border.width: 1

                ColumnLayout {
                    id: ttsLayout

                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: i18n("Text-to-Speech (TTS)")
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    }

                    QQC2.CheckBox {
                        id: voiceTtsEnabledToggle

                        text: i18n("Read AI responses aloud")
                        Layout.fillWidth: true
                    }

                    // Model Path Row (TTS)
                    RowLayout {
                        visible: voiceTtsEnabledToggle.checked
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: i18n("TTS Model Path:")
                            font.bold: true
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                        }

                        QQC2.TextField {
                            id: voiceTtsModelPathField

                            Layout.fillWidth: true
                            placeholderText: i18n("Path to model directory or file...")
                        }

                        QQC2.Button {
                            icon.name: "document-properties"
                            QQC2.ToolTip.text: i18n("Browse for TTS model file")
                            onClicked: ttsFileDialog.open()
                        }

                        QQC2.Button {
                            icon.name: "folder-open"
                            QQC2.ToolTip.text: i18n("Browse for TTS model directory")
                            onClicked: ttsFolderDialog.open()
                        }

                    }

                    QQC2.Label {
                        visible: voiceTtsEnabledToggle.checked
                        Layout.fillWidth: true
                        textFormat: Text.RichText
                        wrapMode: Text.Wrap
                        font: Kirigami.Theme.smallFont
                        opacity: 0.8
                        text: i18n("<b>Note:</b> Download the model files manually and select their path above. The engine automatically detects the provider (e.g. Kokoro, Piper, F5-TTS, Coqui) based on the path. Defaults to system eSpeak-NG if path is empty.")
                    }

                    QQC2.Button {
                        visible: voiceTtsEnabledToggle.checked
                        text: i18n("Download Models (Hugging Face)")
                        icon.name: "internet-services"
                        Layout.alignment: Qt.AlignLeft
                        onClicked: {
                            Qt.openUrlExternally("https://huggingface.co/models?search=tts");
                        }
                    }

                    // TTS Voice Selector Row
                    RowLayout {
                        visible: voiceTtsEnabledToggle.checked
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: i18n("TTS Voice:")
                            font.bold: true
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                        }

                        QQC2.ComboBox {
                            id: voiceTtsVoiceCombo

                            Layout.fillWidth: true
                            model: ["af_heart", "af_bella", "af_nicole", "af_sarah", "af_sky", "am_adam", "am_michael", "bf_emma", "bf_isabella", "bm_george", "bm_lewis"]
                            currentIndex: {
                                let v = page.cfg_voiceTtsVoice || "af_heart";
                                for (let i = 0; i < model.length; i++) if (model[i] === v) {
                                    return i;
                                }
                                return 0;
                            }
                            onActivated: page.cfg_voiceTtsVoice = currentValue
                        }

                    }

                    // Test TTS Row (only visible when TTS service is running)
                    RowLayout {
                        visible: voiceTtsEnabledToggle.checked && page.ttsServiceActive
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: i18n("Test TTS:")
                            font.bold: true
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                        }

                        QQC2.TextField {
                            id: voiceTtsTestInputField

                            Layout.fillWidth: true
                            placeholderText: i18n("Enter text to speak...")
                            text: i18n("Hello! This is a test of the text to speech system.")
                        }

                        QQC2.Button {
                            text: i18n("Speak Test")
                            icon.name: "audio-speakers"
                            onClicked: {
                                page.ttsPlaying = true;
                                page.ttsTestResult = i18n("Initializing...");
                                sendVoiceCommand(JSON.stringify({
                                    "cmd": "tts",
                                    "text": voiceTtsTestInputField.text.trim() || i18n("Hello! This is a test of the text to speech system."),
                                    "voice": page.cfg_voiceTtsVoice || "af_heart",
                                    "lang_code": "a",
                                    "model_path": page.cfg_voiceTtsModelPath || "",
                                    "espeak_path": page.cfg_voiceEspeakPath || ""
                                }));
                            }
                        }

                        QQC2.Button {
                            text: i18n("Stop")
                            icon.name: "media-playback-stop"
                            visible: page.ttsPlaying
                            onClicked: sendVoiceCommand(JSON.stringify({
                                "cmd": "stop_tts"
                            }))
                        }

                    }

                    QQC2.Label {
                        visible: voiceTtsEnabledToggle.checked && !page.ttsServiceActive
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        text: i18n("Start the TTS service to enable testing.")
                    }

                    // TTS Status Box
                    Rectangle {
                        visible: voiceTtsEnabledToggle.checked && page.ttsTestResult.length > 0
                        Layout.fillWidth: true
                        implicitHeight: Math.max(Kirigami.Units.gridUnit * 2.5, ttsTestResultText.implicitHeight + Kirigami.Units.smallSpacing * 2)
                        radius: 4
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                        border.width: 1

                        QQC2.Label {
                            id: ttsTestResultText

                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            text: page.ttsTestResult
                            wrapMode: Text.Wrap
                            textFormat: Text.PlainText
                            font.italic: page.ttsTestResult.indexOf("...") >= 0
                            opacity: page.ttsTestResult.indexOf("...") >= 0 ? 0.7 : 1
                        }

                    }

                    // TTS Service
                    RowLayout {
                        visible: voiceTtsEnabledToggle.checked
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: i18n("TTS Service:")
                            font.bold: true
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                        }

                        QQC2.Button {
                            text: page.ttsServiceActive ? i18n("Stop Service") : i18n("Start Service")
                            icon.name: page.ttsServiceActive ? "media-playback-stop" : "media-playback-start"
                            onClicked: toggleTtsService()
                        }

                        QQC2.Button {
                            text: page.ttsServiceEnabled ? i18n("Disable Autostart") : i18n("Enable Autostart")
                            icon.name: page.ttsServiceEnabled ? "box-unlocked" : "box-locked"
                            onClicked: toggleTtsBoot()
                        }

                        QQC2.Label {
                            text: page.ttsServiceActive ? i18n("Active (Running)") : i18n("Inactive (Stopped)")
                            font.bold: true
                            color: page.ttsServiceActive ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.neutralTextColor
                        }

                    }

                }

            }

            // ── eSpeak-NG Configuration Panel ─────────────────────────────
            Rectangle {
                id: espeakConfigPanel

                visible: voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                implicitHeight: espeakLayout.implicitHeight + Kirigami.Units.gridUnit * 1.5
                radius: 5
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.02)
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                border.width: 1

                ColumnLayout {
                    id: espeakLayout

                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.Label {
                        text: i18n("eSpeak-NG Configuration")
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.1
                    }

                    // espeak-ng Path Row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.Label {
                            text: i18n("eSpeak-NG Path:")
                            font.bold: true
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                        }

                        QQC2.TextField {
                            id: voiceEspeakPathField

                            Layout.fillWidth: true
                            placeholderText: i18n("System default (recommended)")
                        }

                        QQC2.Button {
                            icon.name: "folder-open"
                            QQC2.ToolTip.text: i18n("Browse for espeak-ng executable")
                            onClicked: espeakFileDialog.open()
                        }

                        QQC2.Button {
                            text: i18n("Install")
                            icon.name: "download"
                            QQC2.ToolTip.text: i18n("Install espeak-ng using system package manager")
                            onClicked: {
                                runSetupInTerminal("install_espeak");
                            }
                        }

                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        textFormat: Text.RichText
                        wrapMode: Text.Wrap
                        font: Kirigami.Theme.smallFont
                        opacity: 0.8
                        text: i18n("eSpeak-NG is required for phoneme generation in Kokoro and other English TTS models, or as a standalone fallback synthesis provider.")
                    }

                }

            }

            // ── Chat Storage ─────────────────────────────────────────────────
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Chat Storage")
            }

            RowLayout {
                Kirigami.FormData.label: i18n("Save chats to:")
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    id: customHistoryPathField

                    Layout.fillWidth: true
                    placeholderText: i18n("Default (~/.config)")
                    text: plasmoid.configuration.customHistoryPath || ""
                    onTextChanged: plasmoid.configuration.customHistoryPath = text
                }

                QQC2.Button {
                    text: i18n("Browse…")
                    icon.name: "folder-open"
                    onClicked: storageFolderDialog.open()
                }

            }

            Rectangle {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                visible: customHistoryPathField.text.trim() !== ""
                implicitHeight: storageInfoRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                radius: 5
                color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
                border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2)
                border.width: 1

                RowLayout {
                    id: storageInfoRow

                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }

                    Kirigami.Icon {
                        source: "folder-sync"
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: Kirigami.Units.iconSizes.small
                        Layout.alignment: Qt.AlignVCenter
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
                        text: {
                            let p = customHistoryPathField.text.trim();
                            if (p === "")
                                return "";

                            if (p.indexOf("file://") === 0)
                                p = decodeURIComponent(p.slice(7));

                            let file = p.endsWith("/") ? p + "kdeaichat_history.json" : p + "/kdeaichat_history.json";
                            return i18n("Chats will be saved to: <b>%1</b><br/>Your existing chats are <b>automatically exported</b> when you press Apply / OK.").arg(file);
                        }
                        textFormat: Text.RichText
                    }

                }

            }

            RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                visible: customHistoryPathField.text.trim() !== ""
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    id: exportNowBtn

                    text: page.storageExportStatus !== "" ? page.storageExportStatus : i18n("Export Now")
                    icon.name: "document-export"
                    enabled: customHistoryPathField.text.trim() !== "" && page.storageExportStatus === ""
                    onClicked: {
                        page.storageExportStatus = i18n("Exporting…");
                        let dir = customHistoryPathField.text.trim();
                        if (dir.indexOf("file://") === 0)
                            dir = decodeURIComponent(dir.slice(7));

                        let file = dir.endsWith("/") ? dir + "kdeaichat_history.json" : dir + "/kdeaichat_history.json";
                        let jsonStr = plasmoid.configuration.chatSessionsJson || "[]";
                        let b64 = Qt.btoa(unescape(encodeURIComponent(jsonStr)));
                        let cmd = "python3 -c \"import base64, os; path=os.path.expanduser(" + Sec.quoteForShell(file) + "); os.makedirs(os.path.dirname(path), exist_ok=True); " + "open(path, 'w', encoding='utf-8').write(base64.b64decode(" + Sec.quoteForShell(b64) + ").decode('utf-8')); print('OK')\"";
                        storageDs.connectSource(cmd + " #storage-export-" + Date.now());
                        storageExportTimer.restart();
                    }
                }

                QQC2.Button {
                    text: i18n("Open Folder")
                    icon.name: "folder-open"
                    visible: customHistoryPathField.text.trim() !== ""
                    onClicked: {
                        let dir = customHistoryPathField.text.trim();
                        if (dir.indexOf("file://") === 0)
                            dir = decodeURIComponent(dir.slice(7));

                        storageDs.connectSource("xdg-open " + Sec.quoteForShell(dir) + " #open-storage-dir");
                    }
                }

                QQC2.Button {
                    text: i18n("Clear Path")
                    icon.name: "edit-clear"
                    visible: customHistoryPathField.text.trim() !== ""
                    onClicked: {
                        customHistoryPathField.text = "";
                    }
                }

            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.7
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.88
                text: customHistoryPathField.text.trim() === "" ? i18n("Chats are saved in the default KDE config location. Select a folder above to store them elsewhere (e.g. a synced cloud drive).") : i18n("<b>Warning: Beta feature.</b> After changing this path, press <b>Apply</b> or <b>OK</b> — your chats will automatically be exported to the new location.")
                textFormat: Text.RichText
            }

        }

        // ── Storage DataSource ──────────────────────────────────────────────────
        P5Support.DataSource {
            id: storageDs

            engine: "executable"
            connectedSources: []
            onNewData: function(sourceName, data) {
                let out = (data["stdout"] || "").trim();
                let err = (data["stderr"] || "").trim();
                if (sourceName.indexOf("storage-export-") >= 0) {
                    page.storageExportStatus = (out.trim() === "OK" || err === "") ? i18n("✓ Exported!") : i18n("Export failed");
                    storageExportTimer.restart();
                }
                disconnectSource(sourceName);
            }
        }

        Timer {
            id: storageExportTimer

            interval: 2500
            repeat: false
            onTriggered: {
                page.storageExportStatus = "";
            }
        }

        FolderDialog {
            id: storageFolderDialog

            title: i18n("Select Chat History Directory")
            onAccepted: {
                let path = selectedFolder.toString();
                if (path.indexOf("file://") === 0)
                    path = decodeURIComponent(path.slice(7));

                if (path.length > 1 && path.slice(-1) === "/")
                    path = path.slice(0, -1);

                customHistoryPathField.text = path;
            }
        }

        // ── Template Viewer Dialog ───────────────────────────────────────────────
        QQC2.Dialog {
            id: templateDialog

            modal: true
            standardButtons: QQC2.Dialog.Close
            title: i18n("Prompt Templates")
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            width: Kirigami.Units.gridUnit * 32
            height: Kirigami.Units.gridUnit * 28

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    opacity: 0.72
                    font: Kirigami.Theme.smallFont
                    text: i18n("Your saved prompt templates. Type /&lt;name&gt; in chat to use them.")
                }

                Kirigami.Separator {
                    Layout.fillWidth: true
                }

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ListView {
                        id: templateListView

                        model: {
                            try {
                                return JSON.parse(page.cfg_promptTemplates || "[]");
                            } catch (e) {
                                return [];
                            }
                        }

                        delegate: Rectangle {
                            width: templateListView.width
                            implicitHeight: templateItemLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
                            radius: 4
                            color: index % 2 === 0 ? Kirigami.Theme.backgroundColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.03)
                            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                            border.width: 1

                            ColumnLayout {
                                id: templateItemLayout

                                anchors.margins: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing / 2

                                anchors {
                                    left: parent.left
                                    right: parent.right
                                    top: parent.top
                                }

                                QQC2.Label {
                                    text: "/" + (modelData.name || ("template-" + (index + 1)))
                                    font.bold: true
                                    font.family: "monospace"
                                    color: Kirigami.Theme.highlightColor
                                }

                                QQC2.Label {
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                    text: modelData.prompt || ""
                                    opacity: 0.8
                                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
                                }

                            }

                            QQC2.ToolButton {
                                icon.name: "edit-delete"
                                QQC2.ToolTip.text: i18n("Delete template")
                                onClicked: {
                                    let arr = JSON.parse(page.cfg_promptTemplates || "[]");
                                    arr.splice(index, 1);
                                    page.cfg_promptTemplates = JSON.stringify(arr);
                                }

                                anchors {
                                    right: parent.right
                                    top: parent.top
                                    margins: Kirigami.Units.smallSpacing
                                }

                            }

                        }

                    }

                }

                QQC2.Label {
                    visible: templateListView.model.length === 0
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignCenter
                    opacity: 0.5
                    text: i18n("No templates yet. Create one above.")
                    font: Kirigami.Theme.smallFont
                }

            }

        }

    }

    QQC2.Dialog {
        id: confirmDeleteSetupDialog

        modal: true
        standardButtons: QQC2.Dialog.Yes | QQC2.Dialog.No
        title: i18n("Confirm Delete Venv Setup")
        x: Math.round((parent.width - width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: Kirigami.Units.gridUnit * 22
        onAccepted: {
            page.deleteVoiceSetup();
        }

        contentItem: ColumnLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: i18n("Are you sure you want to delete the voice virtual environment? This will stop and disable the services, and remove the venv and downloaded models completely.")
            }

        }

    }

}
