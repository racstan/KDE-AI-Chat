import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as P5Support
import "MainDatabase.js" as MainDatabase
import "Security.js" as Sec

QQC2.ScrollView {
    id: page

    contentWidth: availableWidth
    contentHeight: formLayout.implicitHeight

    property var plasmoidRef: plasmoid
    property bool voiceEnvChecked: false
    property var voiceEnvResult: null
    property bool ttsPlaying: false
    property bool sttTesting: false
    property string sttTestResult: ""
    property string envStatusText: ""

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
                    if (resp.type === "env_check") {
                        voiceEnvResult = resp;
                        voiceEnvChecked = true;
                    } else if (resp.type === "stt_result") {
                        sttTesting = false;
                        sttTestResult = resp.text || "(no speech detected)";
                    } else if (resp.type === "stt_error") {
                        sttTesting = false;
                        sttTestResult = "Error: " + (resp.error || "Unknown");
                    } else if (resp.type === "tts_done") {
                        ttsPlaying = false;
                    } else if (resp.type === "tts_error") {
                        ttsPlaying = false;
                    } else if (resp.type === "tts_status") {
                        if (resp.status === "playing") ttsPlaying = true;
                    }
                } catch (e) {}
            }
        }
    }

    // cfg_ aliases
    property string cfg_promptTemplates: plasmoid.configuration.promptTemplates || "[]"
    property alias cfg_voiceEnabled: voiceEnabledToggle.checked
    property alias cfg_voiceTtsEnabled: voiceTtsEnabledToggle.checked
    property alias cfg_voiceAutoSend: voiceAutoSendToggle.checked

    FolderDialog {
        id: sttFolderDialog
        title: i18n("Select STT Model Directory")
        onAccepted: {
            let path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));
            plasmoid.configuration.voiceSttModelPath = path;
        }
    }

    FolderDialog {
        id: ttsFolderDialog
        title: i18n("Select TTS Model Directory")
        onAccepted: {
            let path = selectedFolder.toString();
            if (path.indexOf("file://") === 0)
                path = decodeURIComponent(path.slice(7));
            plasmoid.configuration.voiceTtsModelPath = path;
        }
    }

    Kirigami.FormLayout {
        id: formLayout
        width: page.availableWidth

        // ── Guide ─────────────────────────────────────────────────────
        Rectangle {
            visible: true
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: guideLayout.implicitHeight + Kirigami.Units.gridUnit
            radius: 5
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.08)
            border.color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.25)
            border.width: 1
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Voice & Audio Guide")

            RowLayout {
                id: guideLayout
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
                          "<b>1.</b> Create the voice environment by running the setup command below.<br>" +
                          "<b>2.</b> Point to your STT/TTS model directories or download default models.<br>" +
                          "<b>3.</b> Enable voice features and optionally enable read-aloud.<br>" +
                          "<b>4.</b> Click the <b>microphone</b> button in the chat input to record.<br>" +
                          "<br>Uses <b>Faster Whisper</b> for speech-to-text and <b>Kokoro</b> for text-to-speech."
                }
            }
        }

        // ── Prompt Templates ──────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Prompt Templates")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            Kirigami.FormData.label: i18n("Templates:")
            wrapMode: Text.Wrap
            opacity: 0.72
            font: Kirigami.Theme.smallFont
            text: i18n("Save frequently used prompts. Use /template in chat to apply them.")
        }

        Repeater {
            model: {
                try {
                    return JSON.parse(page.cfg_promptTemplates || "[]");
                } catch(e) { return []; }
            }
            delegate: RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: formLayout.fieldMaxWidth
                spacing: Kirigami.Units.smallSpacing

                QQC2.Label {
                    text: modelData.name || ("Template " + (index + 1))
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                QQC2.ToolButton {
                    icon.name: "edit-delete"
                    onClicked: {
                        let arr = JSON.parse(page.cfg_promptTemplates || "[]");
                        arr.splice(index, 1);
                        page.cfg_promptTemplates = JSON.stringify(arr);
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: newTemplateName
                placeholderText: i18n("Template name")
                Layout.fillWidth: true
            }
            QQC2.TextField {
                id: newTemplatePrompt
                placeholderText: i18n("System prompt")
                Layout.fillWidth: true
            }
            QQC2.Button {
                text: i18n("Add")
                onClicked: {
                    if (!newTemplateName.text.trim()) return;
                    let arr = JSON.parse(page.cfg_promptTemplates || "[]");
                    arr.push({"name": newTemplateName.text.trim(), "prompt": newTemplatePrompt.text.trim()});
                    page.cfg_promptTemplates = JSON.stringify(arr);
                    newTemplateName.text = "";
                    newTemplatePrompt.text = "";
                }
            }
        }

        // ── Voice & Audio ─────────────────────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Voice & Audio (Experimental)")
        }

        QQC2.CheckBox {
            id: voiceEnabledToggle
            Kirigami.FormData.label: i18n("Enable voice features:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            checked: plasmoid.configuration.voiceEnabled || false
            text: checked ? i18n("Enabled — mic button appears in chat") : i18n("Disabled")
        }

        // ── Environment Setup ─────────────────────────────────────────
        ColumnLayout {
            visible: voiceEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            Kirigami.FormData.label: i18n("Environment setup:")
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: i18n("Run this command in a terminal to install voice dependencies:")
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: setupCmdLabel.implicitHeight + Kirigami.Units.gridUnit
                radius: 4
                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                border.width: 1

                QQC2.Label {
                    id: setupCmdLabel
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.gridUnit * 0.4
                    wrapMode: Text.Wrap
                    font.family: "monospace"
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize * 0.85
                    text: {
                        let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
                        return "python3 -m venv " + venvPath + " && " + venvPath + "/bin/pip install faster-whisper kokoro sounddevice numpy soundfile";
                    }
                }
            }

            RowLayout {
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    text: i18n("Copy Command")
                    icon.name: "edit-copy"
                    onClicked: {
                        let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
                        let cmd = "python3 -m venv " + venvPath + " && " + venvPath + "/bin/pip install faster-whisper kokoro sounddevice numpy soundfile";
                        MainDatabase.copyToClipboard(cmd);
                    }
                }

                QQC2.Button {
                    text: i18n("Check Status")
                    icon.name: "dialog-ok"
                    onClicked: {
                        let helperPath = MainDatabase.getVoiceHelperPath();
                        let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
                        let venvPy = venvPath + "/bin/python3";
                        let sttPath = plasmoid.configuration.voiceSttModelPath || "";
                        let ttsPath = plasmoid.configuration.voiceTtsModelPath || "";
                        let payload = JSON.stringify({cmd: "check_env", stt_model_path: sttPath, tts_model_path: ttsPath});
                        let cmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payload) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payload) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
                        voicePageDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #voice-env-" + Date.now());
                    }
                }
            }

            // Status display
            Rectangle {
                visible: page.voiceEnvChecked
                Layout.fillWidth: true
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
                            if (hasPath) {
                                return page.voiceEnvResult.stt_model_path_ok ? "✓ " + i18n("Custom path OK") : "✗ " + i18n("Path not found");
                            }
                            return page.voiceEnvResult.faster_whisper_ok ? "✓ " + i18n("Default model ready") : "✗ " + i18n("Not downloaded");
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
                            if (hasPath) {
                                return page.voiceEnvResult.tts_model_path_ok ? "✓ " + i18n("Custom path OK") : "✗ " + i18n("Path not found");
                            }
                            return page.voiceEnvResult.kokoro_ok ? "✓ " + i18n("Default model ready") : "✗ " + i18n("Not downloaded");
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
        }

        // ── Speech-to-Text ────────────────────────────────────────────
        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("STT model path:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: voiceSttModelPathField
                Layout.fillWidth: true
                placeholderText: i18n("Leave empty to use default model")
                text: plasmoid.configuration.voiceSttModelPath || ""
                onEditingFinished: {
                    plasmoid.configuration.voiceSttModelPath = text;
                }
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
                id: voiceSttModelCombo
                Layout.fillWidth: true
                model: ["large-v3-turbo", "large-v3", "medium", "small", "base", "tiny"]
                currentIndex: {
                    let m = plasmoid.configuration.voiceSttModel || "large-v3-turbo";
                    for (let i = 0; i < model.length; i++) {
                        if (model[i] === m) return i;
                    }
                    return 0;
                }
                onActivated: {
                    plasmoid.configuration.voiceSttModel = currentValue;
                }
            }

            QQC2.Button {
                visible: !(plasmoid.configuration.voiceSttModelPath && plasmoid.configuration.voiceSttModelPath.length > 0)
                text: i18n("Download")
                icon.name: "download"
                onClicked: {
                    let helperPath = MainDatabase.getVoiceHelperPath();
                    let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
                    let payload = JSON.stringify({cmd: "download_stt", model: plasmoid.configuration.voiceSttModel || "large-v3-turbo"});
                    let venvPy = venvPath + "/bin/python3";
                    let cmd = "echo " + Sec.quoteForShell(payload) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath);
                }
            }
        }

        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("STT language:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: voiceLanguageCombo
                Layout.fillWidth: true
                model: ["en", "auto", "es", "fr", "de", "it", "pt", "ru", "ja", "ko", "zh", "ar", "hi"]
                currentIndex: {
                    let l = plasmoid.configuration.voiceLanguage || "en";
                    for (let i = 0; i < model.length; i++) {
                        if (model[i] === l) return i;
                    }
                    return 0;
                }
                onActivated: {
                    plasmoid.configuration.voiceLanguage = currentValue;
                }
            }
        }

        QQC2.Button {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Test STT:")
            text: page.sttTesting ? i18n("Recording...") : i18n("Record & Transcribe")
            icon.name: page.sttTesting ? "media-record" : "audio-input-microphone"
            enabled: !page.sttTesting
            onClicked: {
                page.sttTesting = true;
                page.sttTestResult = "";
                let helperPath = MainDatabase.getVoiceHelperPath();
                let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
                let venvPy = venvPath + "/bin/python3";
                let lang = plasmoid.configuration.voiceLanguage || "en";
                let model = plasmoid.configuration.voiceSttModel || "large-v3-turbo";
                let modelPath = plasmoid.configuration.voiceSttModelPath || "";
                let payload = JSON.stringify({cmd: "start_stt", duration: 10, language: lang, model: model, model_path: modelPath});
                let cmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payload) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payload) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
                voicePageDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #voice-test-stt-" + Date.now());
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

        // ── Text-to-Speech ────────────────────────────────────────────
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
                id: voiceTtsModelPathField
                Layout.fillWidth: true
                placeholderText: i18n("Leave empty to use default model")
                text: plasmoid.configuration.voiceTtsModelPath || ""
                onEditingFinished: {
                    plasmoid.configuration.voiceTtsModelPath = text;
                }
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
                visible: !(plasmoid.configuration.voiceTtsModelPath && plasmoid.configuration.voiceTtsModelPath.length > 0)
                text: i18n("Download")
                icon.name: "download"
                onClicked: {
                    let helperPath = MainDatabase.getVoiceHelperPath();
                    let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
                    let payload = JSON.stringify({cmd: "download_tts", voice: plasmoid.configuration.voiceTtsVoice || "af_heart"});
                    let venvPy = venvPath + "/bin/python3";
                    let cmd = "echo " + Sec.quoteForShell(payload) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath);
                }
            }
        }

        RowLayout {
            visible: voiceEnabledToggle.checked && voiceTtsEnabledToggle.checked
            Kirigami.FormData.label: i18n("TTS voice:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: voiceTtsVoiceCombo
                Layout.fillWidth: true
                model: ["af_heart", "af_bella", "af_nicole", "af_sarah", "af_sky", "am_adam", "am_michael", "bf_emma", "bf_isabella", "bm_george", "bm_lewis"]
                currentIndex: {
                    let v = plasmoid.configuration.voiceTtsVoice || "af_heart";
                    for (let i = 0; i < model.length; i++) {
                        if (model[i] === v) return i;
                    }
                    return 0;
                }
                onActivated: {
                    plasmoid.configuration.voiceTtsVoice = currentValue;
                }
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
                    let helperPath = MainDatabase.getVoiceHelperPath();
                    let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
                    let venvPy = venvPath + "/bin/python3";
                    let voice = plasmoid.configuration.voiceTtsVoice || "af_heart";
                    let payload = JSON.stringify({cmd: "tts", text: i18n("Hello! This is a test of the text to speech system."), voice: voice, lang_code: "a"});
                    let cmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payload) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payload) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
                    voicePageDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #voice-test-tts-" + Date.now());
                }
            }

            QQC2.Button {
                text: i18n("Stop")
                icon.name: "media-playback-stop"
                visible: page.ttsPlaying
                onClicked: {
                    let helperPath = MainDatabase.getVoiceHelperPath();
                    let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
                    let venvPy = venvPath + "/bin/python3";
                    let payload = JSON.stringify({cmd: "stop_tts"});
                    let cmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payload) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payload) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi";
                    voicePageDs.connectSource("sh -c " + Sec.quoteForShell(cmd) + " #voice-test-stoptts-" + Date.now());
                }
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
                onEditingFinished: {
                    plasmoid.configuration.voiceVenvPath = text;
                }
            }
        }
    }

    Connections {
        target: plasmoid.configuration

        function onVoiceSttModelPathChanged() {
            page.voiceEnvChecked = false;
        }
        function onVoiceTtsModelPathChanged() {
            page.voiceEnvChecked = false;
        }
    }
}
