import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support 2.0 as P5Support
import "Security.js" as Sec

KCM.SimpleKCM {
    id: page

    property bool voiceEnvChecked: false
    property var voiceEnvResult: null
    property bool ttsPlaying: false
    property bool sttTesting: false
    property string sttTestResult: ""
    property bool voiceSetupRunning: false
    property string voiceSetupStatus: ""
    property string storageExportStatus: ""

    property string cfg_promptTemplates: plasmoid.configuration.promptTemplates || "[]"
    property bool cfg_showInteractiveGuides: plasmoid.configuration.showInteractiveGuides !== undefined ? plasmoid.configuration.showInteractiveGuides : true
    property alias cfg_voiceEnabled: voiceEnabledToggle.checked
    property alias cfg_voiceTtsEnabled: voiceTtsEnabledToggle.checked
    property alias cfg_voiceAutoSend: voiceAutoSendToggle.checked

    P5Support.DataSource {
        id: voicePageDs
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
                    handleVoicePageResponse(resp, sourceName);
                } catch (e) {}
            }
        }
    }

    function handleVoicePageResponse(resp, sourceName) {
        if (resp.type === "env_check") {
            voiceEnvResult = resp;
            voiceEnvChecked = true;
            voiceSetupRunning = false;
            if (resp.stt_ready || resp.tts_ready) {
                voiceSetupStatus = i18n("Environment ready");
            } else {
                voiceSetupStatus = i18n("Some components missing — see status below");
            }
        } else if (resp.type === "setup_status") {
            if (resp.status === "creating_venv") {
                voiceSetupStatus = i18n("Creating virtual environment...");
            } else if (resp.status === "installing_packages") {
                voiceSetupStatus = i18n("Installing packages (this may take a few minutes)...");
            } else if (resp.status === "done") {
                voiceSetupStatus = i18n("Setup complete — checking environment...");
                runEnvCheck();
            }
        } else if (resp.type === "stt_result") {
            sttTesting = false;
            sttTestResult = resp.text || i18n("(no speech detected)");
        } else if (resp.type === "stt_error") {
            sttTesting = false;
            sttTestResult = i18n("Error: ") + (resp.error || i18n("Unknown"));
        } else if (resp.type === "tts_done") {
            ttsPlaying = false;
        } else if (resp.type === "tts_error") {
            ttsPlaying = false;
        } else if (resp.type === "tts_status") {
            if (resp.status === "playing") ttsPlaying = true;
        }
    }

    function getVenvPath() {
        return plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
    }

    function getVenvPython() {
        let venvPath = getVenvPath();
        return venvPath + "/bin/python3";
    }

    function getHelperPath() {
        let base = Qt.resolvedUrl("./voice/voice_helper.py");
        if (base.indexOf("file://") === 0) base = base.substring(7);
        return base;
    }

    function getSetupPath() {
        let base = Qt.resolvedUrl("./voice/voice_setup.sh");
        if (base.indexOf("file://") === 0) base = base.substring(7);
        return base;
    }

    function runEnvCheck() {
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let sttPath = plasmoid.configuration.voiceSttModelPath || "";
        let ttsPath = plasmoid.configuration.voiceTtsModelPath || "";
        let payload = JSON.stringify({cmd: "check_env", stt_model_path: sttPath, tts_model_path: ttsPath});
        let cmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payload) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payload) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
        voicePageDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #voice-env-" + Date.now());
    }

    function runVoiceSetup() {
        voiceSetupRunning = true;
        voiceSetupStatus = i18n("Starting setup...");
        let setupPath = getSetupPath();
        let venvPath = getVenvPath();
        let cmd = "bash " + Sec.quoteForShell(setupPath) + " " + Sec.quoteForShell(venvPath);
        voicePageDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #voice-setup-" + Date.now());
    }

    function sendVoiceCommand(payload) {
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let cmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payload) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payload) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
        voicePageDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #voice-cmd-" + Date.now());
    }


    FolderDialog {
        id: sttFolderDialog
        title: i18n("Select STT Model Directory")
        onAccepted: {
            let path = selectedFolder.toString();
            if (path.indexOf("file://") === 0) path = decodeURIComponent(path.slice(7));
            plasmoid.configuration.voiceSttModelPath = path;
        }
    }

    FolderDialog {
        id: ttsFolderDialog
        title: i18n("Select TTS Model Directory")
        onAccepted: {
            let path = selectedFolder.toString();
            if (path.indexOf("file://") === 0) path = decodeURIComponent(path.slice(7));
            plasmoid.configuration.voiceTtsModelPath = path;
        }
    }


    Timer {
        id: autoSetupTimer
        interval: 500
        repeat: false
        onTriggered: {
            runVoiceSetup();
        }
    }


    Kirigami.FormLayout {
        id: formLayout
        width: page.width || 500
        property int fieldMaxWidth: Kirigami.Units.gridUnit * 35

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
                    text: "<b>Voice features</b> let you speak to the AI and hear responses read aloud.<br>" +
                          "The Python environment is <b>set up automatically</b> when you enable this feature.<br><br>" +
                          "<b>How to use:</b><br>" +
                          "1. <b>Enable</b> voice features below — dependencies install automatically.<br>" +
                          "2. <b>Point to your model</b> directory or download default models.<br>" +
                          "3. Click the <b>microphone</b> button in chat to record voice input.<br>" +
                          "4. Enable <b>read-aloud</b> to hear AI responses spoken back.<br><br>" +
                          "<b>Models:</b> Uses <b>Faster Whisper</b> (STT) and <b>Kokoro</b> (TTS).<br>" +
                          "You can point to existing model directories instead of downloading."
                }
            }
        }

        QQC2.CheckBox {
            id: voiceEnabledToggle
            Kirigami.FormData.label: i18n("Enable voice features:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            checked: plasmoid.configuration.voiceEnabled || false
            text: checked ? i18n("Enabled — mic button appears in chat") : i18n("Disabled")
            onCheckedChanged: {
                if (checked && !voiceEnvChecked && !voiceSetupRunning) {
                    autoSetupTimer.restart();
                }
            }
        }

        // ── Setup Status ──────────────────────────────────────────────
        RowLayout {
            visible: voiceEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.BusyIndicator {
                visible: voiceSetupRunning
                running: voiceSetupRunning
                Layout.preferredWidth: Kirigami.Units.gridUnit
                Layout.preferredHeight: Kirigami.Units.gridUnit
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.8
                text: {
                    if (voiceSetupRunning) return voiceSetupStatus;
                    if (voiceEnvChecked && voiceEnvResult) {
                        let ok = (voiceEnvResult.stt_ready || voiceEnvResult.faster_whisper_ok) && voiceEnvResult.sounddevice_ok;
                        return ok ? i18n("Environment ready") : i18n("Environment needs setup — click Check Status");
                    }
                    return i18n("Checking environment...");
                }
                color: {
                    if (voiceSetupRunning) return Kirigami.Theme.neutralTextColor;
                    if (voiceEnvChecked && voiceEnvResult) {
                        let ok = (voiceEnvResult.stt_ready || voiceEnvResult.faster_whisper_ok) && voiceEnvResult.sounddevice_ok;
                        return ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor;
                    }
                    return Kirigami.Theme.textColor;
                }
            }

            QQC2.Button {
                text: i18n("Check Status")
                icon.name: "view-refresh"
                onClicked: runEnvCheck()
            }

            QQC2.Button {
                text: i18n("Reinstall")
                icon.name: "tools-wizard"
                visible: voiceEnvChecked && voiceEnvResult && !voiceEnvResult.stt_ready
                onClicked: runVoiceSetup()
            }
        }

        // ── Environment Status Grid ───────────────────────────────────
        Rectangle {
            visible: voiceEnabledToggle.checked && voiceEnvChecked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: statusGrid.implicitHeight + Kirigami.Units.gridUnit
            radius: 4
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
            border.width: 1

            GridLayout {
                id: statusGrid
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: Kirigami.Units.gridUnit * 0.5
                columns: 2
                columnSpacing: Kirigami.Units.gridUnit
                rowSpacing: Kirigami.Units.smallSpacing * 0.5

                QQC2.Label { text: i18n("Microphone:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: page.voiceEnvResult && page.voiceEnvResult.mic_available ? "✓ " + i18n("Available") : "✗ " + i18n("Not found")
                    color: page.voiceEnvResult && page.voiceEnvResult.mic_available ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                QQC2.Label { text: i18n("Audio player:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: page.voiceEnvResult && (page.voiceEnvResult.paplay_available || page.voiceEnvResult.aplay_available) ? "✓ " + i18n("Available") : "✗ " + i18n("Missing")
                    color: page.voiceEnvResult && (page.voiceEnvResult.paplay_available || page.voiceEnvResult.aplay_available) ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                QQC2.Label { text: i18n("STT engine:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: page.voiceEnvResult && page.voiceEnvResult.faster_whisper_ok ? "✓ faster-whisper" : "✗ " + i18n("Not installed")
                    color: page.voiceEnvResult && page.voiceEnvResult.faster_whisper_ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                QQC2.Label { text: i18n("TTS engine:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: page.voiceEnvResult && page.voiceEnvResult.kokoro_ok ? "✓ Kokoro" : "✗ " + i18n("Not installed")
                    color: page.voiceEnvResult && page.voiceEnvResult.kokoro_ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                QQC2.Label { text: i18n("espeak-ng:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: page.voiceEnvResult && page.voiceEnvResult.espeak_available ? "✓ " + i18n("Available") : "✗ " + i18n("Missing")
                    color: page.voiceEnvResult && page.voiceEnvResult.espeak_available ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                QQC2.Label { text: i18n("STT model:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: {
                        if (!page.voiceEnvResult) return "";
                        let hasPath = plasmoid.configuration.voiceSttModelPath && plasmoid.configuration.voiceSttModelPath.length > 0;
                        if (hasPath) return page.voiceEnvResult.stt_model_path_ok ? "✓ " + i18n("Custom path OK") : "✗ " + i18n("Path not found");
                        return page.voiceEnvResult.faster_whisper_ok ? "✓ " + i18n("Default ready") : "✗ " + i18n("Not downloaded");
                    }
                    color: {
                        if (!page.voiceEnvResult) return Kirigami.Theme.textColor;
                        let hasPath = plasmoid.configuration.voiceSttModelPath && plasmoid.configuration.voiceSttModelPath.length > 0;
                        if (hasPath) return page.voiceEnvResult.stt_model_path_ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor;
                        return page.voiceEnvResult.faster_whisper_ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor;
                    }
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }

                QQC2.Label { text: i18n("TTS model:"); font.bold: true; font.pointSize: Kirigami.Theme.smallFont.pointSize }
                QQC2.Label {
                    text: {
                        if (!page.voiceEnvResult) return "";
                        let hasPath = plasmoid.configuration.voiceTtsModelPath && plasmoid.configuration.voiceTtsModelPath.length > 0;
                        if (hasPath) return page.voiceEnvResult.tts_model_path_ok ? "✓ " + i18n("Custom path OK") : "✗ " + i18n("Path not found");
                        return page.voiceEnvResult.kokoro_ok ? "✓ " + i18n("Default ready") : "✗ " + i18n("Not downloaded");
                    }
                    color: {
                        if (!page.voiceEnvResult) return Kirigami.Theme.textColor;
                        let hasPath = plasmoid.configuration.voiceTtsModelPath && plasmoid.configuration.voiceTtsModelPath.length > 0;
                        if (hasPath) return page.voiceEnvResult.tts_model_path_ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor;
                        return page.voiceEnvResult.kokoro_ok ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor;
                    }
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
        }

        // ── STT Settings ──────────────────────────────────────────────
        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("STT model path:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                Layout.fillWidth: true
                placeholderText: i18n("Leave empty to use default model")
                text: plasmoid.configuration.voiceSttModelPath || ""
                onEditingFinished: plasmoid.configuration.voiceSttModelPath = text
            }
            QQC2.Button {
                icon.name: "folder-open"
                QQC2.ToolTip.text: i18n("Browse for STT model directory")
                onClicked: sttFolderDialog.open()
            }
        }

        RowLayout {
            visible: voiceEnabledToggle.checked && !(plasmoid.configuration.voiceSttModelPath && plasmoid.configuration.voiceSttModelPath.length > 0)
            Kirigami.FormData.label: i18n("Default STT model:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                Layout.fillWidth: true
                model: ["large-v3-turbo", "large-v3", "medium", "small", "base", "tiny"]
                currentIndex: {
                    let m = plasmoid.configuration.voiceSttModel || "large-v3-turbo";
                    for (let i = 0; i < model.length; i++) if (model[i] === m) return i;
                    return 0;
                }
                onActivated: plasmoid.configuration.voiceSttModel = currentValue
            }
            QQC2.Button {
                text: i18n("Download")
                icon.name: "download"
                onClicked: sendVoiceCommand(JSON.stringify({cmd: "download_stt", model: plasmoid.configuration.voiceSttModel || "large-v3-turbo"}))
            }
        }

        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("STT language:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                Layout.fillWidth: true
                model: ["en", "auto", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh", "ar", "hi"]
                currentIndex: {
                    let l = plasmoid.configuration.voiceLanguage || "en";
                    for (let i = 0; i < model.length; i++) if (model[i] === l) return i;
                    return 0;
                }
                onActivated: plasmoid.configuration.voiceLanguage = currentValue
            }
        }

        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Test STT:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: page.sttTesting ? i18n("Recording...") : i18n("Record & Transcribe")
                icon.name: page.sttTesting ? "media-record" : "audio-input-microphone"
                enabled: !page.sttTesting
                onClicked: {
                    page.sttTesting = true;
                    page.sttTestResult = "";
                    let lang = plasmoid.configuration.voiceLanguage || "en";
                    let model = plasmoid.configuration.voiceSttModel || "large-v3-turbo";
                    let modelPath = plasmoid.configuration.voiceSttModelPath || "";
                    sendVoiceCommand(JSON.stringify({cmd: "start_stt", duration: 5, language: lang, model: model, model_path: modelPath}));
                }
            }
        }

        QQC2.Label {
            visible: voiceEnabledToggle.checked && page.sttTestResult.length > 0
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            Kirigami.FormData.label: i18n("STT result:")
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            text: page.sttTestResult
        }

        // ── TTS Settings ──────────────────────────────────────────────
        QQC2.CheckBox {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Read AI responses aloud:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            id: voiceTtsEnabledToggle
            checked: plasmoid.configuration.voiceTtsEnabled || false
            text: checked ? i18n("Enabled — AI responses will be spoken") : i18n("Disabled")
        }

        RowLayout {
            visible: voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
            Kirigami.FormData.label: i18n("TTS model path:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                Layout.fillWidth: true
                placeholderText: i18n("Leave empty to use default model")
                text: plasmoid.configuration.voiceTtsModelPath || ""
                onEditingFinished: plasmoid.configuration.voiceTtsModelPath = text
            }
            QQC2.Button {
                icon.name: "folder-open"
                QQC2.ToolTip.text: i18n("Browse for TTS model directory")
                onClicked: ttsFolderDialog.open()
            }
        }

        RowLayout {
            visible: voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked && !(plasmoid.configuration.voiceTtsModelPath && plasmoid.configuration.voiceTtsModelPath.length > 0)
            Kirigami.FormData.label: i18n("Default TTS:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                Layout.fillWidth: true
                model: ["kokoro-82m"]
                currentIndex: 0
            }
            QQC2.Button {
                text: i18n("Download")
                icon.name: "download"
                onClicked: sendVoiceCommand(JSON.stringify({cmd: "download_tts", voice: plasmoid.configuration.voiceTtsVoice || "af_heart"}))
            }
        }

        RowLayout {
            visible: voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
            Kirigami.FormData.label: i18n("TTS voice:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                Layout.fillWidth: true
                model: ["af_heart", "af_bella", "af_nicole", "af_sarah", "af_sky", "am_adam", "am_michael", "bf_emma", "bf_isabella", "bm_george", "bm_lewis"]
                currentIndex: {
                    let v = plasmoid.configuration.voiceTtsVoice || "af_heart";
                    for (let i = 0; i < model.length; i++) if (model[i] === v) return i;
                    return 0;
                }
                onActivated: plasmoid.configuration.voiceTtsVoice = currentValue
            }
        }

        RowLayout {
            visible: voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
            Kirigami.FormData.label: i18n("Test TTS:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Speak Test")
                icon.name: "audio-speakers"
                onClicked: {
                    page.ttsPlaying = true;
                    sendVoiceCommand(JSON.stringify({cmd: "tts", text: i18n("Hello! This is a test of the text to speech system."), voice: plasmoid.configuration.voiceTtsVoice || "af_heart", lang_code: "a"}));
                }
            }
            QQC2.Button {
                text: i18n("Stop")
                icon.name: "media-playback-stop"
                visible: page.ttsPlaying
                onClicked: sendVoiceCommand(JSON.stringify({cmd: "stop_tts"}))
            }
        }

        QQC2.CheckBox {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Auto-send voice input:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            id: voiceAutoSendToggle
            checked: plasmoid.configuration.voiceAutoSend !== undefined ? plasmoid.configuration.voiceAutoSend : true
            text: checked ? i18n("Enabled — transcribed text is sent automatically") : i18n("Disabled — transcribed text goes to input field")
        }

        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Venv path:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                Layout.fillWidth: true
                text: plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv"
                onEditingFinished: plasmoid.configuration.voiceVenvPath = text
            }
        }


    }
}
