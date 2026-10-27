// Settings → Chat, "Behaviour": which key sends, following new text, the
// time format, asking before a chat is deleted and a new chat on every
// opening. Every default is how the chat always behaved (chat/Prefs.js);
// each option has its own reset button. The page owns the saved values
// (cfg_*); this form edits them.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../chat/Prefs.js" as Prefs

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: form

    property string sendKey: Prefs.defaults.sendKey
    property bool autoScroll: Prefs.defaults.autoScroll
    property string timeFormat: Prefs.defaults.timeFormat
    property bool confirmDelete: Prefs.defaults.confirmDeleteChat
    property bool newChatOnOpen: Prefs.defaults.newChatOnOpen

    // Puts every option of this form back to its default.
    function resetAll() {
        sendKey = Prefs.defaults.sendKey;
        autoScroll = Prefs.defaults.autoScroll;
        timeFormat = Prefs.defaults.timeFormat;
        confirmDelete = Prefs.defaults.confirmDeleteChat;
        newChatOnOpen = Prefs.defaults.newChatOnOpen;
    }

    function indexIn(model, value) {
        for (var i = 0; i < model.length; i++) {
            if (model[i].value === value)
                return i;
        }
        return 0;
    }

    readonly property var sendKeys: [
        {"value": "enter", "text": i18n("Enter sends, Shift+Enter adds a line")},
        {"value": "ctrlEnter", "text": i18n("Ctrl+Enter sends, Enter adds a line")}
    ]
    // Examples at 14:30 today, so each choice shows what it looks like.
    readonly property real exampleTime: { var d = new Date(); d.setHours(14, 30, 0, 0); return d.getTime(); }
    readonly property var timeFormats: [
        {"value": "24h", "text": i18n("24-hour (%1)", Prefs.formatTime(exampleTime, "24h"))},
        {"value": "12h", "text": i18n("12-hour (%1)", Prefs.formatTime(exampleTime, "12h"))},
        {"value": "system", "text": i18n("Like the rest of the system (%1)", new Date(exampleTime).toLocaleTimeString(Qt.locale(), Locale.ShortFormat))}
    ]

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Behaviour")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Sending:")
        changed: form.sendKey !== Prefs.defaults.sendKey
        onReset: form.sendKey = Prefs.defaults.sendKey

        QQC2.ComboBox {
            Accessible.name: i18n("Send key")
            objectName: "sendKeyCombo"
            model: form.sendKeys
            textRole: "text"
            valueRole: "value"
            currentIndex: form.indexIn(form.sendKeys, form.sendKey)
            onActivated: form.sendKey = currentValue
        }
    }

    SettingHelp {
        text: i18n("Which key sends your message. Choose Ctrl+Enter if you often write messages of several lines and sometimes send them too early.")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Scrolling:")
        changed: form.autoScroll !== Prefs.defaults.autoScroll
        onReset: form.autoScroll = Prefs.defaults.autoScroll

        QQC2.CheckBox {
            objectName: "autoScrollCheck"
            text: i18n("Follow the answer while it is being written")
            checked: form.autoScroll
            onToggled: form.autoScroll = checked
        }
    }

    SettingHelp {
        text: i18n("The chat moves down as new text comes in. Turn this off to read at your own pace: a \"New messages\" button takes you to the end.")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Times:")
        changed: form.timeFormat !== Prefs.defaults.timeFormat
        onReset: form.timeFormat = Prefs.defaults.timeFormat

        QQC2.ComboBox {
            Accessible.name: i18n("Time format")
            objectName: "timeFormatCombo"
            model: form.timeFormats
            textRole: "text"
            valueRole: "value"
            currentIndex: form.indexIn(form.timeFormats, form.timeFormat)
            onActivated: form.timeFormat = currentValue
        }
    }

    SettingHelp {
        text: i18n("How the time is written next to each message.")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Deleting chats:")
        changed: form.confirmDelete !== Prefs.defaults.confirmDeleteChat
        onReset: form.confirmDelete = Prefs.defaults.confirmDeleteChat

        QQC2.CheckBox {
            objectName: "confirmDeleteCheck"
            text: i18n("Ask before deleting a chat")
            checked: form.confirmDelete
            onToggled: form.confirmDelete = checked
        }
    }

    SettingHelp {
        text: i18n("A question appears before a chat is deleted from the history. Either way, Undo brings a deleted chat back for a few seconds.")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Opening:")
        changed: form.newChatOnOpen !== Prefs.defaults.newChatOnOpen
        onReset: form.newChatOnOpen = Prefs.defaults.newChatOnOpen

        QQC2.CheckBox {
            objectName: "newChatOnOpenCheck"
            text: i18n("Start a new chat each time the widget opens")
            checked: form.newChatOnOpen
            onToggled: form.newChatOnOpen = checked
        }
    }

    SettingHelp {
        text: i18n("Opens on an empty chat instead of the last one. Earlier chats stay in the history. An empty chat is reused, and a chat still getting an answer is left open.")
    }
}
