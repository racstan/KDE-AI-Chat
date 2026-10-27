// Settings → Appearance, "Chat look": the text size of the chat, the
// spacing, plain messages or bubbles, the colours of code and the accent
// colour. Every default keeps the Plasma look (chat/Prefs.js); each option
// has its own reset button. The page owns the saved values (cfg_*); this
// form edits them.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../chat/Prefs.js" as Prefs

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: form

    property int fontScale: Prefs.defaults.chatFontScale
    property string density: Prefs.defaults.chatDensity
    property string chatStyle: Prefs.defaults.chatStyle
    property string codeTheme: Prefs.defaults.codeTheme
    property string accentColor: Prefs.defaults.accentColor

    // Puts every option of this form back to its default.
    function resetAll() {
        fontScale = Prefs.defaults.chatFontScale;
        density = Prefs.defaults.chatDensity;
        chatStyle = Prefs.defaults.chatStyle;
        codeTheme = Prefs.defaults.codeTheme;
        accentColor = Prefs.defaults.accentColor;
    }

    function indexIn(model, value) {
        for (var i = 0; i < model.length; i++) {
            if (model[i].value === value)
                return i;
        }
        return 0;
    }

    readonly property var densities: [
        {"value": "compact", "text": i18n("Compact")},
        {"value": "normal", "text": i18n("Normal (like Plasma)")},
        {"value": "roomy", "text": i18n("Roomy")}
    ]
    readonly property var styles: [
        {"value": "plain", "text": i18n("Plain (like Plasma)")},
        {"value": "bubbles", "text": i18n("Bubbles")}
    ]
    readonly property var codeThemes: [
        {"value": "system", "text": i18n("Plasma colours")},
        {"value": "light", "text": i18n("Light")},
        {"value": "dark", "text": i18n("Dark")},
        {"value": "solarizedLight", "text": i18n("Solarized light")},
        {"value": "solarizedDark", "text": i18n("Solarized dark")},
        {"value": "highContrast", "text": i18n("High contrast")}
    ]
    readonly property string accent: Prefs.accent(form.accentColor)

    ColorDialog {
        id: colorDialog
        title: i18n("Choose the Accent Colour")
        selectedColor: form.accent || Kirigami.Theme.highlightColor
        // "#rrggbb" (an "#aarrggbb" loses its alpha).
        onAccepted: { var t = String(selectedColor); form.accentColor = t.length === 9 ? "#" + t.substring(3) : t; }
    }

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Chat look")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Text size:")
        changed: form.fontScale !== Prefs.defaults.chatFontScale
        onReset: form.fontScale = Prefs.defaults.chatFontScale

        QQC2.SpinBox {
            id: fontSpin
            objectName: "fontScaleSpin"
            from: Prefs.minFontScale
            to: Prefs.maxFontScale
            stepSize: 10
            editable: true
            value: form.fontScale
            onValueModified: form.fontScale = value
            textFromValue: function(value) { return i18n("%1 %", value); }
            valueFromText: function(text) {
                var number = parseInt(text, 10);
                return isNaN(number) ? Prefs.defaults.chatFontScale : number;
            }
            Accessible.name: i18n("Text size of the chat, in percent")
        }
    }

    SettingHelp {
        text: i18n("Makes the messages and the message box bigger or smaller. 100 % is the size of the rest of your desktop.")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Spacing:")
        changed: form.density !== Prefs.defaults.chatDensity
        onReset: form.density = Prefs.defaults.chatDensity

        QQC2.ComboBox {
            Accessible.name: i18n("Spacing")
            objectName: "densityCombo"
            model: form.densities
            textRole: "text"
            valueRole: "value"
            currentIndex: form.indexIn(form.densities, form.density)
            onActivated: form.density = currentValue
        }
    }

    SettingHelp {
        text: i18n("How much room there is between and around messages. Compact fits more on the screen; roomy is easier to read.")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Messages:")
        changed: form.chatStyle !== Prefs.defaults.chatStyle
        onReset: form.chatStyle = Prefs.defaults.chatStyle

        QQC2.ComboBox {
            Accessible.name: i18n("Message style")
            objectName: "chatStyleCombo"
            model: form.styles
            textRole: "text"
            valueRole: "value"
            currentIndex: form.indexIn(form.styles, form.chatStyle)
            onActivated: form.chatStyle = currentValue
        }
    }

    SettingHelp {
        text: i18n("Plain shows the messages as text on the chat's background. Bubbles puts each message in a box: yours tinted with the accent colour.")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Code colours:")
        changed: form.codeTheme !== Prefs.defaults.codeTheme
        onReset: form.codeTheme = Prefs.defaults.codeTheme

        QQC2.ComboBox {
            Accessible.name: i18n("Code colours")
            objectName: "codeThemeCombo"
            model: form.codeThemes
            textRole: "text"
            valueRole: "value"
            currentIndex: form.indexIn(form.codeThemes, form.codeTheme)
            onActivated: form.codeTheme = currentValue
        }
    }

    SettingHelp {
        text: i18n("The colours of program code in answers. Plasma colours match your desktop; the others always look the same, for example dark code on a light desktop.")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Accent colour:")
        changed: form.accentColor !== Prefs.defaults.accentColor
        onReset: form.accentColor = Prefs.defaults.accentColor

        Rectangle {
            objectName: "accentSwatch"
            implicitWidth: Kirigami.Units.iconSizes.smallMedium
            implicitHeight: implicitWidth
            radius: width / 2
            color: form.accent || Kirigami.Theme.highlightColor
            border.width: 1
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.3)
        }

        QQC2.Button {
            objectName: "accentButton"
            text: form.accent ? form.accent : i18n("Plasma accent")
            icon.name: "color-picker"
            Accessible.name: i18n("Choose the accent colour")
            onClicked: colorDialog.open()
        }
    }

    SettingHelp {
        text: i18n("The colour of highlights in the chat: selected text, the picked message and, with bubbles, your messages. By default it is your desktop's accent colour. Plasma's own buttons keep the desktop colour.")
    }
}
