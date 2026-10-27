// One setting of a read-aloud engine on Settings → Voice, drawn from its
// type in voice/TtsEngines.js. The value lives in the page's cfg_<key>
// property (`form.optionValue(key)` / `form.setOption(key, value)`), so it
// is saved with OK/Apply like any setting; a "secret" goes to KWallet. Under
// the field is the option's plain explanation (its `help` in the engine list).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../Security.js" as Sec

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

ColumnLayout {
    id: row

    required property var modelData    // the option spec
    property var form: null           // the settings page
    property var voiceProbe: null          // voice/TtsProbe.qml
    property var keyStore: null         // store/Wallet.qml, for "secret"
    property string engineId: ""
    // The engine's chosen language, which narrows its voice list.
    property string language: ""

    readonly property var option: modelData
    readonly property var value: form ? form.optionValue(option.key) : undefined
    function set(v) { if (form) form.setOption(option.key, v); }
    // The field itself (for tests).
    readonly property alias item: field.item

    objectName: "ttsOption-" + (option.key || option.type)
    Kirigami.FormData.label: i18n(option.label) + ":"
    Kirigami.FormData.labelAlignment: Qt.AlignTop
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    Loader {
        id: field
        Layout.fillWidth: true
        sourceComponent: ({"language": choiceField, "voice": choiceField, "rate": sliderField, "pitch": sliderField,
                           "speed": sliderField, "text": textField, "url": textField,
                           "secret": secretField})[row.option.type] || textField
    }

    SettingHelp {
        text: row.option.help ? i18n(row.option.help) : ""
        visible: text !== ""
    }

    Component {
        id: choiceField
        QQC2.ComboBox {
            readonly property bool isLanguage: row.option.type === "language"
            textRole: "text"
            valueRole: "value"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 16
            model: !row.voiceProbe ? [] : isLanguage ? row.voiceProbe.languages(row.engineId, i18n("Engine default"))
                : row.voiceProbe.voiceChoices(row.engineId, row.language, i18n("Engine default"), String(row.value || ""))
            currentIndex: count > 0 ? Math.max(0, indexOfValue(String(row.value || row.option.def || ""))) : -1
            onActivated: row.set(currentValue)
        }
    }

    Component {
        id: sliderField
        RowLayout {
            readonly property bool isSpeed: row.option.type === "speed"
            QQC2.Slider {
                id: slider
                from: parent.isSpeed ? 0.5 : -1
                to: parent.isSpeed ? 2 : 1
                stepSize: 0.1
                value: Number(row.value === undefined ? row.option.def : row.value)
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                onMoved: row.set(Math.round(value * 10) / 10)
            }
            QQC2.Label {
                text: parent.isSpeed ? i18n("%1×", slider.value.toFixed(1))
                    : slider.value === 0 ? i18n("normal") : (slider.value > 0 ? "+" : "") + slider.value.toFixed(1)
            }
        }
    }

    Component {
        id: textField
        ColumnLayout {
            readonly property string problem: {
                var v = String(row.value || "");
                if (row.option.type === "url" && v && !Sec.validateHttpUrl(v))
                    return i18n("Enter an address that starts with http:// or https://.");
                return "";
            }
            QQC2.TextField {
                Layout.fillWidth: true
                Layout.minimumWidth: Kirigami.Units.gridUnit * 18
                text: String(row.value || "")
                placeholderText: row.option.placeholder || ""
                onTextEdited: row.set(text)
            }
            QQC2.Label {
                visible: parent.problem !== ""
                text: parent.problem
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }

    // A key: written to KWallet at once, never into the settings.
    Component {
        id: secretField
        ColumnLayout {
            id: secretBox
            readonly property bool saved: !!row.keyStore && !!row.keyStore.keys && !!row.keyStore.keys[row.option.entry]
            property string note: ""
            RowLayout {
                QQC2.TextField {
                    id: keyField
                    objectName: "ttsSecretField"
                    Layout.minimumWidth: Kirigami.Units.gridUnit * 14
                    echoMode: TextInput.Password
                    placeholderText: secretBox.saved ? i18n("Saved in KWallet") : i18n("Not set")
                }
                QQC2.Button {
                    text: keyField.text ? i18n("Save key") : i18n("Remove key")
                    enabled: !!row.keyStore && (keyField.text !== "" || secretBox.saved)
                    onClicked: {
                        var box = secretBox;
                        row.keyStore.write(row.option.entry, keyField.text, function(ok) {
                            box.note = ok ? i18n("Saved.") : row.keyStore.statusMessage();
                            if (ok) keyField.text = "";
                        });
                    }
                }
            }
            QQC2.Label {
                text: secretBox.note || (row.option.hint ? i18n(row.option.hint) : "")
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
    }
}
