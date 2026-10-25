// The chat history: one compact row per chat with its title and when it was
// last used. Rename, archive and delete appear on the row only while the
// pointer is over it or it has keyboard focus. Clicking a row (or Enter on it)
// opens that chat. Shown beside the chat in a wide popup and in place of it in
// a narrow one (chat/ChatBody.qml).
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Rectangle {
    id: sessionList

    property var chat: null
    // A narrow popup shows the history instead of the chat: choosing a chat
    // then goes back to it. Beside the chat, the history stays open.
    property bool closeOnSelect: true
    readonly property alias list: historyList

    // "Today", "Yesterday" or the date.
    function dayLabel(ms) {
        if (!(ms > 0))
            return "";
        var now = new Date();
        var startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
        if (ms >= startOfToday)
            return i18n("Today");
        if (ms >= startOfToday - 86400000)
            return i18n("Yesterday");
        return new Date(ms).toLocaleDateString(Qt.locale(), Locale.ShortFormat);
    }

    radius: Kirigami.Units.cornerRadius
    color: Kirigami.Theme.alternateBackgroundColor
    border.width: 1
    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)

    ListView {
        id: historyList

        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        model: sessionList.chat.sessions
        spacing: 1
        clip: true
        cacheBuffer: 5000

        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
        }

        delegate: Rectangle {
            id: row

            required property var modelData
            readonly property var chat: sessionList.chat
            readonly property bool current: modelData.value === chat.currentSessionId
            readonly property bool editing: chat.editingSessionId === modelData.value
            readonly property string title: modelData.text || i18n("New Chat")
            readonly property bool showActions: hover.hovered || activeFocus || editing || renameButton.activeFocus
                                                || archiveButton.activeFocus || deleteButton.activeFocus

            function open() {
                chat.switchSession(modelData.value);
                if (sessionList.closeOnSelect)
                    chat.historyOnlyMode = false;
            }

            width: historyList.width
            height: Kirigami.Units.gridUnit * 2 + Kirigami.Units.smallSpacing
            radius: Kirigami.Units.cornerRadius
            opacity: modelData.archived ? 0.72 : 1
            // The open chat is tinted with the accent colour; a hovered one faintly.
            color: current ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.18)
                 : hover.hovered ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.07)
                 : "transparent"
            border.width: activeFocus ? 1 : 0
            border.color: Kirigami.Theme.highlightColor
            activeFocusOnTab: true

            Accessible.role: Accessible.Button
            Accessible.name: title
            Accessible.description: sessionList.dayLabel(modelData.updatedAt || modelData.createdAt)
            Accessible.onPressAction: open()

            Keys.onReturnPressed: if (!editing) open()
            Keys.onEnterPressed: if (!editing) open()
            Keys.onDownPressed: nextItemInFocusChain(true).forceActiveFocus()
            Keys.onUpPressed: nextItemInFocusChain(false).forceActiveFocus()

            HoverHandler {
                id: hover
            }

            TapHandler {
                enabled: !row.editing
                onTapped: {
                    row.forceActiveFocus();
                    row.open();
                }
            }

            QQC2.ToolTip.visible: hover.hovered && !row.editing
            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
            QQC2.ToolTip.text: chat.sessionSubtitle(modelData)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.smallSpacing * 2
                anchors.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                // Agent chats are marked with a plain tag: OC for OpenCode, PI for Pi.
                PC3.Label {
                    visible: text !== ""
                    text: row.modelData.source === "opencode" ? "OC" : (row.modelData.source === "pi" ? "PI" : "")
                    font.bold: true
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    opacity: 0.7
                    Accessible.name: row.modelData.source === "pi" ? i18n("Pi chat") : i18n("OpenCode chat")
                }

                PC3.Label {
                    visible: !row.editing
                    Layout.fillWidth: true
                    text: row.title
                    font.bold: row.current
                    elide: Text.ElideRight
                }

                PC3.TextField {
                    visible: row.editing
                    Layout.fillWidth: true
                    text: row.chat.editingSessionDraft
                    onTextChanged: row.chat.editingSessionDraft = text
                    onAccepted: row.chat.saveSessionRename(row.modelData.value)
                    onVisibleChanged: if (visible) forceActiveFocus()
                }

                PC3.Label {
                    objectName: "dateLabel"
                    visible: !row.showActions
                    text: sessionList.dayLabel(row.modelData.updatedAt || row.modelData.createdAt)
                    color: Kirigami.Theme.disabledTextColor
                    font: Kirigami.Theme.smallFont
                }

                // Actions: only while hovered or focused (or renaming).
                PC3.ToolButton {
                    id: renameButton
                    objectName: "renameButton"

                    visible: row.showActions
                    icon.name: row.editing ? "dialog-ok-apply" : "document-edit"
                    display: PC3.AbstractButton.IconOnly
                    Accessible.name: row.editing ? i18n("Save title") : i18n("Rename chat")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: Accessible.name
                    onClicked: {
                        if (row.editing)
                            row.chat.saveSessionRename(row.modelData.value);
                        else
                            row.chat.startSessionRename(row.modelData.value);
                    }
                }

                PC3.ToolButton {
                    id: archiveButton
                    objectName: "archiveButton"

                    visible: row.showActions && !row.editing
                    icon.name: row.modelData.archived ? "archive-remove" : "archive-insert"
                    display: PC3.AbstractButton.IconOnly
                    Accessible.name: row.modelData.archived ? i18n("Unarchive chat") : i18n("Archive chat")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: Accessible.name
                    onClicked: row.chat.setSessionArchived(row.modelData.value, !row.modelData.archived)
                }

                PC3.ToolButton {
                    id: deleteButton
                    objectName: "deleteButton"

                    visible: row.showActions
                    icon.name: row.editing ? "dialog-cancel" : "trash-empty"
                    display: PC3.AbstractButton.IconOnly
                    Accessible.name: row.editing ? i18n("Cancel rename") : i18n("Delete chat")
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: Accessible.name
                    onClicked: {
                        if (row.editing)
                            row.chat.cancelSessionRename();
                        else
                            row.chat.deleteSession(row.modelData.value);
                    }
                }
            }
        }
    }
}
