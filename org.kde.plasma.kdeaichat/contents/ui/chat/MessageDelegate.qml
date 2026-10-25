// One message in the chat view: a day divider when the day changes, then a
// bubble with the header, thinking, text, attachments, the agent's
// question or permission request, activity and the action buttons. Parts a
// message doesn't need aren't created.
//
// A row of chat.messageModel: `rev` goes up when this message changes, so
// the delegate updates in place instead of being rebuilt.
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Item {
    id: row

    required property string msgKey
    required property int rev
    required property int index
    property var chat: null

    readonly property var message: { rev; return chat.messageModel.messageFor(msgKey) || ({}); }
    readonly property string role: message.role || ""
    readonly property bool mine: role === "user" || role === "queued"
    readonly property bool isRequest: role === "permission_request" || role === "question_request"
    readonly property bool streaming: chat.currentStreamIndex === index
    readonly property bool editing: chat.editingMessageIndex === index && role !== "error"
    readonly property bool showDay: index === 0 || chat.messageDayKeyAt(index) !== chat.messageDayKeyAt(index - 1)
    readonly property string reasoning: streaming && (chat.currentStreamReasoning || chat.currentStreamExtractedReasoning)
        ? [chat.currentStreamReasoning, chat.currentStreamExtractedReasoning].filter(function(t) { return !!t; }).join("\n")
        : (message.reasoning || "")
    property string selectedText: ""

    implicitHeight: column.implicitHeight
    height: implicitHeight

    FontMetrics {
        id: metrics
        font: Kirigami.Theme.defaultFont
    }

    ColumnLayout {
        id: column
        width: row.width
        spacing: Kirigami.Units.smallSpacing

        PC3.Label {
            visible: row.showDay
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: row.showDay ? row.chat.dayDividerLabelForIndex(row.index) : ""
            font: Kirigami.Theme.smallFont
            opacity: 0.6
        }

        Rectangle {
            id: bubble

            Layout.alignment: row.mine ? Qt.AlignRight : Qt.AlignLeft
            Layout.preferredWidth: row.mine ? Math.min(row.width * 0.85, Math.max(content.implicitWidthHint, Kirigami.Units.gridUnit * 8)) : row.width
            Layout.leftMargin: row.mine ? 0 : Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            implicitHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
            radius: Kirigami.Units.cornerRadius * 2
            color: row.mine ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, row.role === "queued" ? 0.08 : 0.16)
                 : row.role === "error" ? Qt.rgba(Kirigami.Theme.negativeTextColor.r, Kirigami.Theme.negativeTextColor.g, Kirigami.Theme.negativeTextColor.b, 0.1)
                 : row.isRequest ? Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.1)
                 : "transparent"
            border.width: row.role === "error" || row.isRequest ? 1 : 0
            border.color: row.role === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.neutralTextColor

            ColumnLayout {
                id: content

                // Width a short message of mine needs, so its bubble hugs the text.
                readonly property real implicitWidthHint: Math.max(header.implicitWidth, body.longestLine) + Kirigami.Units.largeSpacing * 2

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    id: header
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PC3.Label {
                        text: row.role === "user" ? i18n("You")
                            : row.role === "queued" ? i18n("You · queued")
                            : row.role === "error" ? i18n("Something went wrong")
                            : row.role === "question_request" ? i18n("%1 asks", row.message.model || "OpenCode")
                            : row.role === "permission_request" ? i18n("%1 asks for permission", row.message.model || "OpenCode")
                            : (row.message.model || i18n("Assistant"))
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.maximumWidth: content.width * 0.7
                    }

                    PC3.Label {
                        text: row.chat.formatMessageTime(row.message, row.index)
                        visible: text !== ""
                        font: Kirigami.Theme.smallFont
                        opacity: 0.6
                    }

                    Item { Layout.fillWidth: true }

                    PC3.BusyIndicator {
                        visible: row.streaming
                        running: visible
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    }
                }

                Loader {
                    active: row.role === "assistant" && row.reasoning !== "" && !row.editing
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: ReasoningBlock {
                        text: row.reasoning
                        streaming: row.streaming && row.chat.currentStreamText === ""
                    }
                }

                Loader {
                    active: row.editing
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.TextArea {
                            Layout.fillWidth: true
                            text: row.chat.editingDraft
                            wrapMode: Text.Wrap
                            onTextChanged: row.chat.editingDraft = text
                            Component.onCompleted: forceActiveFocus()
                        }

                        PC3.Label {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            font: Kirigami.Theme.smallFont
                            opacity: 0.75
                            text: i18n("Saving removes the messages after this one.")
                        }
                    }
                }

                MessageBody {
                    id: body

                    // The longest line, measured roughly, for sizing my bubbles.
                    readonly property real longestLine: row.mine
                        ? Math.max.apply(null, String(row.message.content || "").split("\n").slice(0, 50).map(function(l) { return l.length; }).concat([0])) * metrics.averageCharacterWidth
                        : 0

                    visible: !row.editing && (text !== "" || row.streaming)
                    Layout.fillWidth: true
                    chat: row.chat
                    messageIndex: row.index
                    streaming: row.streaming
                    isError: row.role === "error"
                    text: row.streaming ? row.chat.currentStreamText : (row.message.content || "")
                    onSelectionMade: (text) => { if (text.trim() || !actions.keepSelection) row.selectedText = text; }
                }

                Loader {
                    active: (row.message.attachments || []).length > 0
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: AttachmentChips {
                        chat: row.chat
                        attachments: row.message.attachments
                    }
                }

                Loader {
                    active: row.role === "permission_request"
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: PermissionButtons {
                        message: row.message
                        onAnswered: (approved, always) => row.chat.respondToPermission(row.message.permissionId, approved, always)
                    }
                }

                Loader {
                    active: row.role === "question_request"
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: QuestionCard {
                        chat: row.chat
                        message: row.message
                    }
                }

                Loader {
                    active: (row.message.contextItems || []).length > 0
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: ContextList {
                        items: row.message.contextItems
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    MessageActions {
                        id: actions
                        visible: !row.isRequest
                        chat: row.chat
                        message: row.message
                        messageIndex: row.index
                        streaming: row.streaming
                        editing: row.editing
                        selectedText: row.selectedText
                    }

                    Item { Layout.fillWidth: true }

                    PC3.Label {
                        visible: row.message.tokens !== undefined && !row.mine
                        text: visible ? row.chat.formatTokensUsage(row.message.tokens, row.message.cost) : ""
                        font: Kirigami.Theme.smallFont
                        opacity: 0.55
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
