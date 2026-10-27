// Settings → Voice, dictation part: the engine (Speech Note, the default, or
// a speech server), that engine's options, the language of the speech
// server, and a Test button that sends a bundled recording to the server (no
// microphone).
//
// The values are the page's cfg_ properties (`form.optionValue(key)` /
// `form.setOption(key, value)`); the speech server's key goes to KWallet
// (entry stt-remote), never into the settings.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../voice/SttEngines.js" as SttEngines
import "../voice/SttConfig.js" as SttConfig

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: dictation

    // The page's form, so the label columns line up (forms are siblings, never nested).
    property var twin: null

    property var form: null          // the settings page
    property var keyStore: null      // store/Wallet.qml
    property alias setup: sttSetup
    property var runHelper: null
    property var payload: ({})
    property bool active: false
    property var speechNote: null    // config/SpeechNoteStatus.qml

    // A saved engine that no longer exists counts as Speech Note (the widget moves it at start).
    readonly property string engineId: SttConfig.migratedEngine(form ? form.optionValue("sttEngine") : "")
    readonly property var engine: SttEngines.engine(engineId)
    readonly property bool isServer: engineId === "remote"

    readonly property var allOptions: {
        var out = [];
        SttEngines.engines.forEach(function(e) {
            e.options.forEach(function(o) { out.push(Object.assign({"engine": e.id}, o)); });
        });
        return out;
    }

    function optionValue(key) { return form ? form.optionValue(key) : undefined; }
    function setOption(key, value) {
        if (form)
            form.setOption(key, value);
    }

    SttSetup {
        id: sttSetup
        runHelper: dictation.runHelper
        payload: dictation.payload
    }

    Kirigami.FormLayout {
        twinFormLayouts: dictation.twin ? [dictation.twin] : []
        Layout.fillWidth: true

        QQC2.ComboBox {
            id: engineCombo
            objectName: "sttEngineCombo"
            Kirigami.FormData.label: i18n("Engine:")
            textRole: "text"
            valueRole: "value"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
            model: SttEngines.engines.map(function(e) { return {"value": e.id, "text": i18n(e.label)}; })
            currentIndex: model.map(function(o) { return o.value; }).indexOf(dictation.engineId)
            onActivated: dictation.setOption("sttEngine", currentValue)
        }

        SettingHelp {
            objectName: "sttEngineNote"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            details: i18n("The engine is the program that turns your speech into text. Speech Note works on this computer and keeps your voice private; a speech server gets the recording.")
            text: i18n(dictation.engine.note)
        }
    }

    SpeechNotePanel {
        objectName: "speechNoteDictation"
        role: "stt"
        form: dictation
        status: dictation.speechNote
        twin: dictation.twin
        visible: dictation.engineId === "speechnote" && !!dictation.speechNote
        active: visible && dictation.active
    }

    Kirigami.FormLayout {
        twinFormLayouts: dictation.twin ? [dictation.twin] : []
        Layout.fillWidth: true

        // The speech server's options, made once; only the chosen engine's show.
        Repeater {
            model: dictation.allOptions
            delegate: TtsOption {
                form: dictation
                keyStore: dictation.keyStore
                engineId: modelData.engine
                visible: engineId === dictation.engineId
            }
        }

        QQC2.ComboBox {
            objectName: "sttLanguageCombo"
            visible: dictation.isServer
            Kirigami.FormData.label: i18n("Spoken language:")
            textRole: "text"
            valueRole: "value"
            model: SttEngines.languages.map(function(l) { return {"value": l.value, "text": i18n(l.text)}; })
            currentIndex: Math.max(0, model.map(function(o) { return o.value; }).indexOf(String(dictation.optionValue("sttLanguage") || "auto")))
            onActivated: dictation.setOption("sttLanguage", currentValue)
        }

        SettingHelp {
            visible: dictation.isServer
            text: i18n("The language you speak. \"Detect automatically\" works for most people; choosing yours helps with short phrases.")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Try it:")
            visible: dictation.isServer
            QQC2.Button {
                objectName: "sttTestButton"
                text: i18n("Test")
                icon.name: "audio-input-microphone"
                enabled: !sttSetup.testing && String(dictation.optionValue("sttRemoteUrl") || "") !== ""
                onClicked: sttSetup.test()
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Sends a short recording that comes with the widget to the server, with the settings above.")
            }
            QQC2.BusyIndicator {
                visible: sttSetup.testing
                running: visible
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
            QQC2.Label {
                objectName: "sttTestResult"
                text: sttSetup.testResult
                wrapMode: Text.Wrap
                Layout.preferredWidth: Kirigami.Units.gridUnit * 18
            }
        }

        SettingHelp {
            visible: dictation.isServer
            text: i18n("Checks the settings above with a short recording that comes with the widget; no microphone needed.")
        }

        QQC2.CheckBox {
            text: i18n("Send the transcript right away")
            checked: dictation.optionValue("voiceAutoSend") !== false
            onToggled: dictation.form.setOption("voiceAutoSend", checked)
        }

        SettingHelp {
            text: i18n("On: what you said is sent as soon as you stop talking. Off: it waits in the message box so you can check or change it first.")
        }
    }
}
