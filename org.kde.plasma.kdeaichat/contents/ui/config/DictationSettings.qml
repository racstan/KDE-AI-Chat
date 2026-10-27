// Settings → Voice, dictation part: the engine (from the helper's
// stt_engines: only engines that work or can be finished here; the others
// are listed with the reason), that engine's options, the language, and a
// Test button that transcribes a bundled recording (no microphone).
//
// The local engines (Parakeet, the default, and faster-whisper) get their own
// rows (config/LocalSttRows.qml): model with sizes and models found on disk,
// device, Install / Download / Remove data, each showing its size first. The values are the page's cfg_ properties
// (`form.optionValue(key)` / `form.setOption(key, value)`); the speech
// server's key goes to KWallet (entry stt-remote), never into the settings.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../voice/SttEngines.js" as SttEngines

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

    readonly property string engineId: form ? String(form.optionValue("sttEngine") || SttEngines.defaultEngine) : SttEngines.defaultEngine
    readonly property var engine: SttEngines.engine(engineId) || SttEngines.engine(SttEngines.defaultEngine)
    readonly property var lists: SttEngines.split(sttSetup.engines)
    readonly property bool engineUsable: !!(sttSetup.engineRow(engineId) || {}).available

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
        if (key !== "sttLanguage")
            recheck.restart();
    }

    onActiveChanged: if (active && !sttSetup.enginesLoaded) sttSetup.refresh()
    Component.onCompleted: if (active) sttSetup.refresh()

    SttSetup {
        id: sttSetup
        runHelper: dictation.runHelper
        payload: dictation.payload
    }

    // Typing a path, URL or command re-checks which engines work (debounced).
    Timer {
        id: recheck
        interval: 700
        onTriggered: { sttSetup.refreshEngines(); sttSetup.estimate(); }
    }

    Kirigami.FormLayout {
        twinFormLayouts: dictation.twin ? [dictation.twin] : []
        Layout.fillWidth: true

        RowLayout {
            Kirigami.FormData.label: i18n("Engine:")
            QQC2.ComboBox {
                id: engineCombo
                objectName: "sttEngineCombo"
                textRole: "text"
                valueRole: "value"
                Layout.minimumWidth: Kirigami.Units.gridUnit * 16
                model: {
                    var list = dictation.lists.choices.map(function(row) {
                        return {"value": row.id, "text": i18n(SttEngines.engine(row.id).label)};
                    });
                    if (sttSetup.enginesLoaded && !list.some(function(r) { return r.value === dictation.engineId; }))
                        list.push({"value": dictation.engineId, "text": i18n("%1 (not available)", i18n(dictation.engine.label))});
                    return list;
                }
                currentIndex: model.map(function(o) { return o.value; }).indexOf(dictation.engineId)
                onActivated: dictation.setOption("sttEngine", currentValue)
            }
            QQC2.BusyIndicator {
                visible: !sttSetup.enginesLoaded
                running: visible
                Layout.preferredHeight: Kirigami.Units.iconSizes.medium
            }
        }

        SettingHelp {
            objectName: "sttEngineNote"
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            details: i18n("The engine is the program that turns your speech into text. The ones on this computer keep your voice private; a speech server gets the recording.")
            text: {
                var row = sttSetup.engineRow(dictation.engineId);
                var note = i18n(dictation.engine.note);
                if (row && !row.available && row.reason && !SttEngines.isLocal(dictation.engineId))
                    note += "\n" + i18n("Not ready: %1", row.reason);
                return note;
            }
        }

        QQC2.Label {
            objectName: "sttUnavailable"
            visible: dictation.lists.unavailable.length > 0
            Kirigami.FormData.label: i18n("Not available:")
            Layout.preferredWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.75
            text: dictation.lists.unavailable.map(function(row) {
                return i18n("%1: %2", i18n(SttEngines.engine(row.id).label), row.reason);
            }).join("\n")
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

    LocalSttRows {
        form: dictation
        setup: sttSetup
        engine: SttEngines.isLocal(dictation.engineId) ? dictation.engineId : SttEngines.localDefault
        shown: SttEngines.isLocal(dictation.engineId)
        twinFormLayouts: dictation.twin ? [dictation.twin] : []
    }

    Kirigami.FormLayout {
        twinFormLayouts: dictation.twin ? [dictation.twin] : []
        Layout.fillWidth: true

        // whisper.cpp: models found on this computer (Speech Note, Handy, whisper.cpp).
        QQC2.ComboBox {
            objectName: "sttGgmlFound"
            readonly property var models: sttSetup.found.filter(function(m) { return m.engine === "whisper-cpp"; })
            visible: dictation.engineId === "whisper-cpp" && models.length > 0
            Kirigami.FormData.label: i18n("Found models:")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
            textRole: "text"
            valueRole: "value"
            model: [{"value": "", "text": i18n("Choose a model found on this computer…")}].concat(models.map(function(m) {
                return {"value": m.model, "text": i18n("%1 (%2, %3)", m.name, m.source, SttEngines.size(m.mb))};
            }))
            currentIndex: Math.max(0, model.map(function(o) { return o.value; }).indexOf(String(dictation.optionValue("sttWhisperCppModel") || "")))
            onActivated: if (currentValue) dictation.setOption("sttWhisperCppModel", currentValue)
        }

        SettingHelp {
            visible: dictation.engineId === "whisper-cpp" && sttSetup.found.some(function(m) { return m.engine === "whisper-cpp"; })
            text: i18n("Speech models other apps on this computer already downloaded. Pick one to use it without downloading again.")
        }

        // The other engines' options, made once; only the chosen engine's show.
        Repeater {
            model: dictation.allOptions
            delegate: TtsOption {
                form: dictation
                keyStore: dictation.keyStore
                engineId: modelData.engine
                visible: engineId === dictation.engineId
            }
        }

        QQC2.Label {
            objectName: "sttEnglishOnly"
            visible: dictation.engineId === "parakeet"
            Kirigami.FormData.label: i18n("Spoken language:")
            text: i18n("English (this model understands English only)")
        }

        QQC2.ComboBox {
            objectName: "sttLanguageCombo"
            visible: dictation.engineId !== "parakeet" && dictation.engineId !== "speechnote"
            Kirigami.FormData.label: i18n("Spoken language:")
            textRole: "text"
            valueRole: "value"
            model: SttEngines.languages.map(function(l) { return {"value": l.value, "text": i18n(l.text)}; })
            currentIndex: Math.max(0, model.map(function(o) { return o.value; }).indexOf(String(dictation.optionValue("sttLanguage") || "auto")))
            onActivated: dictation.setOption("sttLanguage", currentValue)
        }

        SettingHelp {
            visible: dictation.engineId !== "parakeet" && dictation.engineId !== "speechnote"
            text: i18n("The language you speak. \"Detect automatically\" works for most people; choosing yours helps with short phrases.")
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Try it:")
            visible: dictation.engineId !== "speechnote"
            QQC2.Button {
                objectName: "sttTestButton"
                text: i18n("Test")
                icon.name: "audio-input-microphone"
                enabled: dictation.engineUsable && !sttSetup.testing && !sttSetup.busy
                onClicked: sttSetup.test()
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Transcribes a short recording that comes with the widget, with the settings above.")
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
            visible: dictation.engineId !== "speechnote"
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
