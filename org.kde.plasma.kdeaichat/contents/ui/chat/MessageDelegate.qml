// One message in the chat view: a day divider when the day changes, then a
// bubble with the header, thinking, text, attachments, the agent's
// question or permission request, activity, an error's buttons and the
// action buttons (shown while the message is hovered). Parts a message
// doesn't need aren't created.
//
// A row of chat.messageModel: `rev` goes up when this message changes, so
// the delegate updates in place instead of being rebuilt.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "ErrorText.js" as ErrorText
import "MessageGroups.js" as MessageGroups
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

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
    // The name and time show on the first message of a run from one sender only (MessageGroups.js).
    readonly property bool showHeader: showDay || MessageGroups.startsRun(chat.messages, index)
    readonly property bool showDay: index === 0 || chat.messageDayKeyAt(index) !== chat.messageDayKeyAt(index - 1)
    readonly property string reasoning: streaming && (chat.currentStreamReasoning || chat.currentStreamExtractedReasoning)
        ? [chat.currentStreamReasoning, chat.currentStreamExtractedReasoning].filter(function(t) { return !!t; }).join("\n")
        : (message.reasoning || "")
    property string selectedText: ""
    // Picked with Up/Down (ChatView.qml).
    readonly property bool selected: !!view && view.selectedIndex === index
    readonly property string errorProvider: role === "error" && !chat.openCodeMode && !chat.piMode
        ? chat.providerDisplayName(chat.getEffectiveProvider(chat.currentSessionId)) : ""
    // An error in plain language, with what can be done about it.
    readonly property var errorInfo: role === "error" ? ErrorText.describe(message.content, errorProvider) : ({})
    readonly property string errorText: role === "error" ? ErrorText.translated(errorInfo, function(template, args) {
        return args.length === 0 ? i18n(template) : args.length === 1 ? i18n(template, args[0]) : i18n(template, args[0], args[1]);
    }) : ""
    // Agent requests show their own content (what is asked, the questions).
    readonly property bool ownsBody: role === "permission_request" || (role === "question_request" && (message.questions || []).length > 0)
    // From the chat view: builds the buttons after the first frame
    // (chat/DeferredBuilder.qml), and the height they'll take.
    readonly property var view: ListView.view
    readonly property var builder: view ? view.builder : null
    readonly property real buttonHeight: view ? view.buttonHeight : 0
    // The bubble's width, known before the layouts run, so a new delegate
    // has its final height at once and the list doesn't lay out twice.
    // Every message fills the row between the bubble's side margins (yours
    // too: no box, only the name line tells them apart), so a card's border
    // isn't cut off at the right edge.
    // Yours sit at the right and take at most 80% of the row, so the line
    // lengths stay readable; the others fill it.
    readonly property real bubbleWidth: mine ? Math.round((width - Kirigami.Units.smallSpacing * 2) * 0.8) : width - Kirigami.Units.smallSpacing * 2
    // Settings → Appearance (chat/ChatPrefs.qml): the padding at the chosen
    // density, and filled boxes ("bubbles") for the conversation's messages.
    readonly property var prefs: chat && chat.prefs ? chat.prefs : null
    readonly property real pad: prefs ? prefs.spaced(Kirigami.Units.largeSpacing) : Kirigami.Units.largeSpacing
    readonly property bool filled: !!prefs && prefs.bubbles && (mine || role === "assistant")
    // How far the action buttons reach into the padding and the gap below
    // (so they cost little height).
    readonly property real actionsOverlap: prefs && prefs.densityFactor !== 1
        ? pad + Math.round(prefs.spaced(Kirigami.Units.largeSpacing) / 2) : Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing

    implicitHeight: column.implicitHeight
    height: implicitHeight

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
            objectName: "bubble"

            Layout.alignment: row.mine ? Qt.AlignRight : Qt.AlignLeft
            Layout.preferredWidth: row.bubbleWidth
            Layout.leftMargin: Kirigami.Units.smallSpacing
            Layout.rightMargin: Kirigami.Units.smallSpacing
            implicitHeight: content.implicitHeight + row.pad * 2
            radius: Kirigami.Units.cornerRadius
            // No fill for any message by default: a colour only where it means
            // something, and then only as an edge (errors red, agent requests
            // orange). With bubbles, yours take the accent, the AI's the view colour.
            color: row.selected ? Qt.alpha(Kirigami.Theme.highlightColor, 0.14)
                : !row.filled ? "transparent" : row.mine ? Qt.alpha(Kirigami.Theme.highlightColor, 0.18) : Kirigami.Theme.backgroundColor
            opacity: row.role === "queued" ? 0.7 : 1
            border.width: row.role === "error" || row.isRequest || row.selected ? 1 : 0
            border.color: row.role === "error" ? Kirigami.Theme.negativeTextColor
                : row.isRequest ? Kirigami.Theme.neutralTextColor : Qt.alpha(Kirigami.Theme.highlightColor, 0.5)

            HoverHandler {
                id: hover
            }

            ColumnLayout {
                id: content

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: row.pad
                spacing: row.prefs ? row.prefs.spaced(Kirigami.Units.smallSpacing) : Kirigami.Units.smallSpacing

                RowLayout {
                    id: header
                    visible: row.showHeader || row.streaming
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    layoutDirection: row.mine ? Qt.RightToLeft : Qt.LeftToRight

                    Loader {
                        active: row.role === "error"
                        visible: active
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        sourceComponent: Kirigami.Icon {
                            source: "dialog-error"
                            color: Kirigami.Theme.negativeTextColor
                        }
                    }

                    SenderName {
                        visible: row.showHeader
                        chat: row.chat
                        role: row.role
                        model: row.message.model || ""
                        scheduleName: row.message.scheduled ? String(row.message.scheduleName || i18n("Scheduled message")) : ""
                        maximumWidth: content.width * 0.7
                    }

                    // Next to the name while the reply is being written.
                    Loader {
                        active: row.streaming
                        visible: active
                        sourceComponent: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            PC3.BusyIndicator {
                                objectName: "streamSpinner"
                                running: true
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            }

                            PC3.Label {
                                objectName: "streamStatus"
                                text: row.message.imageJob ? i18n("Making a picture…") : row.chat.currentStreamText === "" ? i18n("Thinking…") : i18n("Writing…")
                                font: Kirigami.Theme.smallFont
                                opacity: 0.7
                            }
                        }
                    }

                    PC3.Label {
                        text: row.chat.formatMessageTime(row.message, row.index)
                        visible: text !== "" && row.showHeader
                        font: Kirigami.Theme.smallFont
                        opacity: 0.6
                    }

                    Item { Layout.fillWidth: true }
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

                        PC3.TextArea {
                            objectName: "inPlaceEditor"
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

                // What this message quoted (ChatView's list jumps to the original).
                Loader {
                    active: (row.message.quotes || []).length > 0
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: QuoteBlock {
                        chat: row.chat
                        quotes: row.message.quotes
                    }
                }

                // A picture being made: the queue place and wait time, or the countdown, and Stop.
                Loader {
                    active: !!row.message.imageJob
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: ImageJobCard {
                        job: row.message.imageJob
                        live: row.streaming
                        onStopRequested: row.chat.stopStreaming()
                    }
                }

                MessageBody {
                    id: body
                    objectName: "messageBody"

                    visible: !row.editing && !row.ownsBody && (text !== "" || row.streaming)
                    Layout.fillWidth: true
                    textWidth: row.bubbleWidth - row.pad * 2
                    buttonHeight: row.buttonHeight
                    builder: row.builder
                    chat: row.chat
                    messageIndex: row.index
                    streaming: row.streaming
                    isError: row.role === "error"
                    alignRight: row.mine
                    text: row.streaming ? row.chat.currentStreamText : row.role === "error" ? row.errorText : (row.message.content || "")
                    onSelectionMade: (text) => { if (text.trim() || !actions.keepSelection) row.selectedText = text; }
                }

                // Pictures of a reply, and the images it links to (click to load).
                Loader {
                    active: row.role === "assistant" && ((row.message.images || []).length > 0 || String(row.message.content || "").indexOf("![") >= 0)
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: MessageImages {
                        chat: row.chat
                        message: row.message
                    }
                }

                Loader {
                    active: (row.message.attachments || []).length > 0
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: AttachmentChips {
                        chat: row.chat
                        attachments: row.message.attachments
                        alignRight: row.mine
                    }
                }

                Loader {
                    active: row.role === "permission_request"
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: PermissionDetail {
                        message: row.message
                    }
                }

                Loader {
                    active: row.role === "error"
                    visible: active
                    Layout.fillWidth: true
                    sourceComponent: ErrorActions {
                        info: row.errorInfo
                        chat: row.chat
                        onRetryRequested: row.chat.retryFailedMessage(row.index)
                        onSettingsRequested: row.chat.openSettings()
                        onCopyRequested: row.chat.copyTextToClipboard(row.errorInfo.detail || row.errorText)
                        onDeleteRequested: row.chat.deleteMessage(row.index)
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
                        tools: row.message.tools || ({})
                        notices: row.message.notices || []
                        files: row.message.filesChanged || []
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    layoutDirection: row.mine ? Qt.RightToLeft : Qt.LeftToRight

                    MessageActions {
                        id: actions
                        visible: !row.isRequest && row.role !== "error"
                        // Room for the buttons, which are built after the first frame.
                        Layout.minimumHeight: buttonSize
                        // Overlaps the bubble's bottom padding and part of the gap to
                        // the next message (never reaching it), so it costs little height.
                        Layout.bottomMargin: -row.actionsOverlap
                        builder: row.builder
                        chat: row.chat
                        message: row.message
                        messageIndex: row.index
                        streaming: row.streaming
                        editing: row.editing
                        hovered: hover.hovered
                        selected: row.selected
                        selectedText: row.selectedText
                    }

                    // What the reply used, right after the buttons: shown with
                    // them, while the message is hovered or has keyboard focus.
                    PC3.Label {
                        objectName: "usageLine"
                        visible: row.message.tokens !== undefined && !row.mine
                        Layout.bottomMargin: actions.Layout.bottomMargin
                        Layout.leftMargin: Kirigami.Units.smallSpacing
                        text: visible ? row.chat.formatTokensUsage(row.message.tokens, row.message.cost) : ""
                        font: Kirigami.Theme.smallFont
                        opacity: actions.shown ? 0.55 : 0
                        elide: Text.ElideRight
                        Layout.maximumWidth: content.width - actions.implicitWidth - Kirigami.Units.largeSpacing

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Kirigami.Units.shortDuration
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
