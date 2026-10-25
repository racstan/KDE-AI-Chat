// The toolbar above the chat: the history toggle, pin, settings, the chat
// title, the Chat info panel, a "More" menu (rename, jump, export, clear) and
// New chat. Every button has an accessible name.
//
// Things that live outside the chat (the settings action, dialogs) are
// requested through signals; the parent wires them up.
pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.plasma.components as PC3

RowLayout {
    id: header

    property var chat: null
    property string appName: "KDE AI Chat"
    // The history takes the whole view (a narrow popup), so chat actions are
    // hidden and the toggle reads "Back to chat". Set by FullRepresentationContent.
    property bool historyFull: chat ? chat.historyOnlyMode : false

    signal settingsRequested()
    signal chatControlsRequested()
    signal exportRequested(string suggestedFile)

    function exportFileName() {
        var cleanTitle = (header.chat.currentSessionTitle || "New Chat").replace(/[\/\?<>\\:\*\|":\s]+/g, "_");
        var now = new Date();
        var year = now.getFullYear();
        var month = String(now.getMonth() + 1).padStart(2, "0");
        var day = String(now.getDate()).padStart(2, "0");
        var hour = String(now.getHours()).padStart(2, "0");
        var min = String(now.getMinutes()).padStart(2, "0");
        var sec = String(now.getSeconds()).padStart(2, "0");
        var timestamp = year + "-" + month + "-" + day + "_" + hour + "-" + min + "-" + sec;
        var docs = String(StandardPaths.writableLocation(StandardPaths.DocumentsLocation)).replace(/\/+$/, "");
        return docs + "/" + encodeURIComponent(cleanTitle + "_" + timestamp + ".md");
    }

    function clearChat() {
        header.chat.messages = [];
        header.chat.editingMessageIndex = -1;
        header.chat.editingDraft = "";
        header.chat.clearCurrentOpenCodeSessionIfNeeded();
        header.chat.saveCurrentSessionState(true);
    }

    Layout.fillWidth: true

    PC3.ToolButton {
        id: historyButton

        readonly property string label: header.historyFull ? i18n("Back to chat")
            : (header.chat.historyOnlyMode ? i18n("Hide history") : i18n("Show history"))

        icon.name: header.historyFull ? "go-previous-symbolic" : "view-history"
        checkable: !header.historyFull
        checked: !header.historyFull && header.chat.historyOnlyMode
        Accessible.name: label
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: label
        onClicked: header.chat.historyOnlyMode = !header.chat.historyOnlyMode
    }

    PC3.ToolButton {
        icon.name: "window-pin"
        checkable: true
        checked: !header.chat.hideOnWindowDeactivate
        onToggled: header.chat.hideOnWindowDeactivate = !checked
        Accessible.name: checked ? i18n("Unpin (close when clicking away)") : i18n("Pin (keep open)")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: Accessible.name
    }

    PC3.ToolButton {
        icon.name: "configure"
        Accessible.name: i18n("Open Settings")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: Accessible.name
        onClicked: header.settingsRequested()
    }

    Item {
        Layout.fillWidth: true
    }

    PC3.Label {
        text: header.historyFull ? i18n("%1 History", header.appName) : (header.chat.currentSessionTitle || i18n("New Chat"))
        font.bold: true
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        Layout.fillWidth: false
        Layout.maximumWidth: Math.max(50, header.width - 220)
        clip: true
    }

    Item {
        Layout.fillWidth: true
    }

    // Chat info: this chat's usage and its own settings.
    PC3.ToolButton {
        visible: !header.historyFull
        icon.name: "documentinfo"
        Accessible.name: i18n("Chat info")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: Accessible.name
        onClicked: header.chatControlsRequested()
    }

    // Everything else that acts on this chat, kept out of the toolbar.
    PC3.ToolButton {
        id: moreButton

        visible: !header.historyFull
        icon.name: "overflow-menu"
        Accessible.name: i18n("More actions")
        QQC2.ToolTip.visible: hovered && !moreMenu.visible
        QQC2.ToolTip.text: Accessible.name
        onClicked: moreMenu.popup(moreButton, 0, moreButton.height)

        QQC2.Menu {
            id: moreMenu

            QQC2.MenuItem {
                text: i18n("Rename chat")
                icon.name: "document-edit"
                onTriggered: {
                    header.chat.renamingCurrentChat = !header.chat.renamingCurrentChat;
                    header.chat.currentChatRenameDraft = header.chat.currentSessionTitle || "";
                }
            }
            QQC2.MenuSeparator {
            }
            QQC2.MenuItem {
                text: i18n("Jump to first message")
                icon.name: "go-top"
                onTriggered: {
                    var list = header.chat.msgListViewRef;
                    if (list && list.count > 0) {
                        header.chat.userScrolledUp = true;
                        list.positionViewAtBeginning();
                    }
                }
            }
            QQC2.MenuItem {
                text: i18n("Jump to previous message")
                icon.name: "go-up"
                onTriggered: header.chat.jumpOneMessageAbove()
            }
            QQC2.MenuItem {
                text: i18n("Jump to next message")
                icon.name: "go-down"
                onTriggered: header.chat.jumpOneMessageBelow()
            }
            QQC2.MenuItem {
                text: i18n("Jump to latest message")
                icon.name: "go-bottom"
                onTriggered: {
                    header.chat.userScrolledUp = false;
                    header.chat.scrollToBottom(true);
                }
            }
            QQC2.MenuSeparator {
            }
            QQC2.MenuItem {
                text: i18n("Export chat…")
                icon.name: "document-export"
                enabled: !header.chat.loading && header.chat.messages.length > 0
                onTriggered: header.exportRequested(header.exportFileName())
            }
            QQC2.MenuItem {
                text: i18n("Clear chat")
                icon.name: "edit-clear-all"
                enabled: !header.chat.loading && header.chat.messages.length > 0
                onTriggered: header.clearChat()
            }
        }
    }

    PC3.ToolButton {
        icon.name: "list-add"
        enabled: !header.chat.loading
        Accessible.name: i18n("New chat")
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: Accessible.name
        onClicked: header.chat.createSession(true)
    }
}
