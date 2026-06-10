import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
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

    // cfg_ aliases for config bindings
    property alias cfg_promptTemplates: page.promptTemplatesValue
    property string promptTemplatesValue: plasmoid.configuration.promptTemplates || "[]"
    property alias cfg_voiceEnabled: voiceEnabledToggle.checked
    property alias cfg_voiceTtsEnabled: voiceTtsEnabledToggle.checked
    property alias cfg_voiceAutoSend: voiceAutoSendToggle.checked
    property string cfg_voiceSttModel: plasmoid.configuration.voiceSttModel || "large-v3-turbo"
    property string cfg_voiceTtsModel: plasmoid.configuration.voiceTtsModel || "kokoro-82m"
    property string cfg_voiceSttModelPath: plasmoid.configuration.voiceSttModelPath || ""
    property string cfg_voiceTtsModelPath: plasmoid.configuration.voiceTtsModelPath || ""
    property string cfg_voiceLanguage: plasmoid.configuration.voiceLanguage || "en"
    property string cfg_voiceTtsVoice: plasmoid.configuration.voiceTtsVoice || "af_heart"
    property string cfg_voiceVenvPath: plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv"

    Kirigami.FormLayout {
        id: formLayout
        width: page.availableWidth

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
                        page.promptTemplatesValue = page.cfg_promptTemplates;
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
                    page.promptTemplatesValue = page.cfg_promptTemplates;
                    newTemplateName.text = "";
                    newTemplatePrompt.text = "";
                }
            }
        }

        // ── Voice & Audio (Experimental) ──────────────────────────────
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Voice & Audio (Experimental)")
        }

        QQC2.Label {
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            wrapMode: Text.Wrap
            opacity: 0.72
            font: Kirigami.Theme.smallFont
            text: i18n("Speech-to-text and text-to-speech. Requires Python venv with faster-whisper and kokoro.")
        }

        QQC2.CheckBox {
            id: voiceEnabledToggle
            Kirigami.FormData.label: i18n("Enable voice features:")
            Layout.maximumWidth: formLayout.fieldMaxWidth
            checked: plasmoid.configuration.voiceEnabled || false
            text: checked ? i18n("Enabled — mic button appears in chat") : i18n("Disabled")
        }

        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Setup:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                id: voiceSetupButton
                text: i18n("Setup Voice Environment")
                icon.name: "setup"
                onClicked: {
                    let setupPath = MainDatabase.getVoiceSetupPath();
                    let venvPath = plasmoid.configuration.voiceVenvPath || "~/.local/share/kdeaichat/venv";
                    let cmd = "bash " + Sec.quoteForShell(setupPath) + " " + Sec.quoteForShell(venvPath);
                    voiceSetupButton.text = i18n("Installing...");
                    voiceSetupButton.enabled = false;
                }
            }

            QQC2.Button {
                text: i18n("Check Environment")
                icon.name: "dialog-ok"
                onClicked: {
                    MainDatabase.checkVoiceEnv();
                }
            }
        }

        Rectangle {
            visible: voiceEnabledToggle.checked && page.voiceEnvChecked
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            implicitHeight: voiceEnvGrid.implicitHeight + Kirigami.Units.gridUnit
            radius: 6
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
            border.width: 1

            GridLayout {
                id: voiceEnvGrid
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.margins: Kirigami.Units.gridUnit * 0.6
                columns: 2

                QQC2.Label { text: i18n("Microphone:"); font.bold: true }
                QQC2.Label { text: page.voiceEnvResult && page.voiceEnvResult.mic_available ? "✓ " + i18n("Available") : "✗ " + i18n("Not found") }

                QQC2.Label { text: i18n("Audio player:"); font.bold: true }
                QQC2.Label { text: page.voiceEnvResult && (page.voiceEnvResult.paplay_available || page.voiceEnvResult.aplay_available) ? "✓ " + i18n("Available") : "✗ " + i18n("Install pulseaudio-utils") }

                QQC2.Label { text: i18n("STT engine:"); font.bold: true }
                QQC2.Label { text: page.voiceEnvResult && page.voiceEnvResult.faster_whisper_ok ? "✓ faster-whisper" : "✗ " + i18n("Not installed") }

                QQC2.Label { text: i18n("TTS engine:"); font.bold: true }
                QQC2.Label { text: page.voiceEnvResult && page.voiceEnvResult.kokoro_ok ? "✓ Kokoro" : "✗ " + i18n("Not installed") }

                QQC2.Label { text: i18n("espeak-ng:"); font.bold: true }
                QQC2.Label { text: page.voiceEnvResult && page.voiceEnvResult.espeak_available ? "✓ " + i18n("Available") : "✗ " + i18n("Install espeak-ng") }
            }
        }

        RowLayout {
            visible: voiceEnabledToggle.checked
            Kirigami.FormData.label: i18n("Speech-to-Text:")
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
                text: i18n("Download Model")
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
            Kirigami.FormData.label: i18n("STT model path:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: voiceSttModelPathField
                Layout.fillWidth: true
                placeholderText: i18n("Leave empty for default (HuggingFace cache)")
                text: plasmoid.configuration.voiceSttModelPath || ""
                onEditingFinished: {
                    plasmoid.configuration.voiceSttModelPath = text;
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
            Kirigami.FormData.label: i18n("Text-to-Speech:")
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: voiceTtsModelCombo
                Layout.fillWidth: true
                model: ["kokoro-82m"]
                currentIndex: 0
            }

            QQC2.Button {
                text: i18n("Download TTS Model")
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
            Layout.fillWidth: true
            Layout.maximumWidth: formLayout.fieldMaxWidth
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: i18n("Test Voice")
                icon.name: "audio-speakers"
                onClicked: {
                    MainDatabase.triggerTts(i18n("Hello! This is a test of the text to speech system."));
                }
            }

            QQC2.Button {
                text: i18n("Stop")
                icon.name: "media-playback-stop"
                visible: page.ttsPlaying
                onClicked: {
                    MainDatabase.stopTts();
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
    }
}
