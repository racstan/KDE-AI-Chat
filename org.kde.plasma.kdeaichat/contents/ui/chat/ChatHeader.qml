// The toolbar above the chat: history, pin, settings, the chat title,
// chat actions (rename, controls, jump, clear, export) and New chat.
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

    Layout.fillWidth: true

    PC3.ToolButton {
        icon.name: header.chat.historyOnlyMode ? "go-previous-symbolic" : "view-list-icons"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: header.chat.historyOnlyMode ? "Back to chat" : "Expand history"
        onClicked: header.chat.historyOnlyMode = !header.chat.historyOnlyMode
    }

    PC3.ToolButton {
        icon.name: "window-pin"
        checkable: true
        checked: !header.chat.hideOnWindowDeactivate
        onToggled: header.chat.hideOnWindowDeactivate = !checked
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: checked ? "Unpin (close when clicking away)" : "Pin (keep open)"
    }

    PC3.ToolButton {
        icon.name: "configure"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Open Settings"
        onClicked: header.settingsRequested()
    }

    Item {
        Layout.fillWidth: true
    }

    PC3.Label {
        text: header.chat.historyOnlyMode ? (header.appName + " History") : (header.chat.currentSessionTitle || "New Chat")
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

    PC3.ToolButton {
        visible: !header.chat.historyOnlyMode
        icon.name: "document-edit"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Rename current chat"
        onClicked: {
            header.chat.renamingCurrentChat = !header.chat.renamingCurrentChat;
            header.chat.currentChatRenameDraft = header.chat.currentSessionTitle || "";
        }
    }

    PC3.ToolButton {
        visible: !header.chat.historyOnlyMode
        icon.name: "preferences-other"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Open chat controls sidebar"
        onClicked: header.chatControlsRequested()
    }

    PC3.ToolButton {
        visible: !header.chat.historyOnlyMode
        icon.name: "go-top"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Jump to first message"
        onClicked: {
            var list = header.chat.msgListViewRef;
            if (list && list.count > 0) {
                header.chat.userScrolledUp = true;
                list.positionViewAtBeginning();
            }
        }
    }

    PC3.ToolButton {
        visible: !header.chat.historyOnlyMode
        icon.name: "go-up"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Jump to one message above"
        onClicked: header.chat.jumpOneMessageAbove()
    }

    PC3.ToolButton {
        visible: !header.chat.historyOnlyMode
        icon.name: "go-down"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Jump to one message below"
        onClicked: header.chat.jumpOneMessageBelow()
    }

    PC3.ToolButton {
        visible: !header.chat.historyOnlyMode
        icon.name: "go-bottom"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Jump to latest message"
        onClicked: {
            header.chat.userScrolledUp = false;
            header.chat.scrollToBottom(true);
        }
    }

    PC3.ToolButton {
        visible: !header.chat.historyOnlyMode
        icon.name: "edit-clear-all"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Clear current chat history"
        enabled: !header.chat.loading && header.chat.messages.length > 0
        onClicked: {
            header.chat.messages = [];
            header.chat.editingMessageIndex = -1;
            header.chat.editingDraft = "";
            header.chat.clearCurrentOpenCodeSessionIfNeeded();
            header.chat.saveCurrentSessionState(true);
        }
    }

    PC3.ToolButton {
        visible: !header.chat.historyOnlyMode && header.chat.messages.length > 0
        icon.name: "document-export"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "Export chat session"
        enabled: !header.chat.loading
        onClicked: header.exportRequested(header.exportFileName())
    }

    PC3.ToolButton {
        icon.name: "list-add"
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.text: "New chat"
        enabled: !header.chat.loading
        onClicked: header.chat.createSession(true)
    }
}
