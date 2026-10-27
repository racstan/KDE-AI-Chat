// Settings → Appearance, "Layout": the size the chat opens at, which side
// the history sits on, the folder and project bar, and which buttons the
// top of the chat shows. Every default is the layout the widget always had
// (chat/Prefs.js); each option has its own reset button. The page owns the
// saved values (cfg_*); this form edits them.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../chat/Prefs.js" as Prefs

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

Kirigami.FormLayout {
    id: form

    property int popupWidth: Prefs.defaults.customPopupWidth
    property int popupHeight: Prefs.defaults.customPopupHeight
    property string historySide: Prefs.defaults.historySide
    property bool showWorkspaceBar: Prefs.defaults.showWorkspaceBar
    property bool showHistory: Prefs.defaults.headerShowHistory
    property bool showPin: Prefs.defaults.headerShowPin
    property bool showSettings: Prefs.defaults.headerShowSettings
    property bool showNewChat: Prefs.defaults.headerShowNewChat
    property bool showInfo: Prefs.defaults.headerShowInfo

    // Puts every option of this form back to its default.
    function resetAll() {
        popupWidth = Prefs.defaults.customPopupWidth;
        popupHeight = Prefs.defaults.customPopupHeight;
        historySide = Prefs.defaults.historySide;
        showWorkspaceBar = Prefs.defaults.showWorkspaceBar;
        showHistory = Prefs.defaults.headerShowHistory;
        showPin = Prefs.defaults.headerShowPin;
        showSettings = Prefs.defaults.headerShowSettings;
        showNewChat = Prefs.defaults.headerShowNewChat;
        showInfo = Prefs.defaults.headerShowInfo;
    }

    readonly property var sides: [
        {"value": "left", "text": i18n("Left")},
        {"value": "right", "text": i18n("Right")}
    ]

    Item {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("Layout")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Chat size:")
        changed: form.popupWidth !== Prefs.defaults.customPopupWidth || form.popupHeight !== Prefs.defaults.customPopupHeight
        onReset: {
            form.popupWidth = Prefs.defaults.customPopupWidth;
            form.popupHeight = Prefs.defaults.customPopupHeight;
        }

        QQC2.SpinBox {
            objectName: "popupWidthSpin"
            from: Prefs.minPopupWidth
            to: 4000
            stepSize: 20
            editable: true
            value: form.popupWidth
            onValueModified: form.popupWidth = value
            Accessible.name: i18n("Width of the chat, in pixels")
        }
        QQC2.Label {
            text: "×"
        }
        QQC2.SpinBox {
            objectName: "popupHeightSpin"
            from: Prefs.minPopupHeight
            to: 4000
            stepSize: 20
            editable: true
            value: form.popupHeight
            onValueModified: form.popupHeight = value
            Accessible.name: i18n("Height of the chat, in pixels")
        }
    }

    SettingHelp {
        text: i18n("How wide and tall the chat is when it opens, in pixels. Dragging the grip in the chat's corner changes this too.")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("History side:")
        changed: form.historySide !== Prefs.defaults.historySide
        onReset: form.historySide = Prefs.defaults.historySide

        QQC2.ComboBox {
            Accessible.name: i18n("History side")
            objectName: "historySideCombo"
            model: form.sides
            textRole: "text"
            valueRole: "value"
            currentIndex: form.historySide === "right" ? 1 : 0
            onActivated: form.historySide = currentValue
        }
    }

    SettingHelp {
        text: i18n("Where the list of your chats appears when the chat is wide enough to show it beside the conversation.")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Folder bar:")
        changed: form.showWorkspaceBar !== Prefs.defaults.showWorkspaceBar
        onReset: form.showWorkspaceBar = Prefs.defaults.showWorkspaceBar

        QQC2.CheckBox {
            objectName: "workspaceBarCheck"
            text: i18n("Show the folder and project bar above the chat")
            checked: form.showWorkspaceBar
            onToggled: form.showWorkspaceBar = checked
        }
    }

    SettingHelp {
        text: i18n("The bar shows the chat's folder and project. Hide it if you don't use them; a chat's folder can still be set in its Chat info. OpenCode chats always show it, for the agent choice.")
    }

    ResetRow {
        Kirigami.FormData.label: i18n("Buttons at the top:")
        changed: form.showHistory !== Prefs.defaults.headerShowHistory
        onReset: form.showHistory = Prefs.defaults.headerShowHistory

        QQC2.CheckBox {
            objectName: "showHistoryCheck"
            text: i18n("History")
            checked: form.showHistory
            onToggled: form.showHistory = checked
        }
    }

    ResetRow {
        changed: form.showPin !== Prefs.defaults.headerShowPin
        onReset: form.showPin = Prefs.defaults.headerShowPin

        QQC2.CheckBox {
            objectName: "showPinCheck"
            text: i18n("Pin (keep open)")
            checked: form.showPin
            onToggled: form.showPin = checked
        }
    }

    ResetRow {
        changed: form.showSettings !== Prefs.defaults.headerShowSettings
        onReset: form.showSettings = Prefs.defaults.headerShowSettings

        QQC2.CheckBox {
            objectName: "showSettingsCheck"
            text: i18n("Settings")
            checked: form.showSettings
            onToggled: form.showSettings = checked
        }
    }

    ResetRow {
        changed: form.showNewChat !== Prefs.defaults.headerShowNewChat
        onReset: form.showNewChat = Prefs.defaults.headerShowNewChat

        QQC2.CheckBox {
            objectName: "showNewChatCheck"
            text: i18n("New chat")
            checked: form.showNewChat
            onToggled: form.showNewChat = checked
        }
    }

    ResetRow {
        changed: form.showInfo !== Prefs.defaults.headerShowInfo
        onReset: form.showInfo = Prefs.defaults.headerShowInfo

        QQC2.CheckBox {
            objectName: "showInfoCheck"
            text: i18n("Chat info")
            checked: form.showInfo
            onToggled: form.showInfo = checked
        }
    }

    SettingHelp {
        text: i18n("Hide the buttons you don't use. The keyboard shortcuts for the history, a new chat, chat info and the settings still work (see below), and the More button always stays.")
    }
}
