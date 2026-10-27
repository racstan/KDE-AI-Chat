// Settings → Appearance: the widget's name, its icon and panel
// animation (config/IconSettings.qml), the chat's look
// (config/ChatLookSettings.qml) and layout (config/LayoutSettings.qml), which desktop notifications to
// show, the sound played when a reply finishes, the keyboard shortcuts.
// Colours follow the Plasma colour scheme; only the accent can be changed.
// Every look and layout option is opt-in: its default is the Plasma look.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "config" as Config
import "store" as Store
import "chat/ShortcutList.js" as ShortcutList
import "chat/Prefs.js" as Prefs

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    // A KDE icon name, or the path of a still image file.
    property alias cfg_customIcon: panelIcon.customIcon
    property alias cfg_appDisplayName: nameField.text
    property alias cfg_playNotificationSound: soundCheck.checked
    property alias cfg_notifyOnReply: replyCheck.checked
    property alias cfg_notifyOnError: errorCheck.checked
    property alias cfg_notifyOnScheduled: scheduledCheck.checked
    property alias cfg_notifyOnInput: inputCheck.checked
    property alias cfg_panelIconMode: panelIcon.mode
    property alias cfg_panelIconFile: panelIcon.file
    property alias cfg_panelIconHoverOnly: panelIcon.hoverOnly
    property alias cfg_chatFontScale: look.fontScale
    property alias cfg_chatDensity: look.density
    property alias cfg_chatStyle: look.chatStyle
    property alias cfg_codeTheme: look.codeTheme
    property alias cfg_accentColor: look.accentColor
    property alias cfg_customPopupWidth: layoutForm.popupWidth
    property alias cfg_customPopupHeight: layoutForm.popupHeight
    property alias cfg_historySide: layoutForm.historySide
    property alias cfg_showWorkspaceBar: layoutForm.showWorkspaceBar
    property alias cfg_headerShowHistory: layoutForm.showHistory
    property alias cfg_headerShowPin: layoutForm.showPin
    property alias cfg_headerShowSettings: layoutForm.showSettings
    property alias cfg_headerShowNewChat: layoutForm.showNewChat
    property alias cfg_headerShowInfo: layoutForm.showInfo

    // "Reset this page": every setting here back to its default.
    function resetPage() {
        Prefs.resetPage(page, Prefs.appearancePageDefaults);
        look.resetAll();
        layoutForm.resetAll();
    }

    // Runs the helper's commands (the animation file check); tests pass a fake.
    property var runHelper: defaultRunner.run

    // The labels as literal i18n() calls, so they get extracted for translation.
    function shortcutLabel(id) {
        var labels = {
            "newChat": i18n("New chat"),
            "incognito": i18n("New incognito chat (never saved)"),
            "searchChats": i18n("Search all chats"),
            "history": i18n("Show or hide the history"),
            "info": i18n("Show or hide the chat info panel"),
            "focusInput": i18n("Focus the message input"),
            "stop": i18n("Stop the reply; cancel an edit"),
            "regenerate": i18n("Regenerate the last reply"),
            "copyReply": i18n("Copy the last reply"),
            "nextChat": i18n("Next chat"),
            "prevChat": i18n("Previous chat"),
            "settings": i18n("Open the settings"),
            "editLast": i18n("Edit your last message"),
            "quote": i18n("Quote the picked message in your next one"),
            "readAloud": i18n("Read aloud the selected text or the picked message; stop reading"),
            "browseUp": i18n("Previous message (input empty, or after clicking the chat)"),
            "browseDown": i18n("Next message; past the latest, back to the input"),
            "firstMessage": i18n("Jump to the first message"),
            "latestMessage": i18n("Jump to the latest message")
        };
        return labels[id] || id;
    }

    Store.HelperRunner {
        id: defaultRunner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }

    ColumnLayout {
        Kirigami.FormLayout {
            id: mainForm
            Layout.fillWidth: true

            QQC2.TextField {
                Accessible.name: Kirigami.FormData.label
                id: nameField
                Kirigami.FormData.label: i18n("Name:")
                Layout.preferredWidth: Kirigami.Units.gridUnit * 16
                placeholderText: "KDE AI Chat"
            }

            Config.SettingHelp {
                text: i18n("The widget's name, shown at the top of the chat and when you hover over it in the panel.")
            }
        }

        Config.IconSettings {
            id: panelIcon
            Layout.fillWidth: true
            twinFormLayouts: [mainForm, restForm]
            runHelper: page.runHelper
        }

        Config.ChatLookSettings {
            id: look
            Layout.fillWidth: true
            twinFormLayouts: [mainForm, restForm]
        }

        Config.LayoutSettings {
            id: layoutForm
            Layout.fillWidth: true
            twinFormLayouts: [mainForm, restForm]
        }

        Kirigami.FormLayout {
            id: restForm
            Layout.fillWidth: true

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Notifications")
            }

            QQC2.CheckBox {
                id: replyCheck
                objectName: "notifyReplyCheck"
                Kirigami.FormData.label: i18n("Notify when:")
                text: i18n("A reply finishes while the chat is closed")
            }

            Config.SettingHelp {
                text: i18n("A desktop notification tells you the answer is ready, so you can do other things while you wait.")
            }

            QQC2.CheckBox {
                id: errorCheck
                objectName: "notifyErrorCheck"
                text: i18n("A request fails while the chat is closed")
            }

            Config.SettingHelp {
                text: i18n("You hear about problems, for example a wrong key or no internet, without opening the chat.")
            }

            QQC2.CheckBox {
                id: inputCheck
                objectName: "notifyInputCheck"
                text: i18n("The AI needs an answer or permission while the chat is closed")
            }

            Config.SettingHelp {
                text: i18n("The AI is waiting for you, for example to answer a question or to allow a change to your files.")
            }

            QQC2.CheckBox {
                id: scheduledCheck
                objectName: "notifyScheduledCheck"
                text: i18n("A scheduled task runs")
            }

            Config.SettingHelp {
                text: i18n("A schedule from the Schedules page has sent its message. Each schedule can also turn its own notification off.")
            }

            QQC2.CheckBox {
                id: soundCheck
                objectName: "soundCheck"
                Kirigami.FormData.label: i18n("Sound:")
                text: i18n("Play a sound when a reply is finished")
            }

            Config.SettingHelp {
                text: i18n("A short sound when the answer is complete, handy when you are looking at something else.")
            }

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Keyboard shortcuts")
            }

            Repeater {
                model: ShortcutList.shortcuts
                delegate: QQC2.Label {
                    required property var modelData
                    objectName: "shortcutRow"
                    Kirigami.FormData.label: modelData.keys
                    text: page.shortcutLabel(modelData.id)
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            QQC2.Label {
                objectName: "shortcutNote"
                Layout.fillWidth: true
                Layout.maximumWidth: Kirigami.Units.gridUnit * 24
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: i18n("These work while the chat is open. To open the widget from anywhere, set its global shortcut on the \"Keyboard Shortcuts\" page of this window.")
            }
        }

        Config.PageReset {
            onReset: page.resetPage()
        }
    }
}
