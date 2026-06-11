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

    property bool voiceEnvChecked: false
    property var voiceEnvResult: null
    property bool ttsPlaying: false
    property bool sttTesting: false
    property string sttTestResult: ""
    property string storageExportStatus: ""
    property string copiedText: ""
    property string recordedAudioPath: ""

    // Computed binding — QML tracks dependencies (copiedText, voiceEnvChecked, voiceEnvResult)
    property string statusText: {
        if (copiedText === "copied") return i18n("Copied command");
        if (copiedText === "copying") return i18n("Copying...");
        if (copiedText === "error") return i18n("Copy failed — check system clipboard");
        if (!voiceEnvChecked) return i18n("Not checked — click Check Status");
        var r = voiceEnvResult;
        var ok = r && (r.stt_ready || r.faster_whisper_ok) && r.sounddevice_ok;
        if (ok) return i18n("Environment ready");
        return i18n("Needs setup — copy and run the setup command");
    }
    property color statusColor: {
        if (copiedText === "copied") return Kirigami.Theme.positiveTextColor;
        if (copiedText === "copying") return Kirigami.Theme.neutralTextColor;
        if (copiedText === "error") return Kirigami.Theme.negativeTextColor;
        if (!voiceEnvChecked) return Kirigami.Theme.textColor;
        var r = voiceEnvResult;
        var ok = r && (r.stt_ready || r.faster_whisper_ok) && r.sounddevice_ok;
        if (ok) return Kirigami.Theme.positiveTextColor;
        return Kirigami.Theme.negativeTextColor;
    }

    Timer {
        id: copiedTimer
        interval: 2000
        onTriggered: page.copiedText = ""
    }

    Timer {
        id: sttTimer
        interval: 5000
        onTriggered: {
            page.sttTesting = false;
            sendVoiceCommand(JSON.stringify({cmd: "stop_stt"}));
        }
    }

    property string cfg_promptTemplates: plasmoid.configuration.promptTemplates || "[]"
    property bool cfg_showInteractiveGuides: plasmoid.configuration.showInteractiveGuides
    onCfg_showInteractiveGuidesChanged: {
        plasmoid.configuration.showInteractiveGuides = cfg_showInteractiveGuides;
    }
    property alias cfg_voiceEnabled: voiceEnabledToggle.checked
    property alias cfg_voiceTtsEnabled: voiceTtsEnabledToggle.checked
    property alias cfg_voiceAutoSend: voiceAutoSendToggle.checked

    P5Support.DataSource {
        id: voicePageDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            let stdout = (data["stdout"] || "").trim();
            let stderr = (data["stderr"] || "").trim();
            let exitCode = data["exit code"];
            if (stdout !== "") {
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
            if (exitCode !== undefined && exitCode !== 0) {
                sttTesting = false;
                ttsPlaying = false;
            }
            disconnectSource(sourceName);
        }
    }

    function handleVoicePageResponse(resp, sourceName) {
        if (resp.type === "env_check") {
            voiceEnvResult = resp;
            voiceEnvChecked = true;
        } else if (resp.type === "copy_result") {
            copiedText = resp.ok ? "copied" : "error";
            copiedTimer.restart();
        } else if (resp.type === "stt_result") {
            sttTesting = false;
            sttTimer.stop();
            sttTestResult = resp.text || i18n("(no speech detected)");
            if (resp.audio_path) {
                recordedAudioPath = resp.audio_path;
            }
        } else if (resp.type === "stt_error") {
            sttTesting = false;
            sttTimer.stop();
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
        let path = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
        if (path.charAt(0) === "~") {
            path = Qt.homePath + path.substring(1);
        }
        return path;
    }

    function getVenvPython() {
        let venvPath = getVenvPath();
        return venvPath + "/bin/python3";
    }

    function getHelperPath() {
        let base = Qt.resolvedUrl("./voice/voice_helper.py");
        if (base === "") return "";
        if (base.indexOf("file://") === 0) {
            base = base.substring(7);
            try { base = decodeURIComponent(base); } catch (e) {}
        }
        return base;
    }

    function getSetupPath() {
        let base = Qt.resolvedUrl("./voice/voice_setup.sh");
        if (base === "") return "";
        if (base.indexOf("file://") === 0) {
            base = base.substring(7);
            try { base = decodeURIComponent(base); } catch (e) {}
        }
        return base;
    }

    function getSetupCommand() {
        let setupPath = getSetupPath();
        let venvPath = getVenvPath();
        if (setupPath === "") return i18n("Installation path not found — reinstall widget");
        return "bash " + Sec.quoteForShell(setupPath) + " " + Sec.quoteForShell(venvPath);
    }

    function commandCopied() {
        let cmd = getSetupCommand();
        if (cmd === "") {
            copiedText = "error";
            copiedTimer.restart();
            return;
        }
        copiedText = "copying";
        let okPayload = JSON.stringify({type: "copy_result", ok: true});
        let failPayload = JSON.stringify({type: "copy_result", ok: false, error: "No clipboard tool"});
        let copyCmd = "(printf %s " + Sec.quoteForShell(cmd) + " | wl-copy 2>/dev/null || printf %s " + Sec.quoteForShell(cmd) + " | xclip -selection clipboard 2>/dev/null || printf %s " + Sec.quoteForShell(cmd) + " | xsel -b 2>/dev/null) && echo " + Sec.quoteForShell(okPayload) + " || echo " + Sec.quoteForShell(failPayload) + " #voice-copy-" + Date.now();
        voicePageDs.connectSource(copyCmd);
    }

    function runInTerminal(payload) {
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let innerCmd = "echo " + Sec.quoteForShell(JSON.stringify(payload)) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; echo; read -p 'Press Enter to close...'";
        let cmd = "if command -v konsole >/dev/null 2>&1; then konsole --hold -e bash -c " + Sec.quoteForShell(innerCmd) + "; elif command -v x-terminal-emulator >/dev/null 2>&1; then x-terminal-emulator -e bash -c " + Sec.quoteForShell(innerCmd) + "; fi #voice-term-" + Date.now();
        voicePageDs.connectSource(cmd);
    }

    function runEnvCheck() {
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let sttPath = plasmoid.configuration.voiceSttModelPath || "";
        let ttsPath = plasmoid.configuration.voiceTtsModelPath || "";
        let payload = JSON.stringify({cmd: "check_env", stt_model_path: sttPath, tts_model_path: ttsPath});
        let cmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payload) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payload) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi #voice-env-" + Date.now();
        voicePageDs.connectSource(cmd);
    }

    function sendVoiceCommand(payload) {
        let helperPath = getHelperPath();
        let venvPy = getVenvPython();
        let cmd = "if [ -f " + Sec.quoteForShell(venvPy) + " ]; then echo " + Sec.quoteForShell(payload) + " | " + Sec.quoteForShell(venvPy) + " " + Sec.quoteForShell(helperPath) + "; else echo " + Sec.quoteForShell(payload) + " | python3 " + Sec.quoteForShell(helperPath) + "; fi #voice-cmd-" + Date.now();
        voicePageDs.connectSource(cmd);
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

    Kirigami.FormLayout {
        id: formLayout
        width: page.availableWidth

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
                    text: "<b>Prompt Templates</b> let you save frequently used system prompts.<br>" +
                          "Each template you create becomes a <b>slash command</b> in the chat.<br><br>" +
                          "<b>How to use:</b><br>" +
                          "1. Give your template a <b>name</b> (e.g. \"code-reviewer\").<br>" +
                          "2. Write the <b>system prompt</b> for that template.<br>" +
                          "3. In chat, type <b>/code-reviewer</b> and send — the AI will use that system prompt.<br><br>" +
                          "<b>Examples:</b><br>" +
                          "• Name: <code>translator</code> → Prompt: <i>You are a professional translator...</i><br>" +
                          "• Name: <code>code-review</code> → Prompt: <i>Review this code for bugs...</i><br>" +
                          "• Name: <code>summarize</code> → Prompt: <i>Summarize the following text...</i>"
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
                    if (!newTemplateName.text.trim()) return;
                    let arr = JSON.parse(page.cfg_promptTemplates || "[]");
                    arr.push({"name": newTemplateName.text.trim(), "prompt": newTemplatePrompt.text.trim()});
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
                    text: "<b>Voice features</b> let you speak to the AI and hear responses read aloud.<br>" +
                          "Click <b>Copy Setup Command</b> and run it in your terminal to install dependencies.<br><br>" +
                          "<b>How to use:</b><br>" +
                          "1. <b>Enable</b> voice features below.<br>" +
                          "2. <b>Copy</b> and run the setup command in your terminal.<br>" +
                          "3. Click <b>Check Status</b> to verify installation.<br>" +
                          "4. Click the <b>microphone</b> button in chat to record voice input.<br><br>" +
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
        }

        // ── Status ──────────────────────────────────────────────────
        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Status:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.8
                text: page.statusText
                color: page.statusColor
            }

            QQC2.Button {
                text: i18n("Check Status")
                icon.name: "view-refresh"
                onClicked: runEnvCheck()
            }
        }

        // ── Copy Setup Command ──────────────────────────────────────
        RowLayout {
            visible: voiceEnabledToggle.checked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: copiedText === "copied" ? i18n("Copied!") : copiedText === "copying" ? i18n("Copying...") : i18n("Copy Setup Command")
                icon.name: copiedText === "copied" ? "dialog-ok-apply" : "edit-copy"
                enabled: getSetupCommand() !== ""
                onClicked: page.commandCopied()
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
                onClicked: runInTerminal({cmd: "download_stt", model: plasmoid.configuration.voiceSttModel || "large-v3-turbo"})
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
                    page.recordedAudioPath = "";
                    let lang = plasmoid.configuration.voiceLanguage || "en";
                    let model = plasmoid.configuration.voiceSttModel || "large-v3-turbo";
                    let modelPath = plasmoid.configuration.voiceSttModelPath || "";
                    sendVoiceCommand(JSON.stringify({cmd: "start_stt", duration: 5, language: lang, model: model, model_path: modelPath}));
                    sttTimer.start();
                }
            }

            QQC2.Button {
                text: i18n("Play Recording")
                icon.name: "media-playback-start"
                visible: page.recordedAudioPath !== ""
                onClicked: {
                    sendVoiceCommand(JSON.stringify({cmd: "play_audio", path: page.recordedAudioPath}));
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
            Kirigami.FormData.label: i18n("Auto-send voice input:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            id: voiceAutoSendToggle
            checked: plasmoid.configuration.voiceAutoSend !== undefined ? plasmoid.configuration.voiceAutoSend : true
            text: checked ? i18n("Enabled — transcribed text is sent automatically") : i18n("Disabled — transcribed text goes to input field")
        }

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
                onClicked: runInTerminal({cmd: "download_tts", voice: plasmoid.configuration.voiceTtsVoice || "af_heart"})
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
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

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
                        if (p === "") return "";
                        if (p.indexOf("file://") === 0) {
                            p = decodeURIComponent(p.slice(7));
                        }
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
                    if (dir.indexOf("file://") === 0) {
                        dir = decodeURIComponent(dir.slice(7));
                    }
                    let file = dir.endsWith("/") ? dir + "kdeaichat_history.json" : dir + "/kdeaichat_history.json";
                    let jsonStr = plasmoid.configuration.chatSessionsJson || "[]";
                    let b64 = Qt.btoa(unescape(encodeURIComponent(jsonStr)));
                    let cmd = "python3 -c \"import base64, os; path=os.path.expanduser(" + Sec.quoteForShell(file) + "); os.makedirs(os.path.dirname(path), exist_ok=True); " +
                        "open(path, 'w', encoding='utf-8').write(base64.b64decode(" + Sec.quoteForShell(b64) + ").decode('utf-8')); print('OK')\"";
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
                    if (dir.indexOf("file://") === 0) {
                        dir = decodeURIComponent(dir.slice(7));
                    }
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
            text: customHistoryPathField.text.trim() === ""
                ? i18n("Chats are saved in the default KDE config location. Select a folder above to store them elsewhere (e.g. a synced cloud drive).")
                : i18n("<b>Warning: Beta feature.</b> After changing this path, press <b>Apply</b> or <b>OK</b> — your chats will automatically be exported to the new location.")
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
                        } catch(e) { return []; }
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
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing / 2

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
                            anchors { right: parent.right; top: parent.top; margins: Kirigami.Units.smallSpacing }
                            icon.name: "edit-delete"
                            QQC2.ToolTip.text: i18n("Delete template")
                            onClicked: {
                                let arr = JSON.parse(page.cfg_promptTemplates || "[]");
                                arr.splice(index, 1);
                                page.cfg_promptTemplates = JSON.stringify(arr);
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
