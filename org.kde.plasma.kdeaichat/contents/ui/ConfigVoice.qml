// Settings → Voice: speech-to-text (microphone button) and read-aloud, run
// by a local engine (faster-whisper, Kokoro/Piper) in its own Python venv.
// Turning voice or read-aloud on or off takes effect right away, because it
// also installs or stops the systemd user services.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "config" as Config

// i18n() and plasmoid are provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    property alias cfg_voiceEnabled: enabledCheck.checked
    property alias cfg_voiceGpuEnabled: gpuCheck.checked
    property alias cfg_voiceTtsEnabled: ttsCheck.checked
    property alias cfg_voiceTtsAuto: ttsAutoCheck.checked
    property alias cfg_voiceAutoSend: autoSendCheck.checked
    property alias cfg_voiceSttModelPath: sttField.text
    property alias cfg_voiceTtsModelPath: ttsField.text
    property alias cfg_voiceTtsVoice: voiceField.text
    property alias cfg_voiceVenvPath: venvField.text
    property string cfg_voiceLanguage: "auto"

    readonly property var configuration: typeof plasmoid !== "undefined" && plasmoid ? plasmoid.configuration : null
    readonly property var languages: [
        {"text": i18n("Detect automatically"), "value": "auto"}, {"text": i18n("English"), "value": "en"},
        {"text": i18n("Hindi"), "value": "hi"}, {"text": i18n("Spanish"), "value": "es"},
        {"text": i18n("French"), "value": "fr"}, {"text": i18n("German"), "value": "de"},
        {"text": i18n("Japanese"), "value": "ja"}, {"text": i18n("Korean"), "value": "ko"},
        {"text": i18n("Chinese"), "value": "zh"}]

    // Saved at once, since the services were just changed to match.
    function saveNow(name, value) {
        if (configuration)
            configuration[name] = value;
    }

    function folderPath(url) {
        return decodeURIComponent(String(url).replace(/^file:\/\//, ""));
    }

    Component.onCompleted: if (enabledCheck.checked) voice.check()

    Config.VoiceEngine {
        id: voice
        venvPath: venvField.text || "~/.local/share/kdeaichat/venv"
        espeakPath: page.configuration ? String(page.configuration.voiceEspeakPath || "") : ""
        sttPath: sttField.text
        ttsPath: ttsField.text
        ttsVoice: voiceField.text
        language: page.cfg_voiceLanguage
        gpu: gpuCheck.checked
        voiceEnabled: enabledCheck.checked
        ttsEnabled: ttsCheck.checked
    }

    FolderDialog {
        id: folderDialog
        property var field: null
        onAccepted: {
            field.text = page.folderPath(selectedFolder);
            voice.check();
        }
    }

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: enabledCheck
            Kirigami.FormData.label: i18n("Voice input:")
            text: i18n("Show a microphone button in the chat")
            onToggled: {
                page.saveNow("voiceEnabled", checked);
                if (checked) {
                    voice.installServices();
                    voice.check();
                } else {
                    voice.disableServices(false);
                }
            }
        }

        QQC2.CheckBox {
            id: gpuCheck
            enabled: enabledCheck.checked
            text: i18n("Use an NVIDIA GPU (CUDA)")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Needs Repair to install the CUDA packages (about 3 GB). Other GPUs are not supported.")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Speech model folder:")
            enabled: enabledCheck.checked
            QQC2.TextField {
                id: sttField
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 16
                placeholderText: i18n("Empty: download the default model")
                onEditingFinished: voice.check()
            }
            QQC2.Button {
                icon.name: "document-open-folder"
                onClicked: { folderDialog.field = sttField; folderDialog.open(); }
                Accessible.name: i18n("Choose the speech model folder")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: Accessible.name
            }
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Spoken language:")
            enabled: enabledCheck.checked
            textRole: "text"
            valueRole: "value"
            model: page.languages
            currentIndex: count > 0 ? Math.max(0, indexOfValue(page.cfg_voiceLanguage)) : -1
            onActivated: page.cfg_voiceLanguage = currentValue
        }

        QQC2.CheckBox {
            id: autoSendCheck
            enabled: enabledCheck.checked
            text: i18n("Send the transcript right away")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Read aloud")
        }

        QQC2.CheckBox {
            id: ttsCheck
            Kirigami.FormData.label: i18n("Read aloud:")
            enabled: enabledCheck.checked
            text: i18n("Let replies be read aloud")
            onToggled: {
                page.saveNow("voiceTtsEnabled", checked);
                if (checked)
                    voice.installServices();
                else
                    voice.disableServices(true);
                voice.check();
            }
        }

        QQC2.CheckBox {
            id: ttsAutoCheck
            enabled: enabledCheck.checked && ttsCheck.checked
            text: i18n("Read every reply automatically")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Voice model folder:")
            enabled: enabledCheck.checked && ttsCheck.checked
            QQC2.TextField {
                id: ttsField
                Layout.fillWidth: true
                placeholderText: i18n("Empty: download the default model")
                onEditingFinished: voice.check()
            }
            QQC2.Button {
                icon.name: "document-open-folder"
                onClicked: { folderDialog.field = ttsField; folderDialog.open(); }
                Accessible.name: i18n("Choose the voice model folder")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: Accessible.name
            }
        }

        QQC2.TextField {
            id: voiceField
            Kirigami.FormData.label: i18n("Voice:")
            enabled: enabledCheck.checked && ttsCheck.checked
            placeholderText: i18n("Voice id, e.g. af_heart")
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Engine")
            visible: enabledCheck.checked
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Status:")
            visible: enabledCheck.checked
            Layout.fillWidth: true
            QQC2.BusyIndicator {
                visible: voice.checking || voice.repairing
                running: visible
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 22
                wrapMode: Text.Wrap
                text: voice.status || i18n("Not checked yet.")
                color: voice.ready ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.textColor
            }
        }

        QQC2.ProgressBar {
            visible: voice.repairing && voice.progress > 0
            from: 0
            to: 100
            value: voice.progress
        }

        RowLayout {
            visible: enabledCheck.checked
            QQC2.Button {
                text: i18n("Check")
                icon.name: "view-refresh"
                enabled: !voice.checking && !voice.repairing
                onClicked: voice.check()
            }
            QQC2.Button {
                text: i18n("Repair")
                icon.name: "tools-wizard"
                visible: voice.repairNeeded
                enabled: !voice.repairing
                onClicked: voice.repair()
            }
            QQC2.Button {
                text: i18n("Setup Help")
                icon.name: "help-contents"
                onClicked: Qt.openUrlExternally("https://github.com/racstan/KDE-AI-Chat/blob/master/VOICE_SETUP.md")
            }
        }

        Config.VoiceStatusGrid {
            visible: enabledCheck.checked && voice.env !== null
            env: voice.env || ({})
            ttsEnabled: ttsCheck.checked
            gpu: gpuCheck.checked
            espeakMissing: voice.espeakMissing
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Try it:")
            visible: enabledCheck.checked
            QQC2.Button {
                text: voice.sttTesting ? i18n("Stop") : i18n("Record 5 Seconds")
                icon.name: voice.sttTesting ? "media-playback-stop" : "audio-input-microphone"
                enabled: voice.sttTesting || !voice.ttsPlaying
                onClicked: voice.sttTesting ? voice.cancelStt() : voice.testStt()
            }
            QQC2.Button {
                visible: ttsCheck.checked
                text: voice.ttsPlaying ? i18n("Stop") : i18n("Speak a Sentence")
                icon.name: voice.ttsPlaying ? "media-playback-stop" : "audio-speakers"
                enabled: voice.ttsPlaying || !voice.sttTesting
                onClicked: voice.ttsPlaying ? voice.cancelTts() : voice.testTts()
            }
        }

        QQC2.Label {
            visible: enabledCheck.checked && voice.sttResult !== ""
            Kirigami.FormData.label: i18n("Heard:")
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            text: voice.sttResult
        }

        QQC2.Label {
            visible: enabledCheck.checked && ttsCheck.checked && voice.ttsResult !== ""
            Kirigami.FormData.label: i18n("Read aloud:")
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            text: voice.ttsResult
        }

        QQC2.TextField {
            id: venvField
            Kirigami.FormData.label: i18n("Engine folder:")
            visible: enabledCheck.checked
            Layout.fillWidth: true
            placeholderText: "~/.local/share/kdeaichat/venv"
            onEditingFinished: voice.check()
        }
    }
}
