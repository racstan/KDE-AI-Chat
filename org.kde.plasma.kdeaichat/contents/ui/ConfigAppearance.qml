// Settings → Appearance: the widget's name and icon, the panel icon's
// animation (config/PanelIconSettings.qml), the chat's look
// (config/ChatLookSettings.qml) and layout (config/LayoutSettings.qml), which desktop notifications to
// show, the sound played when a reply finishes, the keyboard shortcuts and a
// link to support the developer (Plasma's About page shows no donation link).
// Colours follow the Plasma colour scheme; only the accent can be changed.
// Every look and layout option is opt-in: its default is the Plasma look.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes
import "config" as Config
import "store" as Store
import "chat/ShortcutList.js" as ShortcutList
import "chat/Prefs.js" as Prefs

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

KCM.SimpleKCM {
    id: page

    // A KDE icon name, or the path of an image file (animated GIFs work).
    property string cfg_customIcon: "dialog-messages"
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

    readonly property string donateUrl: "https://buymeacoffee.com/rachitasthana"
    readonly property string termsUrl: "https://github.com/racstan/KDE-AI-Chat/blob/master/TERMS.md"
    // Runs the helper's commands (the animation file check); tests pass a fake.
    property var runHelper: defaultRunner.run
    // Opens a link; tests replace it.
    property var openUrl: function(url) { Qt.openUrlExternally(url); }

    readonly property string defaultIcon: "dialog-messages"

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

    function isCustomIconImage(value) {
        var v = String(value || "").trim().toLowerCase();
        if (v.indexOf("file://") === 0 || v.charAt(0) === "/")
            return true;
        return /\.(png|jpe?g|gif|webp|svgz?|bmp)$/.test(v);
    }

    function customIconImageSource(value) {
        var v = String(value || "").trim();
        return v === "" || v.indexOf("file://") === 0 ? v : "file://" + v;
    }

    Component {
        id: iconDialogComponent
        KIconThemes.IconDialog {
            onIconNameChanged: function(iconName) {
                if (iconName)
                    page.cfg_customIcon = iconName;
            }
        }
    }
    property var iconDialog: null

    Store.HelperRunner {
        id: defaultRunner
        helperPath: {
            var path = decodeURIComponent(String(Qt.resolvedUrl("kde_ai_helper.py")).replace(/^file:\/\//, ""));
            return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
        }
    }

    FileDialog {
        id: imageDialog
        title: i18n("Choose an Image for the Widget")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("Images (*.png *.jpg *.jpeg *.webp *.gif *.svg *.svgz *.bmp)")]
        onAccepted: page.cfg_customIcon = decodeURIComponent(String(selectedFile).replace(/^file:\/\//, ""))
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

            QQC2.Button {
                id: iconButton
                Kirigami.FormData.label: i18n("Icon:")
                implicitWidth: Kirigami.Units.iconSizes.large + Kirigami.Units.largeSpacing * 2
                implicitHeight: implicitWidth
                onPressed: iconMenu.opened ? iconMenu.close() : iconMenu.popup(iconButton, 0, iconButton.height)
                Accessible.name: i18n("Choose the widget icon")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Choose the widget icon")

                Image {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.large
                    height: width
                    visible: page.isCustomIconImage(page.cfg_customIcon)
                    source: visible ? page.customIconImageSource(page.cfg_customIcon) : ""
                    sourceSize.width: width
                    sourceSize.height: height
                    fillMode: Image.PreserveAspectFit
                }
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: Kirigami.Units.iconSizes.large
                    height: width
                    visible: !page.isCustomIconImage(page.cfg_customIcon)
                    source: page.cfg_customIcon || page.defaultIcon
                }

                QQC2.Menu {
                    id: iconMenu
                    QQC2.MenuItem {
                        text: i18n("Choose Icon…")
                        icon.name: "document-open-folder"
                        onTriggered: {
                            if (!page.iconDialog)
                                page.iconDialog = iconDialogComponent.createObject(page);
                            page.iconDialog.open();
                        }
                    }
                    QQC2.MenuItem {
                        text: i18n("Choose Image File…")
                        icon.name: "image-x-generic"
                        onTriggered: imageDialog.open()
                    }
                    QQC2.MenuItem {
                        text: i18n("Reset to Default Icon")
                        icon.name: "edit-clear"
                        enabled: page.cfg_customIcon !== page.defaultIcon
                        onTriggered: page.cfg_customIcon = page.defaultIcon
                    }
                }
            }

            Config.SettingHelp {
                text: i18n("The picture for the widget: an icon from your theme or an image file of your own. It is what you click in the panel, unless you choose an animation below.")
            }
        }

        Config.PanelIconSettings {
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

            Item {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: i18n("Support the developer")
            }

            QQC2.Button {
                objectName: "donateButton"
                Kirigami.FormData.label: i18n("Like it?")
                text: i18n("Buy Me a Coffee")
                icon.name: "emblem-favorite"
                onClicked: page.openUrl(page.donateUrl)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: page.donateUrl
            }

            Config.SettingHelp {
                objectName: "donateHelp"
                text: i18n("KDE AI Chat is free. If it helps you, you can thank the developer with a small gift; this opens buymeacoffee.com in your web browser.")
            }

            QQC2.Button {
                objectName: "termsButton"
                Kirigami.FormData.label: i18n("Terms of use:")
                text: i18n("Read the terms")
                icon.name: "documentinfo"
                onClicked: page.openUrl(page.termsUrl)
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: page.termsUrl
            }

            Config.SettingHelp {
                objectName: "termsHelp"
                text: i18n("In short: the widget comes without warranty and collects nothing itself. Your messages go only to the services you choose, under their terms; you are responsible for your keys, for the costs on your accounts (scheduled prompts run by themselves) and for how you use the answers. Opens the full terms in your web browser.")
            }
        }

        Config.PageReset {
            onReset: page.resetPage()
        }
    }
}
