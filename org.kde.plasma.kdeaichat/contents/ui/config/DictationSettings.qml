// Settings → Voice, dictation part: PLACEHOLDER while speech-to-text is
// rebuilt (Phase 6: an on-demand faster-whisper service, whisper.cpp, a
// speech server or a custom command). It keeps today's engine working: its
// model folder, language, GPU switch, check/repair and a 5-second test.
// The values are the page's cfg_ properties (aliases to the ones below).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: dictation

    property bool active: false
    property string espeakPath: ""
    property alias gpu: gpuCheck.checked
    property alias autoSend: autoSendCheck.checked
    property alias sttPath: sttField.text
    property alias venvPath: venvField.text
    property string language: "auto"
    readonly property alias engine: voice

    readonly property var languages: [
        {"text": i18n("Detect automatically"), "value": "auto"}, {"text": i18n("English"), "value": "en"},
        {"text": i18n("Hindi"), "value": "hi"}, {"text": i18n("Spanish"), "value": "es"},
        {"text": i18n("French"), "value": "fr"}, {"text": i18n("German"), "value": "de"},
        {"text": i18n("Japanese"), "value": "ja"}, {"text": i18n("Korean"), "value": "ko"},
        {"text": i18n("Chinese"), "value": "zh"}]

    Layout.fillWidth: true
    Component.onCompleted: if (active) voice.check()

    VoiceEngine {
        id: voice
        venvPath: venvField.text || "~/.local/share/kdeaichat/venv"
        espeakPath: dictation.espeakPath
        sttPath: sttField.text
        language: dictation.language
        gpu: gpuCheck.checked
        voiceEnabled: dictation.active
    }

    FolderDialog {
        id: folderDialog
        onAccepted: {
            sttField.text = decodeURIComponent(String(selectedFolder).replace(/^file:\/\//, ""));
            voice.check();
        }
    }

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        Layout.maximumWidth: Kirigami.Units.gridUnit * 26
        visible: true
        type: Kirigami.MessageType.Information
        text: i18n("Dictation is being rebuilt: you will soon pick its engine and model here. Until then it uses the local Whisper engine below.")
    }

    Kirigami.FormLayout {
        Layout.fillWidth: true

        RowLayout {
            Kirigami.FormData.label: i18n("Speech model folder:")
            QQC2.TextField {
                id: sttField
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 14
                placeholderText: i18n("Empty: download the default model")
                onEditingFinished: voice.check()
            }
            QQC2.Button {
                icon.name: "document-open-folder"
                onClicked: folderDialog.open()
                Accessible.name: i18n("Choose the speech model folder")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: Accessible.name
            }
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Spoken language:")
            textRole: "text"
            valueRole: "value"
            model: dictation.languages
            currentIndex: count > 0 ? Math.max(0, indexOfValue(dictation.language)) : -1
            onActivated: dictation.language = currentValue
        }

        QQC2.CheckBox {
            id: autoSendCheck
            text: i18n("Send the transcript right away")
        }

        QQC2.CheckBox {
            id: gpuCheck
            text: i18n("Use an NVIDIA GPU (CUDA)")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Needs Repair to install the CUDA packages (about 3 GB). Other GPUs are not supported.")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Status:")
            QQC2.BusyIndicator {
                visible: voice.checking || voice.repairing
                running: visible
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            QQC2.Label {
                Layout.maximumWidth: Kirigami.Units.gridUnit * 20
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
                text: voice.sttTesting ? i18n("Stop") : i18n("Record 5 Seconds")
                icon.name: voice.sttTesting ? "media-playback-stop" : "audio-input-microphone"
                onClicked: voice.sttTesting ? voice.cancelStt() : voice.testStt()
            }
        }

        VoiceStatusGrid {
            visible: voice.env !== null
            env: voice.env || ({})
            gpu: gpuCheck.checked
        }

        QQC2.Label {
            visible: voice.sttResult !== ""
            Kirigami.FormData.label: i18n("Heard:")
            Layout.maximumWidth: Kirigami.Units.gridUnit * 22
            wrapMode: Text.Wrap
            text: voice.sttResult
        }

        QQC2.TextField {
            id: venvField
            Kirigami.FormData.label: i18n("Engine folder:")
            Layout.fillWidth: true
            placeholderText: "~/.local/share/kdeaichat/venv"
            onEditingFinished: voice.check()
        }
    }
}
