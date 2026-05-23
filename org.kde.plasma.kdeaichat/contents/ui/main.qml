import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support 2.0 as P5Support
import QtQuick.Dialogs

PlasmoidItem {
    id: root

    Plasmoid.title: plasmoid.configuration.appDisplayName || "KDE AI Chat"

    preferredRepresentation: compactRepresentation

    property var sessions: []
    property string currentSessionId: ""
    property string currentSessionTitle: ""
    property var messages: []
    property var attachedFiles: []

    property bool historyOnlyMode: false
    property bool loading: false
    property var activeXhr: null
    property var openCodeEventXhr: null
    property string openCodeActiveSessionId: ""
    property int openCodeAssistantMessageIndex: -1
    property string openCodeAssistantServerMessageId: ""
    property string openCodeAssistantModelLabel: "OpenCode"
    property bool openCodeErrorShownForRequest: false
    property bool streamingResponse: false

    property int editingMessageIndex: -1
    property string editingDraft: ""

    property string editingSessionId: ""
    property string editingSessionDraft: ""

    property bool renamingCurrentChat: false
    property string currentChatRenameDraft: ""

    property bool openCodeMode: plasmoid.configuration.useOpenCode

    // Root-level proxies so root-scope functions can reach UI elements in fullRepresentation
    property string chatInputText: ""
    signal clearChatInput()
    property var msgListViewRef: null
    property bool userScrolledUp: false
    property int queueCounter: 0

    property int popupPreferredWidth: plasmoid.configuration.customPopupWidth > 0 ? plasmoid.configuration.customPopupWidth : 760
    property int popupPreferredHeight: plasmoid.configuration.customPopupHeight > 0 ? plasmoid.configuration.customPopupHeight : 760
    readonly property bool popupIsDark: {
        var mode = plasmoid.configuration.appearanceMode || 0;
        if (mode === 1) return false;
        if (mode === 2) return true;
        return Qt.styleHints.colorScheme === Qt.Dark;
    }


    Component.onCompleted: loadSessions()
    onMessagesChanged: {
        if (!root.historyOnlyMode && !root.userScrolledUp)
            Qt.callLater(scrollToBottom)
    }

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.8
            height: width
            source: "dialog-messages"
        }
    }

    fullRepresentation: Item {
        // Plasma popup sizing follows implicit size more reliably than Layout hints here.
        implicitWidth: root.popupPreferredWidth
        implicitHeight: root.popupPreferredHeight
        width: implicitWidth
        height: implicitHeight
        Layout.minimumWidth: 500
        Layout.minimumHeight: 620
        Layout.preferredWidth: implicitWidth
        Layout.preferredHeight: implicitHeight

        Kirigami.Theme.inherit: false
        Kirigami.Theme.colorGroup: root.popupIsDark ? Kirigami.Theme.Dark : Kirigami.Theme.Light
        Kirigami.Theme.backgroundColor: root.popupIsDark ? "#121212" : "#ffffff"
        Kirigami.Theme.alternateBackgroundColor: root.popupIsDark ? "#1a1a1a" : "#f5f7fa"
        Kirigami.Theme.textColor: root.popupIsDark ? "#f7fafc" : "#1a202c"
        Kirigami.Theme.highlightColor: "#3182ce"

        Rectangle {
            anchors.fill: parent
            color: Kirigami.Theme.backgroundColor
            radius: 8
        }

        DropArea {
            id: dropArea
            anchors.fill: parent
            
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(Kirigami.Theme.highlightColor.r,
                               Kirigami.Theme.highlightColor.g,
                               Kirigami.Theme.highlightColor.b,
                               0.15)
                border.color: Kirigami.Theme.highlightColor
                border.width: 2
                radius: 8
                visible: parent.containsDrag
                z: 999

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.largeSpacing

                    Kirigami.Icon {
                        source: "mail-attachment"
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 48
                        implicitHeight: 48
                        color: Kirigami.Theme.highlightColor
                    }

                    PC3.Label {
                        text: "Drop files here to attach"
                        font.bold: true
                        font.pointSize: 14
                        color: Kirigami.Theme.highlightColor
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            onEntered: function(drag) {
                if (drag.hasUrls) {
                    drag.accept(Qt.CopyAction)
                }
            }

            onDropped: function(drop) {
                if (drop.hasUrls) {
                    for (var i = 0; i < drop.urls.length; i++) {
                        root.attachFile(drop.urls[i])
                    }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true

                PC3.ToolButton {
                    icon.name: root.historyOnlyMode ? "go-previous-symbolic" : "view-list-icons"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: root.historyOnlyMode ? "Back to chat" : "Expand history"
                    onClicked: root.historyOnlyMode = !root.historyOnlyMode
                }

                Item { Layout.fillWidth: true }

                PC3.Label {
                    text: root.historyOnlyMode
                          ? ((plasmoid.configuration.appDisplayName || "KDE AI Chat") + " History")
                          : (root.currentSessionTitle || "New Chat")
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    Layout.fillWidth: false
                    Layout.maximumWidth: Math.max(50, parent.width - 220)
                    clip: true
                }

                Item { Layout.fillWidth: true }

                PC3.ToolButton {
                    visible: !root.historyOnlyMode
                    icon.name: "document-edit"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "Rename current chat"
                    onClicked: {
                        root.renamingCurrentChat = !root.renamingCurrentChat
                        root.currentChatRenameDraft = root.currentSessionTitle || ""
                    }
                }


                PC3.ToolButton {
                    visible: !root.historyOnlyMode
                    icon.name: "go-top"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "Jump to first message"
                    onClicked: {
                        if (root.msgListViewRef && root.msgListViewRef.count > 0) {
                            root.userScrolledUp = true
                            root.msgListViewRef.positionViewAtBeginning()
                        }
                    }
                }

                PC3.ToolButton {
                    visible: !root.historyOnlyMode
                    icon.name: "go-up"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "Jump to one message above"
                    onClicked: root.jumpOneMessageAbove()
                }

                PC3.ToolButton {
                    visible: !root.historyOnlyMode
                    icon.name: "go-down"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "Jump to one message below"
                    onClicked: root.jumpOneMessageBelow()
                }

                PC3.ToolButton {
                    visible: !root.historyOnlyMode
                    icon.name: "go-bottom"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "Jump to latest message"
                    onClicked: {
                        root.userScrolledUp = false
                        root.scrollToBottom()
                    }
                }

                PC3.ToolButton {
                    icon.name: "list-add"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "New chat"
                    enabled: !root.loading
                    onClicked: root.createSession(true)
                }
            }

            PC3.Label {
                Layout.fillWidth: true
                visible: !root.historyOnlyMode && root.openCodeMode && root.currentOpenCodeSessionId() !== ""
                text: "OpenCode Session ID: " + root.currentOpenCodeSessionId()
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.italic: true
                opacity: 0.8
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            RowLayout {
                visible: !root.historyOnlyMode && root.renamingCurrentChat
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    Layout.fillWidth: true
                    text: root.currentChatRenameDraft
                    onTextChanged: root.currentChatRenameDraft = text
                    onAccepted: {
                        root.renameCurrentSession(root.currentChatRenameDraft)
                        root.renamingCurrentChat = false
                    }
                }

                PC3.ToolButton {
                    icon.name: "dialog-ok-apply"
                    onClicked: {
                        root.renameCurrentSession(root.currentChatRenameDraft)
                        root.renamingCurrentChat = false
                    }
                }

                PC3.ToolButton {
                    icon.name: "dialog-cancel"
                    onClicked: root.renamingCurrentChat = false
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.historyOnlyMode ? 1 : 0

                Item {
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Kirigami.Units.smallSpacing

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 8
                            color: Kirigami.Theme.alternateBackgroundColor
                            clip: true

                            Connections {
                                target: root
                                function onClearChatInput() { msgInput.text = "" }
                            }

                            ListView {
                                id: msgList
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                model: root.messages
                                spacing: Kirigami.Units.largeSpacing
                                clip: true
                                cacheBuffer: 20000
                                QQC2.ScrollBar.vertical: QQC2.ScrollBar { id: verticalScrollBar }

                                Component.onCompleted: root.msgListViewRef = msgList

                                // Track whether user manually scrolled away from bottom
                                onMovementStarted: {
                                    if (!msgList.atYEnd)
                                        root.userScrolledUp = true
                                }
                                onAtYEndChanged: {
                                    if (msgList.atYEnd)
                                        root.userScrolledUp = false
                                }
                                onContentYChanged: {
                                    if (!msgList.atYEnd) {
                                        if (msgList.moving || msgList.dragging || verticalScrollBar.pressed || verticalScrollBar.active) {
                                            root.userScrolledUp = true
                                        }
                                    }
                                }

                                delegate: Item {
                                    property bool showDayHeader: index === 0 || root.messageDayKeyAt(index) !== root.messageDayKeyAt(index - 1)
                                    width: msgList.width
                                    implicitHeight: delegateCol.implicitHeight
                                    height: implicitHeight

                                    Column {
                                        id: delegateCol
                                        width: parent.width
                                        spacing: Kirigami.Units.largeSpacing

                                        Item {
                                            visible: showDayHeader
                                            width: parent.width
                                            height: showDayHeader ? dayHeaderChip.implicitHeight : 0

                                            Rectangle {
                                                id: dayHeaderChip
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                radius: 999
                                                color: Qt.rgba(Kirigami.Theme.textColor.r,
                                                               Kirigami.Theme.textColor.g,
                                                               Kirigami.Theme.textColor.b,
                                                               0.10)
                                                implicitWidth: dayHeaderText.implicitWidth + Kirigami.Units.largeSpacing
                                                implicitHeight: dayHeaderText.implicitHeight + Kirigami.Units.smallSpacing

                                                PC3.Label {
                                                    id: dayHeaderText
                                                    anchors.centerIn: parent
                                                    horizontalAlignment: Text.AlignHCenter
                                                    opacity: 0.78
                                                    text: root.dayDividerLabelForIndex(index)
                                                }
                                            }
                                        }

                                        Item {
                                            width: parent.width
                                            height: bubble.implicitHeight

                                            Rectangle {
                                                id: bubble
                                                width: Math.min(msgList.width * 0.76, 560)
                                                implicitHeight: bubbleCol.implicitHeight + Kirigami.Units.largeSpacing
                                                radius: 10
                                                color: modelData.role === "user"
                                                       ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                                 Kirigami.Theme.highlightColor.g,
                                                                 Kirigami.Theme.highlightColor.b,
                                                                 0.20)
                                                       : modelData.role === "queued"
                                                         ? Qt.rgba(Kirigami.Theme.neutralTextColor.r,
                                                                   Kirigami.Theme.neutralTextColor.g,
                                                                   Kirigami.Theme.neutralTextColor.b,
                                                                   0.18)
                                                       : modelData.role === "error"
                                                         ? Kirigami.Theme.negativeBackgroundColor
                                                          : (modelData.role === "permission_request" || modelData.role === "question_request")
                                                           ? Qt.rgba(Kirigami.Theme.focusColor.r,
                                                                     Kirigami.Theme.focusColor.g,
                                                                     Kirigami.Theme.focusColor.b,
                                                                     0.12)
                                                           : Kirigami.Theme.backgroundColor
                                                border.width: modelData.role === "error" || modelData.role === "permission_request" || modelData.role === "question_request" ? 2 : 1
                                                border.color: modelData.role === "error"
                                                              ? Kirigami.Theme.negativeTextColor
                                                              : (modelData.role === "permission_request" || modelData.role === "question_request")
                                                                ? Kirigami.Theme.focusColor
                                                                : Qt.rgba(Kirigami.Theme.textColor.r,
                                                                          Kirigami.Theme.textColor.g,
                                                                          Kirigami.Theme.textColor.b,
                                                                          0.16)
                                                anchors.right: modelData.role === "user" || modelData.role === "queued" ? parent.right : undefined
                                                anchors.left: modelData.role === "assistant" || modelData.role === "error" || modelData.role === "permission_request" || modelData.role === "question_request" ? parent.left : undefined

                                                Column {
                                                    id: bubbleCol
                                                    width: parent.width - Kirigami.Units.largeSpacing
                                                    x: Kirigami.Units.smallSpacing + Kirigami.Units.smallSpacing / 2
                                                    y: Kirigami.Units.smallSpacing + Kirigami.Units.smallSpacing / 2
                                                    spacing: Kirigami.Units.smallSpacing

                                                    Row {
                                                        width: parent.width
                                                        spacing: Kirigami.Units.smallSpacing

                                                        PC3.Label {
                                                            text: modelData.role === "user"
                                                                  ? "You"
                                                                  : modelData.role === "queued"
                                                                    ? "You (Queued)"
                                                                    : modelData.role === "error"
                                                                      ? "Error"
                                                                      : modelData.role === "question_request"
                                                                        ? "OpenCode Interactive Question"
                                                                        : modelData.role === "permission_request"
                                                                        ? "OpenCode Security Request"
                                                                        : "AI"
                                                            font.bold: true
                                                        }

                                                        PC3.Label {
                                                            text: root.formatMessageTime(modelData, index)
                                                            opacity: 0.7
                                                            visible: text !== ""
                                                        }

                                                        PC3.Label {
                                                            text: modelData.role === "assistant" && modelData.model ? ("(" + modelData.model + ")") : ""
                                                            opacity: 0.6
                                                            visible: text !== ""
                                                        }
                                                    }

                                                    Loader {
                                                        active: root.editingMessageIndex === index
                                                                && modelData.role !== "error"
                                                                && modelData.role !== "assistant"
                                                        width: parent.width
                                                        sourceComponent: QQC2.TextArea {
                                                            width: parent ? parent.width : implicitWidth
                                                            text: root.editingDraft
                                                            wrapMode: Text.WordWrap
                                                            onTextChanged: root.editingDraft = text
                                                        }
                                                    }

                                                    PC3.Label {
                                                        visible: root.editingMessageIndex !== index || modelData.role === "error"
                                                        width: parent.width
                                                        wrapMode: Text.Wrap
                                                        textFormat: modelData.role === "error" ? Text.PlainText : Text.RichText
                                                        text: modelData.role === "error" ? modelData.content : root.convertMarkdownToHtml(modelData.content)
                                                        color: modelData.role === "error"
                                                               ? Kirigami.Theme.negativeTextColor
                                                               : Kirigami.Theme.textColor
                                                        onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                                                    }

                                                    Flow {
                                                        width: parent.width
                                                        visible: modelData.attachments && modelData.attachments.length > 0
                                                        spacing: Kirigami.Units.smallSpacing

                                                        Repeater {
                                                            model: modelData.attachments || []
                                                            delegate: Rectangle {
                                                                width: Math.min(150, msgFilenameLabel.implicitWidth + 36)
                                                                height: Kirigami.Units.gridUnit * 1.25
                                                                radius: 6
                                                                color: Qt.rgba(Kirigami.Theme.textColor.r,
                                                                               Kirigami.Theme.textColor.g,
                                                                               Kirigami.Theme.textColor.b,
                                                                               0.05)
                                                                border.width: 1
                                                                border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                                                                      Kirigami.Theme.textColor.g,
                                                                                      Kirigami.Theme.textColor.b,
                                                                                      0.10)

                                                                RowLayout {
                                                                    anchors.fill: parent
                                                                    anchors.margins: Kirigami.Units.smallSpacing
                                                                    spacing: Kirigami.Units.smallSpacing

                                                                    Item {
                                                                        Layout.preferredWidth: 16
                                                                        Layout.preferredHeight: 16

                                                                        Image {
                                                                            anchors.fill: parent
                                                                            visible: modelData.type === "image"
                                                                            source: "file://" + modelData.path
                                                                            fillMode: Image.PreserveAspectCrop
                                                                            clip: true
                                                                        }

                                                                        Kirigami.Icon {
                                                                            anchors.fill: parent
                                                                            visible: modelData.type !== "image"
                                                                            source: root.fileIconName(modelData.name)
                                                                        }
                                                                    }

                                                                    PC3.Label {
                                                                        id: msgFilenameLabel
                                                                        Layout.fillWidth: true
                                                                        text: modelData.name
                                                                        elide: Text.ElideRight
                                                                        font.pointSize: 8
                                                                        color: Kirigami.Theme.textColor
                                                                    }
                                                                }

                                                                MouseArea {
                                                                    anchors.fill: parent
                                                                    cursorShape: Qt.PointingHandCursor
                                                                    QQC2.ToolTip.visible: hovered
                                                                    QQC2.ToolTip.text: "Open: " + modelData.path
                                                                    onClicked: Qt.openUrlExternally("file://" + modelData.path)
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Row {
                                                        visible: modelData.role === "permission_request"
                                                        width: parent.width
                                                        spacing: Kirigami.Units.largeSpacing
                                                        Layout.topMargin: Kirigami.Units.smallSpacing

                                                        PC3.Button {
                                                            visible: modelData.status === "pending"
                                                            text: "Allow"
                                                            icon.name: "dialog-ok-apply"
                                                            onClicked: root.respondToPermission(modelData.permissionId, true)
                                                        }

                                                        PC3.Button {
                                                            visible: modelData.status === "pending"
                                                            text: "Reject"
                                                            icon.name: "dialog-cancel"
                                                            onClicked: root.respondToPermission(modelData.permissionId, false)
                                                        }

                                                        PC3.Label {
                                                            visible: modelData.status !== "pending"
                                                            text: modelData.status === "allowed"
                                                                  ? "Approved ✅"
                                                                  : modelData.status === "denied"
                                                                    ? "Rejected ❌"
                                                                    : modelData.status === "allowing..."
                                                                      ? "Approving..."
                                                                      : "Rejecting..."
                                                            font.bold: true
                                                            color: modelData.status === "allowed"
                                                                   ? Kirigami.Theme.positiveTextColor
                                                                   : Kirigami.Theme.negativeTextColor
                                                        }
                                                    }

                                                     Column {
                                                         visible: modelData.role === "question_request"
                                                         width: parent.width
                                                         spacing: Kirigami.Units.smallSpacing

                                                         PC3.Label {
                                                             text: "Your Answer:"
                                                             font.bold: true
                                                             visible: modelData.status === "pending"
                                                         }

                                                         PC3.TextField {
                                                             id: questionReplyField
                                                             visible: modelData.status === "pending"
                                                             width: parent.width
                                                             placeholderText: "Type your answer here..."
                                                             onAccepted: {
                                                                 if (text.trim() !== "") {
                                                                     root.respondToQuestion(modelData.questionId, text, false)
                                                                 }
                                                             }
                                                         }

                                                         Row {
                                                             width: parent.width
                                                             spacing: Kirigami.Units.largeSpacing

                                                             PC3.Button {
                                                                 visible: modelData.status === "pending"
                                                                 text: "Submit"
                                                                 icon.name: "mail-send"
                                                                 onClicked: {
                                                                     if (questionReplyField.text.trim() !== "") {
                                                                         root.respondToQuestion(modelData.questionId, questionReplyField.text, false)
                                                                     }
                                                                 }
                                                             }

                                                             PC3.Button {
                                                                 visible: modelData.status === "pending"
                                                                 text: "Dismiss"
                                                                 icon.name: "dialog-cancel"
                                                                 onClicked: root.respondToQuestion(modelData.questionId, "", true)
                                                             }

                                                             PC3.Label {
                                                                 visible: modelData.status !== "pending"
                                                                 text: modelData.status === "answered"
                                                                       ? "Answered: \"" + (modelData.submittedAnswer || "") + "\" ✅"
                                                                       : modelData.status === "dismissed"
                                                                         ? "Dismissed ❌"
                                                                         : modelData.status === "answering..."
                                                                           ? "Submitting..."
                                                                           : "Dismissing..."
                                                                 font.bold: true
                                                                 color: modelData.status === "answered"
                                                                        ? Kirigami.Theme.positiveTextColor
                                                                        : Kirigami.Theme.negativeTextColor
                                                             }
                                                         }
                                                     }

                                                    Rectangle {
                                                        visible: root.editingMessageIndex === index && modelData.role !== "error"
                                                        width: parent.width
                                                        height: editWarn.implicitHeight + Kirigami.Units.smallSpacing * 2
                                                        radius: 6
                                                        color: Qt.rgba(Kirigami.Theme.neutralTextColor.r,
                                                                       Kirigami.Theme.neutralTextColor.g,
                                                                       Kirigami.Theme.neutralTextColor.b,
                                                                       0.10)

                                                        PC3.Label {
                                                            id: editWarn
                                                            anchors.fill: parent
                                                            anchors.margins: Kirigami.Units.smallSpacing
                                                            wrapMode: Text.Wrap
                                                            text: "Saving this edit will remove all messages below this one and make this the latest message."
                                                        }
                                                    }

                                                    PC3.Label {
                                                        visible: modelData.role === "assistant" && modelData.tokens !== undefined
                                                        width: parent.width
                                                        horizontalAlignment: Text.AlignRight
                                                        text: root.formatTokensUsage(modelData.tokens, modelData.cost)
                                                        font.pointSize: 8
                                                        opacity: 0.55
                                                        elide: Text.ElideRight
                                                    }

                                                    Row {
                                                        width: parent.width
                                                        spacing: Kirigami.Units.smallSpacing

                                                        PC3.ToolButton {
                                                            visible: root.editingMessageIndex !== index
                                                                     && modelData.role !== "error"
                                                                     && modelData.role !== "assistant"
                                                            icon.name: "document-edit"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: modelData.role === "queued" ? "Edit queued message" : "Edit message"
                                                            onClicked: {
                                                                root.editingMessageIndex = index
                                                                root.editingDraft = modelData.content
                                                            }
                                                        }

                                                        PC3.ToolButton {
                                                            visible: root.editingMessageIndex === index
                                                                     && modelData.role !== "error"
                                                                     && modelData.role !== "assistant"
                                                            icon.name: "dialog-ok-apply"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: "Apply edit"
                                                            onClicked: root.saveEditedMessage()
                                                        }

                                                        PC3.ToolButton {
                                                            visible: root.editingMessageIndex === index
                                                                     && modelData.role !== "error"
                                                                     && modelData.role !== "assistant"
                                                            icon.name: "dialog-cancel"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: "Cancel edit"
                                                            onClicked: {
                                                                root.editingMessageIndex = -1
                                                                root.editingDraft = ""
                                                            }
                                                        }

                                                        PC3.ToolButton {
                                                            icon.name: "edit-copy"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: "Copy message"
                                                            onClicked: {
                                                                // Use an invisible text input to copy to clipboard in QML
                                                                clipboardHelper.text = modelData.content || ""
                                                                clipboardHelper.selectAll()
                                                                clipboardHelper.copy()
                                                            }
                                                        }

                                                        PC3.ToolButton {
                                                            icon.name: "edit-delete"
                                                            display: PC3.AbstractButton.IconOnly
                                                            QQC2.ToolTip.visible: hovered
                                                            QQC2.ToolTip.text: modelData.role === "queued" ? "Delete queued message" : "Delete message"
                                                            onClicked: root.deleteMessage(index)
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: parent.width
                                            implicitHeight: 1
                                            color: Qt.rgba(Kirigami.Theme.textColor.r,
                                                           Kirigami.Theme.textColor.g,
                                                           Kirigami.Theme.textColor.b,
                                                           0.14)
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            visible: root.loading
                            PC3.BusyIndicator { running: root.loading; width: 20; height: 20 }
                            PC3.Label {
                                text: root.streamingResponse ? "Streaming response..." : "Thinking..."
                                opacity: 0.8
                            }
                        }

                        // Attached Files Bar
                        QQC2.ScrollView {
                            Layout.fillWidth: true
                            visible: root.attachedFiles.length > 0
                            height: Kirigami.Units.gridUnit * 2
                            QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
                            QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AlwaysOff

                            Row {
                                spacing: Kirigami.Units.smallSpacing
                                padding: Kirigami.Units.smallSpacing

                                Repeater {
                                    model: root.attachedFiles
                                    delegate: Rectangle {
                                        width: Math.min(180, filenameLabel.implicitWidth + 60)
                                        height: Kirigami.Units.gridUnit * 1.5
                                        radius: 6
                                        color: Qt.rgba(Kirigami.Theme.textColor.r,
                                                       Kirigami.Theme.textColor.g,
                                                       Kirigami.Theme.textColor.b,
                                                       0.08)
                                        border.width: 1
                                        border.color: modelData.error !== ""
                                                      ? Kirigami.Theme.negativeTextColor
                                                      : Qt.rgba(Kirigami.Theme.textColor.r,
                                                                Kirigami.Theme.textColor.g,
                                                                Kirigami.Theme.textColor.b,
                                                                0.15)

                                        QQC2.ToolTip.visible: fileMouseArea.hovered && modelData.error !== ""
                                        QQC2.ToolTip.text: modelData.error

                                        MouseArea {
                                            id: fileMouseArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: Kirigami.Units.smallSpacing
                                            spacing: Kirigami.Units.smallSpacing

                                            Item {
                                                Layout.preferredWidth: 20
                                                Layout.preferredHeight: 20

                                                PC3.BusyIndicator {
                                                    anchors.centerIn: parent
                                                    visible: modelData.loading
                                                    running: modelData.loading
                                                    width: 16
                                                    height: 16
                                                }

                                                Image {
                                                    anchors.fill: parent
                                                    visible: !modelData.loading && modelData.type === "image"
                                                    source: "file://" + modelData.path
                                                    fillMode: Image.PreserveAspectCrop
                                                    clip: true
                                                }

                                                Kirigami.Icon {
                                                    anchors.fill: parent
                                                    visible: !modelData.loading && modelData.type !== "image"
                                                    source: root.fileIconName(modelData.name)
                                                }
                                            }

                                            PC3.Label {
                                                id: filenameLabel
                                                Layout.fillWidth: true
                                                text: modelData.name
                                                elide: Text.ElideRight
                                                font.pointSize: 9
                                                color: modelData.error !== "" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                            }

                                            PC3.ToolButton {
                                                icon.name: "dialog-close"
                                                Layout.preferredWidth: 20
                                                Layout.preferredHeight: 20
                                                display: PC3.AbstractButton.IconOnly
                                                QQC2.ToolTip.visible: hovered
                                                QQC2.ToolTip.text: "Remove file"
                                                onClicked: root.removeAttachedFile(index)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            PC3.ToolButton {
                                icon.name: "mail-attachment"
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                                enabled: !root.loading
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: "Attach files (Images, PDF, CSV, Word documents)"
                                onClicked: fileDialog.open()
                            }

                            PC3.ToolButton {
                                icon.name: "edit-paste"
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                                Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                                enabled: !root.loading
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: "Paste file or text from clipboard"
                                onClicked: {
                                    root.checkClipboardForAttachments()
                                    var txt = root.readClipboardText()
                                    if (txt && txt.trim() !== "") {
                                        var curPos = msgInput.cursorPosition
                                        msgInput.insert(curPos, txt)
                                    }
                                }
                            }

                            QQC2.TextArea {
                                id: msgInput
                                Layout.fillWidth: true
                                Layout.minimumHeight: Kirigami.Units.gridUnit * 3
                                Layout.maximumHeight: Kirigami.Units.gridUnit * 7
                                Layout.preferredHeight: Math.min(Layout.maximumHeight,
                                                                 Math.max(Layout.minimumHeight,
                                                                          contentHeight + topPadding + bottomPadding))
                                wrapMode: Text.WordWrap
                                clip: true
                                enabled: !root.loading
                                placeholderText: "Type message (Enter sends, Shift+Enter newline)"

                                // Sync to root property so root-scope functions can read/clear it
                                onTextChanged: root.chatInputText = text

                                Keys.onPressed: function(event) {
                                    if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                            && !(event.modifiers & Qt.ShiftModifier)) {
                                        event.accepted = true
                                        root.sendMessage()
                                    } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                                        root.checkClipboardForAttachments()
                                        event.accepted = false
                                    }
                                }
                            }

                            PC3.Button {
                                icon.name: root.loading ? "list-add" : "document-send"
                                text: root.loading ? "Queue" : "Send"
                                Layout.minimumWidth: Kirigami.Units.gridUnit * 5
                                Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                                enabled: root.chatInputText.trim() !== "" || root.attachedFiles.length > 0
                                onClicked: root.sendMessage()
                            }

                            PC3.ToolButton {
                                visible: root.loading
                                icon.name: "process-stop"
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: "Stop current response"
                                onClicked: root.stopStreaming()
                            }
                        }
                    }
                }

                Rectangle {
                    radius: 8
                    color: Kirigami.Theme.alternateBackgroundColor

                    ListView {
                        id: historyList
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        model: root.sessions
                        spacing: Kirigami.Units.smallSpacing
                        clip: true
                        cacheBuffer: 5000
                        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}

                        delegate: Rectangle {
                            required property var modelData
                            width: historyList.width
                            height: historyCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                            radius: 8
                            opacity: modelData.archived ? 0.72 : 1.0
                            color: root.historySessionTint(modelData)

                            Column {
                                id: historyCol
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing / 2

                                Row {
                                    width: parent.width
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    Rectangle {
                                        id: modeBadge
                                        visible: modelData.source === "opencode"
                                        width: modeBadgeText.implicitWidth + Kirigami.Units.smallSpacing * 2
                                        height: modeBadgeText.implicitHeight + Kirigami.Units.smallSpacing
                                        radius: 999
                                        color: Qt.rgba(0.20, 0.48, 0.92, 0.18)

                                        PC3.Label {
                                            id: modeBadgeText
                                            anchors.centerIn: parent
                                            text: "OC"
                                            font.bold: true
                                            color: Qt.rgba(0.12, 0.35, 0.78, 1.0)
                                        }
                                    }

                                    QQC2.TextField {
                                        visible: root.editingSessionId === modelData.value
                                        width: parent.width - saveRename.width - archiveChat.width - removeChat.width - (modeBadge.visible ? modeBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - Kirigami.Units.smallSpacing * 3
                                        text: root.editingSessionDraft
                                        onTextChanged: root.editingSessionDraft = text
                                        onAccepted: root.saveSessionRename(modelData.value)
                                    }

                                    PC3.Label {
                                        visible: root.editingSessionId !== modelData.value
                                        width: parent.width - saveRename.width - archiveChat.width - removeChat.width - (modeBadge.visible ? modeBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - Kirigami.Units.smallSpacing * 3
                                        text: modelData.text || "New Chat"
                                        font.bold: modelData.value === root.currentSessionId
                                        color: root.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
                                        elide: Text.ElideRight
                                        verticalAlignment: Text.AlignVCenter

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.switchSession(modelData.value)
                                                root.historyOnlyMode = false
                                            }
                                        }
                                    }

                                    PC3.ToolButton {
                                        id: saveRename
                                        icon.name: root.editingSessionId === modelData.value ? "dialog-ok-apply" : "document-edit"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: root.editingSessionId === modelData.value ? "Save title" : "Rename chat"
                                        onClicked: {
                                            if (root.editingSessionId === modelData.value)
                                                root.saveSessionRename(modelData.value)
                                            else
                                                root.startSessionRename(modelData.value)
                                        }
                                    }

                                    PC3.ToolButton {
                                        id: archiveChat
                                        icon.name: modelData.archived ? "archive-remove" : "archive-insert"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: modelData.archived ? "Unarchive chat" : "Archive chat"
                                        onClicked: root.setSessionArchived(modelData.value, !modelData.archived)
                                    }

                                    PC3.ToolButton {
                                        id: removeChat
                                        icon.name: root.editingSessionId === modelData.value ? "dialog-cancel" : "edit-delete"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: root.editingSessionId === modelData.value ? "Cancel rename" : "Delete chat"
                                        onClicked: {
                                            if (root.editingSessionId === modelData.value)
                                                root.cancelSessionRename()
                                            else
                                                root.deleteSession(modelData.value)
                                        }
                                    }
                                }

                                PC3.Label {
                                    opacity: root.popupIsDark ? 1.0 : 0.7
                                    color: root.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
                                    text: root.sessionSubtitle(modelData)
                                }
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Kirigami.Units.gridUnit
            height: Kirigami.Units.gridUnit
            cursorShape: Qt.SizeFDiagCursor
            
            property real startX: 0
            property real startY: 0
            property real startW: 0
            property real startH: 0
            
            onPressed: function(mouse) {
                startX = mouse.x
                startY = mouse.y
                startW = parent.implicitWidth
                startH = parent.implicitHeight
            }
            onPositionChanged: function(mouse) {
                if (pressed) {
                    var dx = mouse.x - startX
                    var dy = mouse.y - startY
                    var newW = Math.max(500, startW + dx)
                    var newH = Math.max(620, startH + dy)
                    parent.implicitWidth = newW
                    parent.implicitHeight = newH
                    plasmoid.configuration.customPopupWidth = newW
                    plasmoid.configuration.customPopupHeight = newH
                }
            }
            
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                Canvas {
                    anchors.fill: parent
                    anchors.margins: 4
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.strokeStyle = Kirigami.Theme.textColor;
                        ctx.lineWidth = 1;
                        ctx.globalAlpha = 0.5;
                        ctx.beginPath();
                        ctx.moveTo(width - 4, height);
                        ctx.lineTo(width, height - 4);
                        ctx.moveTo(width - 8, height);
                        ctx.lineTo(width, height - 8);
                        ctx.moveTo(width - 12, height);
                        ctx.lineTo(width, height - 12);
                        ctx.stroke();
                    }
                }
            }
        }
    }

    function pad2(v) {
        return v < 10 ? ("0" + v) : String(v)
    }

    function nowTime(ts) {
        var d = ts ? new Date(ts) : new Date()
        return pad2(d.getHours()) + ":" + pad2(d.getMinutes())
    }

    function formatDateTime(ts) {
        return new Date(ts).toLocaleString(undefined, {
            year: "numeric",
            month: "short",
            day: "2-digit",
            hour: "2-digit",
            minute: "2-digit"
        })
    }

    function makeSessionId() {
        return "s-" + Date.now() + "-" + Math.floor(Math.random() * 100000)
    }

    function parseSessions() {
        var raw = plasmoid.configuration.chatSessionsJson || "[]"
        try {
            var arr = JSON.parse(raw)
            if (Array.isArray(arr)) {
                for (var i = 0; i < arr.length; i++) {
                    if (!arr[i].messages)
                        arr[i].messages = []
                    if (arr[i].archived === undefined)
                        arr[i].archived = false
                    if (!arr[i].source)
                        arr[i].source = arr[i].openCodeSessionId ? "opencode" : "provider"
                    for (var j = 0; j < arr[i].messages.length; j++) {
                        if (!arr[i].messages[j].at)
                            arr[i].messages[j].at = arr[i].updatedAt || arr[i].createdAt || Date.now()
                        if (!arr[i].messages[j].time)
                            arr[i].messages[j].time = nowTime(arr[i].messages[j].at)
                    }
                    if (!arr[i].updatedAt)
                        arr[i].updatedAt = arr[i].createdAt || Date.now()
                }
                return arr
            }
            return []
        } catch (e) {
            return []
        }
    }

    function persistSessions() {
        plasmoid.configuration.chatSessionsJson = JSON.stringify(root.sessions)
        plasmoid.configuration.lastSessionId = root.currentSessionId
    }

    function sortSessionsByUpdated() {
        var copy = root.sessions.slice()
        copy.sort(function(a, b) {
            if (!!a.archived !== !!b.archived)
                return a.archived ? 1 : -1
            return (b.updatedAt || b.createdAt || 0) - (a.updatedAt || a.createdAt || 0)
        })
        root.sessions = copy
    }

    function historySessionTint(sessionData) {
        if (!sessionData)
            return Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)

        if (sessionData.value === root.currentSessionId && sessionData.source === "opencode")
            return Qt.rgba(0.20, 0.48, 0.92, 0.22)
        if (sessionData.source === "opencode")
            return Qt.rgba(0.20, 0.48, 0.92, 0.10)
        if (sessionData.value === root.currentSessionId)
            return Qt.rgba(Kirigami.Theme.highlightColor.r,
                           Kirigami.Theme.highlightColor.g,
                           Kirigami.Theme.highlightColor.b,
                           0.18)
        return Qt.rgba(Kirigami.Theme.textColor.r,
                       Kirigami.Theme.textColor.g,
                       Kirigami.Theme.textColor.b,
                       0.05)
    }

    function sessionSubtitle(sessionData) {
        var parts = []
        if (sessionData.source === "opencode")
            parts.push("OpenCode")
        if (sessionData.archived)
            parts.push("Archived")
        parts.push("Updated " + root.formatDateTime(sessionData.updatedAt || sessionData.createdAt || Date.now()))
        return parts.join(" · ")
    }

    function sessionIndexById(sessionId) {
        for (var i = 0; i < root.sessions.length; i++) {
            if (root.sessions[i].value === sessionId)
                return i
        }
        return -1
    }

    function createSession(switchToNew) {
        var s = {
            value: makeSessionId(),
            text: "New Chat",
            createdAt: Date.now(),
            updatedAt: Date.now(),
            archived: false,
            source: root.openCodeMode ? "opencode" : "provider",
            openCodeSessionId: "",
            messages: []
        }
        root.sessions = [s].concat(root.sessions)

        if (switchToNew) {
            root.currentSessionId = s.value
            root.currentSessionTitle = s.text
            root.messages = []
            root.editingMessageIndex = -1
            root.editingDraft = ""
            root.editingSessionId = ""
            root.editingSessionDraft = ""
            root.renamingCurrentChat = false
            root.currentChatRenameDraft = ""
            root.historyOnlyMode = false
        }
        persistSessions()
    }

    function loadSessions() {
        root.sessions = parseSessions()
        if (root.sessions.length === 0)
            createSession(true)

        var preferred = plasmoid.configuration.lastSessionId || ""
        var idx = sessionIndexById(preferred)
        if (idx < 0)
            idx = 0

        root.currentSessionId = root.sessions[idx].value
        root.currentSessionTitle = root.sessions[idx].text
        root.messages = root.sessions[idx].messages || []
        sortSessionsByUpdated()
    }

    function saveCurrentSessionState(touchUpdatedAt) {
        var idx = sessionIndexById(root.currentSessionId)
        if (idx < 0)
            return

        var updated = root.sessions.slice()
        var s = Object.assign({}, updated[idx])
        s.text = root.currentSessionTitle || "New Chat"
        s.messages = root.messages
        if (touchUpdatedAt !== false)
            s.updatedAt = Date.now()
        updated[idx] = s
        root.sessions = updated
        if (touchUpdatedAt !== false)
            sortSessionsByUpdated()
        persistSessions()
    }

    function setCurrentSessionSource(source) {
        var idx = sessionIndexById(root.currentSessionId)
        if (idx < 0)
            return
        var updated = root.sessions.slice()
        var item = Object.assign({}, updated[idx])
        item.source = source || "provider"
        item.archived = false
        updated[idx] = item
        root.sessions = updated
        persistSessions()
    }

    function setSessionArchived(sessionId, archived) {
        var idx = sessionIndexById(sessionId)
        if (idx < 0)
            return
        var updated = root.sessions.slice()
        var item = Object.assign({}, updated[idx])
        item.archived = !!archived
        item.updatedAt = Date.now()
        updated[idx] = item
        root.sessions = updated
        sortSessionsByUpdated()
        persistSessions()
    }

    function switchSession(sessionId) {
        if (!sessionId || sessionId === root.currentSessionId)
            return

        saveCurrentSessionState(false)

        var idx = sessionIndexById(sessionId)
        if (idx < 0)
            return

        root.currentSessionId = root.sessions[idx].value
        root.currentSessionTitle = root.sessions[idx].text
        root.messages = root.sessions[idx].messages || []
        root.editingMessageIndex = -1
        root.editingDraft = ""
        root.editingSessionId = ""
        root.editingSessionDraft = ""
        root.renamingCurrentChat = false
        root.currentChatRenameDraft = ""
        persistSessions()
        scrollToBottom()
    }

    function renameCurrentSession(newTitle) {
        var title = (newTitle || "").trim()
        if (title === "")
            title = "New Chat"

        root.currentSessionTitle = title
        saveCurrentSessionState(true)
    }

    function startSessionRename(sessionId) {
        var idx = sessionIndexById(sessionId)
        if (idx < 0)
            return
        root.editingSessionId = sessionId
        root.editingSessionDraft = root.sessions[idx].text || ""
    }

    function cancelSessionRename() {
        root.editingSessionId = ""
        root.editingSessionDraft = ""
    }

    function saveSessionRename(sessionId) {
        var idx = sessionIndexById(sessionId)
        if (idx < 0)
            return

        var title = (root.editingSessionDraft || "").trim()
        if (title === "")
            title = "New Chat"

        var updated = root.sessions.slice()
        var s = Object.assign({}, updated[idx])
        s.text = title
        s.updatedAt = Date.now()
        updated[idx] = s
        root.sessions = updated

        if (root.currentSessionId === sessionId)
            root.currentSessionTitle = title

        sortSessionsByUpdated()
        persistSessions()
        cancelSessionRename()
    }

    function deleteSession(sessionId) {
        if (root.sessions.length <= 1)
            return

        var idx = sessionIndexById(sessionId)
        if (idx < 0)
            return

        var updated = root.sessions.slice()
        updated.splice(idx, 1)
        root.sessions = updated

        if (root.currentSessionId === sessionId) {
            var next = root.sessions[0]
            root.currentSessionId = next.value
            root.currentSessionTitle = next.text
            root.messages = next.messages || []
        }

        cancelSessionRename()
        persistSessions()
    }

    function deleteMessage(index) {
        var copy = root.messages.slice()
        if (index < 0 || index >= copy.length)
            return
        copy.splice(index, 1)
        root.messages = copy
        root.editingMessageIndex = -1
        root.editingDraft = ""
        clearCurrentOpenCodeSessionIfNeeded()
        saveCurrentSessionState(true)
    }

    function saveEditedMessage() {
        var i = root.editingMessageIndex
        if (i < 0 || i >= root.messages.length)
            return
        if ((root.messages[i].role || "") === "error") {
            root.editingMessageIndex = -1
            root.editingDraft = ""
            return
        }

        // Cancel any active streaming/loading requests first
        stopStreaming()

        var role = root.messages[i].role || ""
        var isQueued = role === "queued"

        var copy = isQueued ? root.messages.slice() : root.messages.slice(0, i + 1)
        var item = Object.assign({}, copy[i])
        item.content = root.editingDraft
        item.at = Date.now()
        item.time = nowTime(item.at)
        copy[i] = item

        root.messages = copy
        root.editingMessageIndex = -1
        root.editingDraft = ""
        clearCurrentOpenCodeSessionIfNeeded()
        saveCurrentSessionState(true)

        // Re-run from edited user prompt so assistant response reflects the new text.
        if (role === "user") {
            root.userScrolledUp = false
            sendMessageByIndex(i)
        }
    }

    function openCodeBaseUrl() {
        var raw = (plasmoid.configuration.openCodeUrl || "http://127.0.0.1:4096/v1").trim()
        return raw.replace(/\/v1\/?$/, "").replace(/\/$/, "")
    }

    function currentOpenCodeSessionId() {
        var idx = sessionIndexById(root.currentSessionId)
        if (idx < 0)
            return ""
        return root.sessions[idx].openCodeSessionId || ""
    }

    function setCurrentOpenCodeSessionId(remoteSessionId) {
        var idx = sessionIndexById(root.currentSessionId)
        if (idx < 0)
            return
        var updated = root.sessions.slice()
        var item = Object.assign({}, updated[idx])
        item.openCodeSessionId = remoteSessionId || ""
        updated[idx] = item
        root.sessions = updated
        persistSessions()
    }

    function clearCurrentOpenCodeSessionIfNeeded() {
        if (!root.openCodeMode)
            return
        setCurrentOpenCodeSessionId("")
    }

    function extractReadableError(prefix, errObj, fallbackText) {
        if (errObj) {
            if (errObj.data && errObj.data.message)
                return prefix + errObj.data.message
            if (errObj.message)
                return prefix + errObj.message
            if (errObj.name)
                return prefix + errObj.name
        }
        return prefix + (fallbackText || "Unknown error")
    }

    function beginAssistantStreaming(modelLabel) {
        if (modelLabel)
            root.openCodeAssistantModelLabel = modelLabel
    }


    function updateAssistantStreamingContent(text, modelLabel) {
        var incoming = text || ""
        if (incoming === "")
            return
        if (modelLabel)
            root.openCodeAssistantModelLabel = modelLabel

        if (root.openCodeAssistantMessageIndex < 0) {
            var ts = Date.now()
            root.messages = root.messages.concat([{
                role: "assistant",
                content: incoming,
                time: nowTime(ts),
                at: ts,
                model: root.openCodeAssistantModelLabel || "OpenCode"
            }])
            root.openCodeAssistantMessageIndex = root.messages.length - 1
            root.streamingResponse = true
            if (!root.userScrolledUp)
                Qt.callLater(scrollToBottom)
            return
        }

        var copy = root.messages.slice()
        var item = Object.assign({}, copy[root.openCodeAssistantMessageIndex])
        var existing = item.content || ""

        // OpenCode streams can be cumulative or token-delta; handle both.
        if (incoming.indexOf(existing) === 0)
            item.content = incoming
        else if (existing.indexOf(incoming) === 0)
            item.content = existing
        else
            item.content = existing + incoming

        item.at = Date.now()
        item.time = nowTime(item.at)
        item.model = root.openCodeAssistantModelLabel || item.model || "OpenCode"
        root.streamingResponse = (item.content || "") !== ""
        copy[root.openCodeAssistantMessageIndex] = item
        root.messages = copy
        if (!root.userScrolledUp)
            Qt.callLater(scrollToBottom)
    }

    function finishOpenCodeRequest() {
        root.loading = false
        root.activeXhr = null
        root.openCodeActiveSessionId = ""
        root.openCodeAssistantMessageIndex = -1
        root.openCodeAssistantServerMessageId = ""
        root.openCodeErrorShownForRequest = false
        root.streamingResponse = false
        saveCurrentSessionState(true)
        triggerNotificationSound()
        processNextQueuedMessage()
    }

    function ensureOpenCodeEventStream() {
        if (root.openCodeEventXhr)
            return

        var xhr = new XMLHttpRequest()
        var buffer = ""
        var offset = 0
        var url = openCodeBaseUrl() + "/event"

        root.openCodeEventXhr = xhr

        xhr.open("GET", url, true)
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.LOADING && xhr.readyState !== XMLHttpRequest.DONE)
                return

            var delta = xhr.responseText.slice(offset)
            offset = xhr.responseText.length
            buffer += delta

            while (true) {
                var split = buffer.indexOf("\n\n")
                if (split < 0)
                    break

                var block = buffer.slice(0, split)
                buffer = buffer.slice(split + 2)

                var lines = block.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].indexOf("data:") !== 0)
                        continue
                    try {
                        var eventObj = JSON.parse(lines[i].slice(5).trim())
                        handleOpenCodeEvent(eventObj)
                    } catch (eventError) {
                    }
                }
            }

            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.openCodeEventXhr = null
                if (root.openCodeMode)
                    Qt.callLater(ensureOpenCodeEventStream)
            }
        }

        xhr.onerror = function() {
            root.openCodeEventXhr = null
        }

        try {
            xhr.send()
        } catch (streamError) {
            root.openCodeEventXhr = null
        }
    }

    function handleOpenCodeEvent(eventObj) {
        var props = eventObj && eventObj.properties ? eventObj.properties : {}
        var sessionId = props.sessionID || ""
        if (!sessionId || sessionId !== root.openCodeActiveSessionId)
            return

        if (eventObj.type === "message.updated") {
            var info = props.info || {}
            if (info.role === "assistant") {
                root.openCodeAssistantServerMessageId = info.id || root.openCodeAssistantServerMessageId
                beginAssistantStreaming((info.providerID && info.modelID) ? (info.providerID + "/" + info.modelID) : (info.modelID || "OpenCode"))
                if (info.error && !root.openCodeErrorShownForRequest) {
                    root.openCodeErrorShownForRequest = true
                    pushErrorMessage(extractReadableError("OpenCode: ", info.error, "Request failed."))
                }
            }
        } else if (eventObj.type === "message.part.updated") {
            var part = props.part || {}
            if (part.type === "text"
                    && root.openCodeAssistantServerMessageId !== ""
                    && part.messageID === root.openCodeAssistantServerMessageId)
                updateAssistantStreamingContent(part.text || "", "OpenCode")
        } else if (eventObj.type === "session.error") {
            if (!root.openCodeErrorShownForRequest) {
                root.openCodeErrorShownForRequest = true
                pushErrorMessage(extractReadableError("OpenCode: ", props.error, "Session error."))
            }
        } else if (eventObj.type === "session.status") {
            var status = props.status || {}
            if (status.type === "idle")
                finishOpenCodeRequest()
        } else if (eventObj.type === "session.idle") {
            finishOpenCodeRequest()
        } else if (eventObj.type === "permission.asked") {
            var p = props.permission || {}
            var permId = p.id || ""
            if (permId !== "") {
                var tool = p.tool || ""
                var args = p.arguments || {}
                var argStr = ""
                try {
                    argStr = typeof args === "string" ? args : JSON.stringify(args, null, 2)
                } catch (e) {
                    argStr = String(args)
                }

                var msg = {
                    role: "permission_request",
                    content: "OpenCode is asking for permission to run **" + tool + "**:\n\n```json\n" + argStr + "\n```",
                    model: "OpenCode Security",
                    id: "perm-" + permId,
                    permissionId: permId,
                    tool: tool,
                    arguments: args,
                    status: "pending",
                    at: Date.now()
                }

                root.messages = root.messages.concat([msg])
                saveCurrentSessionState(true)
                if (!root.userScrolledUp)
                    Qt.callLater(scrollToBottom)
            }
        } else if (eventObj.type === "permission.replied") {
            var pr = props.permission || {}
            var pId = pr.id || ""
            var response = pr.response || ""
            var copy = root.messages.slice()
            var updated = false
            for (var i = copy.length - 1; i >= 0; i--) {
                if (copy[i].role === "permission_request" && copy[i].permissionId === pId) {
                    copy[i].status = (response === "allow" ? "allowed" : "denied")
                    updated = true
                    break
                }
            }
            if (updated) {
                root.messages = copy
                saveCurrentSessionState(true)
            }
        } else if (eventObj.type === "session.next.step.ended") {
            var copy = root.messages.slice()
            var updated = false
            for (var idx = copy.length - 1; idx >= 0; idx--) {
                if (copy[idx].role === "assistant") {
                    var item = Object.assign({}, copy[idx])
                    item.tokens = props.tokens
                    item.cost = props.cost
                    copy[idx] = item
                    updated = true
                    break
                }
            }
            if (updated) {
                root.messages = copy
                saveCurrentSessionState(true)
            }
        } else if (eventObj.type === "question.asked") {
            var requestID = props.requestID || props.id || eventObj.id || ""
            if (requestID !== "") {
                var q = props.question || {}
                var qText = ""
                if (typeof props.question === "string") {
                    qText = props.question
                } else if (q.text) {
                    qText = q.text
                } else if (q.content) {
                    qText = q.content
                } else {
                    qText = props.text || props.content || "OpenCode requires clarification."
                }

                var alreadyExists = false
                for (var i = 0; i < root.messages.length; i++) {
                    if (root.messages[i].role === "question_request" && root.messages[i].questionId === requestID) {
                        alreadyExists = true
                        break
                    }
                }

                if (!alreadyExists) {
                    var msg = {
                        role: "question_request",
                        content: "OpenCode is asking a question:\n\n**" + qText + "**",
                        model: "OpenCode Question",
                        id: "question-" + requestID,
                        questionId: requestID,
                        status: "pending",
                        at: Date.now()
                    }

                    root.messages = root.messages.concat([msg])
                    saveCurrentSessionState(true)
                    if (!root.userScrolledUp)
                        Qt.callLater(scrollToBottom)
                }
            }
        } else if (eventObj.type === "question.replied") {
            var qId = props.requestID || props.id || eventObj.id || ""
            var copy = root.messages.slice()
            var updated = false
            for (var i = copy.length - 1; i >= 0; i--) {
                if (copy[i].role === "question_request" && copy[i].questionId === qId) {
                    if (copy[i].status === "pending" || copy[i].status === "answering...") {
                        copy[i].status = "answered"
                        updated = true
                    }
                    break
                }
            }
            if (updated) {
                root.messages = copy
                saveCurrentSessionState(true)
            }
        } else if (eventObj.type === "question.rejected" || eventObj.type === "question.cancelled") {
            var qId = props.requestID || props.id || eventObj.id || ""
            var copy = root.messages.slice()
            var updated = false
            for (var i = copy.length - 1; i >= 0; i--) {
                if (copy[i].role === "question_request" && copy[i].questionId === qId) {
                    if (copy[i].status === "pending" || copy[i].status === "dismissing...") {
                        copy[i].status = "dismissed"
                        updated = true
                    }
                    break
                }
            }
            if (updated) {
                root.messages = copy
                saveCurrentSessionState(true)
            }
        }
    }

    function ensureCurrentOpenCodeSession(successCallback, failureCallback) {
        var existing = currentOpenCodeSessionId()
        if (existing !== "") {
            successCallback(existing)
            return
        }

        var xhr = new XMLHttpRequest()
        xhr.open("POST", openCodeBaseUrl() + "/session", true)
        xhr.setRequestHeader("Content-Type", "application/json")

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return
            if (xhr.status >= 200 && xhr.status < 300) {
                triggerNotificationSound()
                try {
                    var obj = JSON.parse(xhr.responseText)
                    var remoteId = obj.id || ""
                    if (remoteId === "") {
                        failureCallback("OpenCode: server created a session without an id.")
                        return
                    }
                    setCurrentOpenCodeSessionId(remoteId)
                    successCallback(remoteId)
                } catch (parseError) {
                    failureCallback("OpenCode: could not parse session creation response.")
                }
            } else {
                failureCallback("OpenCode: failed to create a server session (HTTP " + xhr.status + ").")
            }
        }

        xhr.onerror = function() {
            failureCallback("OpenCode: could not reach " + openCodeBaseUrl() + "/session. Check that the server is still running.")
        }

        try {
            xhr.send(JSON.stringify({ title: root.currentSessionTitle || "KDE AI Chat" }))
        } catch (sendError) {
            failureCallback("OpenCode: failed to create session: " + sendError)
        }
    }

    function doOpenCodeRequest() {
        ensureOpenCodeEventStream()
        
        root.loading = true
        root.streamingResponse = false
        root.openCodeAssistantMessageIndex = -1
        root.openCodeAssistantServerMessageId = ""
        root.openCodeErrorShownForRequest = false

        ensureCurrentOpenCodeSession(
            function(remoteSessionId) {
                var xhr = new XMLHttpRequest()
                var modelId = (plasmoid.configuration.openCodeModel || "").trim()
                var providerId = (plasmoid.configuration.openCodeProvider || "").trim()
                var requestFinalized = false

                function failOpenCodeRequest(message) {
                    if (requestFinalized)
                        return
                    requestFinalized = true
                    if (!root.openCodeErrorShownForRequest) {
                        root.openCodeErrorShownForRequest = true
                        pushErrorMessage(message)
                    }
                    finishOpenCodeRequest()
                }

                root.activeXhr = xhr
                root.openCodeActiveSessionId = remoteSessionId

                xhr.open("POST", openCodeBaseUrl() + "/session/" + remoteSessionId + "/message", true)
                xhr.setRequestHeader("Content-Type", "application/json")

                xhr.onreadystatechange = function() {
                    if (xhr.readyState !== XMLHttpRequest.DONE)
                        return

                    if (requestFinalized)
                        return

                    if (xhr.status < 200 || xhr.status >= 300) {
                        var suffix = xhr.status > 0 ? ("HTTP " + xhr.status) : "transport error"
                        failOpenCodeRequest("OpenCode request failed (" + suffix + ") at " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message.")
                        return
                    }

                    try {
                        var obj = JSON.parse(xhr.responseText)
                        if (obj.info && obj.info.id)
                            root.openCodeAssistantServerMessageId = obj.info.id
                        if (obj.info && obj.info.error && !root.openCodeErrorShownForRequest) {
                            root.openCodeErrorShownForRequest = true
                            pushErrorMessage(extractReadableError("OpenCode: ", obj.info.error, "Request failed."))
                        }

                        if (obj.parts && obj.parts.length > 0) {
                            var combined = ""
                            for (var i = 0; i < obj.parts.length; i++) {
                                if (obj.parts[i].type === "text")
                                    combined += obj.parts[i].text || obj.parts[i].content || ""
                            }
                            if (combined !== "")
                                updateAssistantStreamingContent(combined, providerId + "/" + modelId)
                            else if (!root.openCodeErrorShownForRequest && root.openCodeAssistantMessageIndex < 0)
                                updateAssistantStreamingContent("(empty response)", providerId + "/" + modelId)
                        }
                    } catch (parseResponseError) {
                    }

                    requestFinalized = true
                    finishOpenCodeRequest()
                }

                xhr.onerror = function() {
                    failOpenCodeRequest("OpenCode: request could not reach " + openCodeBaseUrl() + "/session/" + remoteSessionId + "/message. The server is reachable, but this request path failed.")
                }

                try {
                    var lastMsg = root.messages[root.messages.length - 1]
                    var parts = []
                    if (lastMsg.attachments && lastMsg.attachments.length > 0) {
                        var payload = buildMessageContent(lastMsg.content, lastMsg.attachments, "openai")
                        if (typeof payload === "string") {
                            parts.push({ type: "text", text: payload })
                        } else {
                            for (var p = 0; p < payload.length; p++) {
                                var item = payload[p]
                                if (item.type === "text") {
                                    parts.push({ type: "text", text: item.text })
                                } else if (item.type === "image_url") {
                                    var mType = item.image_url.url.split(";")[0].split(":")[1]
                                    parts.push({
                                        type: "file",
                                        mime: mType,
                                        url: item.image_url.url
                                    })
                                }
                            }
                        }
                    } else {
                        parts.push({ type: "text", text: lastMsg.content || "" })
                    }

                    xhr.send(JSON.stringify({
                        model: {
                            providerID: providerId,
                            modelID: modelId
                        },
                        system: plasmoid.configuration.systemPrompt
                                || "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts.",
                        parts: parts
                    }))
                } catch (sendError) {
                    failOpenCodeRequest("OpenCode: failed to send request: " + sendError)
                }
            },
            function(errorMessage) {
                if (!root.openCodeErrorShownForRequest) {
                    root.openCodeErrorShownForRequest = true
                    pushErrorMessage(errorMessage)
                }
                finishOpenCodeRequest()
            }
        )
    }

    function scrollToBottom() {
        if (root.msgListViewRef) {
            root.msgListViewRef.positionViewAtEnd()
        }
    }

    function messageTimestampAt(index) {
        if (index < 0 || index >= root.messages.length)
            return Date.now()
        var m = root.messages[index] || {}
        return m.at || Date.now()
    }

    function messageDayKeyAt(index) {
        var d = new Date(messageTimestampAt(index))
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    }

    function dayBucketLabel(ts) {
        var target = new Date(ts)
        var now = new Date()
        var today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        var targetDay = new Date(target.getFullYear(), target.getMonth(), target.getDate())
        var daysDiff = Math.floor((today.getTime() - targetDay.getTime()) / 86400000)

        if (daysDiff === 0)
            return "Today"
        if (daysDiff === 1)
            return "Yesterday"
        if (daysDiff === 2)
            return "Day before yesterday"

        var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return months[target.getMonth()] + " " + pad2(target.getDate()) + ", " + target.getFullYear()
    }

    function countMessagesForDayKey(dayKey) {
        var count = 0
        for (var i = 0; i < root.messages.length; i++) {
            if (messageDayKeyAt(i) === dayKey)
                count++
        }
        return count
    }

    function dayDividerLabelForIndex(index) {
        var key = messageDayKeyAt(index)
        return dayBucketLabel(messageTimestampAt(index)) + " (" + countMessagesForDayKey(key) + ")"
    }

    function formatMessageTime(message, index) {
        if (message && message.time)
            return message.time
        return nowTime(messageTimestampAt(index))
    }

    function jumpOneMessageAbove() {
        if (!root.msgListViewRef || root.messages.length === 0)
            return
        
        var currentTop = -1
        for (var offset = 15; offset <= 100; offset += 20) {
            currentTop = root.msgListViewRef.indexAt(30, root.msgListViewRef.contentY + offset)
            if (currentTop >= 0)
                break
        }
        
        if (currentTop < 0) {
            currentTop = root.messages.length
        }
        
        var target = -1
        for (var i = currentTop - 1; i >= 0; i--) {
            var msg = root.messages[i]
            if (msg && msg.role === "user") {
                target = i
                break
            }
        }
        
        if (target >= 0) {
            root.userScrolledUp = true
            root.msgListViewRef.positionViewAtIndex(target, ListView.Beginning)
        } else {
            root.userScrolledUp = true
            root.msgListViewRef.positionViewAtBeginning()
        }
    }

    function jumpOneMessageBelow() {
        if (!root.msgListViewRef || root.messages.length === 0)
            return
        
        var currentTop = -1
        for (var offset = 15; offset <= 100; offset += 20) {
            currentTop = root.msgListViewRef.indexAt(30, root.msgListViewRef.contentY + offset)
            if (currentTop >= 0)
                break
        }
        
        if (currentTop < 0) {
            currentTop = -1
        }
        
        var target = -1
        for (var i = currentTop + 1; i < root.messages.length; i++) {
            var msg = root.messages[i]
            if (msg && msg.role === "user") {
                target = i
                break
            }
        }
        
        if (target >= 0) {
            var isLastUser = true
            for (var j = target + 1; j < root.messages.length; j++) {
                if (root.messages[j] && root.messages[j].role === "user") {
                    isLastUser = false
                    break
                }
            }
            if (isLastUser) {
                if (root.userScrolledUp) {
                    root.userScrolledUp = false
                    root.scrollToBottom()
                }
            } else {
                root.userScrolledUp = true
                root.msgListViewRef.positionViewAtIndex(target, ListView.Beginning)
            }
        } else {
            if (root.userScrolledUp) {
                root.userScrolledUp = false
                root.scrollToBottom()
            }
        }
    }

    function formatTokensUsage(tokens, cost) {
        if (!tokens)
            return ""
        
        var parts = []
        if (tokens.input !== undefined)
            parts.push("Input: " + tokens.input)
        if (tokens.output !== undefined)
            parts.push("Output: " + tokens.output)
        if (tokens.reasoning !== undefined && tokens.reasoning > 0)
            parts.push("Reasoning: " + tokens.reasoning)
        if (tokens.cache && (tokens.cache.read > 0 || tokens.cache.write > 0)) {
            parts.push("Cache R/W: " + tokens.cache.read + "/" + tokens.cache.write)
        }
        
        var res = parts.join(" | ")
        if (cost !== undefined && cost > 0) {
            res += " | Cost: $" + cost.toFixed(5)
        }
        return res
    }

    function pushErrorMessage(text) {
        var ts = Date.now()
        root.messages = root.messages.concat([{ role: "error", content: "DEBUG: " + text, time: nowTime(ts), at: ts, model: "" }])
        scrollToBottom()
        saveCurrentSessionState(true)
    }

    function appendUserMessage(text, role, attachments) {
        var ts = Date.now()
        root.messages = root.messages.concat([{
            role: role || "user",
            content: text,
            time: nowTime(ts),
            at: ts,
            model: "",
            queueId: role === "queued" ? (++root.queueCounter) : 0,
            attachments: attachments || []
        }])
        saveCurrentSessionState(true)
        if (!root.userScrolledUp)
            Qt.callLater(scrollToBottom)
    }

    function validateCurrentSendTarget() {
        if (root.openCodeMode)
            return validateOpenCodeConfig()

        var provider = plasmoid.configuration.provider || "openai"
        var providerCfg = getProviderConfig(provider)
        return validateProviderConfig(provider, providerCfg)
    }

    function sendMessageByIndex(index) {
        var source = root.messages[index] || {}
        var text = (source.content || "").trim()
        var hasAttachments = source.attachments && source.attachments.length > 0
        if (!text && !hasAttachments)
            return

        var validationError = validateCurrentSendTarget()
        if (validationError !== "") {
            pushErrorMessage(validationError)
            return
        }

        if ((source.role || "") === "queued") {
            var copy = root.messages.slice()
            var queued = Object.assign({}, copy[index])
            queued.role = "user"
            queued.at = Date.now()
            queued.time = nowTime(queued.at)
            copy[index] = queued
            root.messages = copy
            saveCurrentSessionState(true)
        }

        setCurrentSessionSource(root.openCodeMode ? "opencode" : "provider")

        if (root.openCodeMode) {
            doOpenCodeRequest()
            return
        }

        var provider = plasmoid.configuration.provider || "openai"
        var providerCfg = getProviderConfig(provider)

        if (providerCfg.type === "anthropic") {
            doAnthropicRequest(providerCfg.apiKey, providerCfg.model)
        } else {
            doOpenAICompatRequest(
                providerCfg.baseUrl,
                providerCfg.apiKey,
                providerCfg.model,
                providerCfg.headers,
                providerCfg.model
            )
        }
    }

    function processNextQueuedMessage() {
        if (root.loading)
            return
        for (var i = 0; i < root.messages.length; i++) {
            if ((root.messages[i].role || "") === "queued") {
                sendMessageByIndex(i)
                return
            }
        }
    }

    function providerDisplayName(providerId) {
        if (providerId === "openai") return "OpenAI"
        if (providerId === "anthropic") return "Anthropic"
        if (providerId === "groq") return "Groq"
        if (providerId === "deepseek") return "DeepSeek"
        if (providerId === "minimax") return "MiniMax"
        if (providerId === "fireworks") return "Fireworks"
        if (providerId === "google") return "Google Gemini"
        if (providerId === "openrouter") return "OpenRouter"
        if (providerId === "mistral") return "Mistral"
        if (providerId === "cloudflare") return "Cloudflare"
        if (providerId === "nvidia") return "NVIDIA NIM"
        if (providerId === "huggingface") return "Hugging Face"
        if (providerId === "xai") return "xAI"
        if (providerId === "lmstudio") return "LM Studio"
        if (providerId === "local") return "Local"
        return providerId || "Selected provider"
    }

    function validateOpenCodeConfig() {
        var missing = []
        if (!(plasmoid.configuration.openCodeUrl || "").trim())
            missing.push("OpenCode URL")
        if (!(plasmoid.configuration.openCodeProvider || "").trim())
            missing.push("OpenCode provider")
        if (!(plasmoid.configuration.openCodeModel || "").trim())
            missing.push("OpenCode model")

        if (missing.length > 0)
            return "Cannot send yet. Configure: " + missing.join(", ") + "."
        return ""
    }

    function validateProviderConfig(providerId, cfg) {
        if (!cfg)
            return "Provider configuration missing."

        var missing = []
        var name = providerDisplayName(providerId)

        if (!providerId)
            missing.push("provider")
        if (!cfg.baseUrl && cfg.type !== "anthropic")
            missing.push("base URL")
        if (!cfg.model)
            missing.push("model")
        if (cfg.type === "anthropic" && !cfg.apiKey)
            missing.push("API key")
        if (cfg.type !== "anthropic" && !cfg.allowEmptyKey && !cfg.apiKey)
            missing.push("API key")

        if (missing.length > 0)
            return "Cannot send with " + name + ". Missing: " + missing.join(", ") + "."

        return ""
    }

    function sendMessage() {
        try {
            var text = (root.chatInputText || "").trim()
            var attachments = root.attachedFiles || []
            if (text === "" && attachments.length === 0)
                return

            root.attachedFiles = []
            root.chatInputText = ""
            root.clearChatInput()
            root.userScrolledUp = false

            if (root.loading) {
                appendUserMessage(text, "queued", attachments)
                return
            }

            appendUserMessage(text, "user", attachments)
            sendMessageByIndex(root.messages.length - 1)
        } catch (err) {
            root.loading = false
            root.activeXhr = null
            pushErrorMessage("Send failed: " + err)
            processNextQueuedMessage()
        }
    }

    function getProviderConfig(provider) {
        if (provider === "anthropic") {
            return {
                type: "anthropic",
                apiKey: (plasmoid.configuration.anthropicApiKey || "").trim(),
                model: plasmoid.configuration.anthropicModel || "",
                allowEmptyKey: false
            }
        }
        if (provider === "local") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.localBaseUrl || "http://localhost:11434/v1",
                apiKey: "",
                model: plasmoid.configuration.localModel || "",
                headers: null,
                allowEmptyKey: true
            }
        }
        if (provider === "ollama") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.ollamaBaseUrl || "http://localhost:11434/v1",
                apiKey: "",
                model: plasmoid.configuration.ollamaModel || "",
                headers: null,
                allowEmptyKey: true
            }
        }
        if (provider === "lmstudio") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.lmStudioBaseUrl || "http://localhost:1234/v1",
                apiKey: "",
                model: plasmoid.configuration.lmStudioModel || "",
                headers: null,
                allowEmptyKey: true
            }
        }
        if (provider === "groq") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.groqBaseUrl || "https://api.groq.com/openai/v1",
                apiKey: (plasmoid.configuration.groqApiKey || "").trim(),
                model: plasmoid.configuration.groqModel || "",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "deepseek") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.deepSeekBaseUrl || "https://api.deepseek.com",
                apiKey: (plasmoid.configuration.deepSeekApiKey || "").trim(),
                model: plasmoid.configuration.deepSeekModel || "",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "minimax") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.miniMaxBaseUrl || "https://api.minimax.io/v1",
                apiKey: (plasmoid.configuration.miniMaxApiKey || "").trim(),
                model: plasmoid.configuration.miniMaxModel || "",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "fireworks") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.fireworksBaseUrl || "https://api.fireworks.ai/inference/v1",
                apiKey: (plasmoid.configuration.fireworksApiKey || "").trim(),
                model: plasmoid.configuration.fireworksModel || "",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "google") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.googleBaseUrl || "https://generativelanguage.googleapis.com/v1beta/openai/",
                apiKey: (plasmoid.configuration.googleApiKey || "").trim(),
                model: plasmoid.configuration.googleModel || "",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "openrouter") {
            var headers = {}
            var referer = plasmoid.configuration.openRouterReferer || "https://github.com/racstan/KDE-AI-Chat"
            var title = plasmoid.configuration.openRouterTitle || "KDE AI Chat"
            headers["HTTP-Referer"] = referer
            headers["X-Title"] = title
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.openRouterBaseUrl || "https://openrouter.ai/api/v1",
                apiKey: (plasmoid.configuration.openRouterApiKey || "").trim(),
                model: plasmoid.configuration.openRouterModel || "",
                headers: headers,
                allowEmptyKey: false
            }
        }
        if (provider === "mistral") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.mistralBaseUrl || "https://api.mistral.ai/v1",
                apiKey: (plasmoid.configuration.mistralApiKey || "").trim(),
                model: plasmoid.configuration.mistralModel || "",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "cloudflare") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.cloudflareBaseUrl || "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1",
                apiKey: (plasmoid.configuration.cloudflareApiKey || "").trim(),
                model: plasmoid.configuration.cloudflareModel || "",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "nvidia") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.nvidiaBaseUrl || "https://integrate.api.nvidia.com/v1",
                apiKey: (plasmoid.configuration.nvidiaApiKey || "").trim(),
                model: plasmoid.configuration.nvidiaModel || "",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "huggingface") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.huggingFaceBaseUrl || "https://router.huggingface.co/v1",
                apiKey: (plasmoid.configuration.huggingFaceApiKey || "").trim(),
                model: plasmoid.configuration.huggingFaceModel || "",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "xai") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.xaiBaseUrl || "https://api.x.ai/v1",
                apiKey: (plasmoid.configuration.xaiApiKey || "").trim(),
                model: plasmoid.configuration.xaiModel || "",
                headers: null,
                allowEmptyKey: false
            }
        }
        return {
            type: "openai-compat",
            baseUrl: plasmoid.configuration.baseUrl || "https://api.openai.com/v1",
            apiKey: (plasmoid.configuration.apiKey || "").trim(),
            model: plasmoid.configuration.model || "",
            headers: null,
            allowEmptyKey: false
        }
    }

    function buildOpenAICompatPayload() {
        var sys = plasmoid.configuration.systemPrompt
                  || "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts."
        var arr = [{ role: "system", content: sys }]
        for (var i = 0; i < root.messages.length; i++) {
            var m = root.messages[i]
            if (m.role === "user" || m.role === "assistant") {
                if (m.role === "user" && m.attachments && m.attachments.length > 0) {
                    var payloadContent = buildMessageContent(m.content, m.attachments, "openai")
                    arr.push({ role: m.role, content: payloadContent })
                } else {
                    arr.push({ role: m.role, content: m.content })
                }
            }
        }
        return arr
    }

    function buildAnthropicPayload() {
        var arr = []
        for (var i = 0; i < root.messages.length; i++) {
            var m = root.messages[i]
            if (m.role === "user" || m.role === "assistant") {
                if (m.role === "user" && m.attachments && m.attachments.length > 0) {
                    var payloadContent = buildMessageContent(m.content, m.attachments, "anthropic")
                    arr.push({ role: m.role, content: payloadContent })
                } else {
                    arr.push({ role: m.role, content: m.content })
                }
            }
        }
        return arr
    }

    function doOpenAICompatRequest(baseUrl, apiKey, model, extraHeaders, modelLabel) {
        var url = (baseUrl || "").replace(/\/$/, "") + "/chat/completions"
        var xhr = new XMLHttpRequest()
        var errorHandled = false

        try {
            xhr.open("POST", url, true)
            xhr.setRequestHeader("Content-Type", "application/json")
            if (apiKey !== "") {
                var safeKey = apiKey.substring(0, Math.min(8, apiKey.length)) + "... (" + apiKey.length + " chars)"
                console.log("DEBUG: Sending request to " + url + " with auth key starting with: " + safeKey)
                xhr.setRequestHeader("Authorization", "Bearer " + apiKey)
            } else {
                console.log("DEBUG: Sending request to " + url + " without Authorization header (empty key)")
            }
            if (extraHeaders) {
                for (var headerName in extraHeaders) {
                    if (Object.prototype.hasOwnProperty.call(extraHeaders, headerName) && extraHeaders[headerName])
                        xhr.setRequestHeader(headerName, extraHeaders[headerName])
                }
            }
        } catch (setupError) {
            root.loading = false
            root.activeXhr = null
            pushErrorMessage("Failed to start request: " + setupError)
            return
        }

        root.loading = true
        root.activeXhr = xhr

        // Non-streaming: wait for the complete response, then display it at once.
        // This is intentional — streaming caused the QML engine to re-render on every
        // individual token, saturating the main thread and freezing the KDE desktop.
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            root.loading = false
            root.activeXhr = null

            if (xhr.status < 200 || xhr.status >= 300) {
                if (errorHandled)
                    return
                errorHandled = true
                var err = "Request to " + url + " failed"
                if (xhr.status)
                    err += " (HTTP " + xhr.status + ")"
                try {
                    var eobj = JSON.parse(xhr.responseText)
                    if (eobj.error) {
                        if (typeof eobj.error === "string") {
                            err += " | " + eobj.error
                        } else {
                            if (eobj.error.message)
                                err = "API Error (" + xhr.status + "): " + eobj.error.message
                            if (eobj.error.metadata) {
                                try {
                                    err += " | " + JSON.stringify(eobj.error.metadata)
                                } catch(ex) {
                                    err += " | " + eobj.error.metadata
                                }
                            }
                        }
                    } else if (eobj.detail) {
                        err += " | " + eobj.detail
                    } else if (eobj.message) {
                        err += " | " + eobj.message
                    }
                } catch (e2) {
                }
                pushErrorMessage(err)
                processNextQueuedMessage()
                return
            }

            try {
                var parsed = JSON.parse(xhr.responseText)
                var finalText = (parsed.choices && parsed.choices[0]
                                 && parsed.choices[0].message
                                 && parsed.choices[0].message.content) || ""
                if (finalText !== "") {
                    var doneTs = Date.now()
                    var msgObj = {
                        role: "assistant",
                        content: finalText,
                        time: nowTime(doneTs),
                        at: doneTs,
                        model: modelLabel || model || ""
                    }
                    if (parsed.usage) {
                        msgObj.tokens = {
                            input: parsed.usage.prompt_tokens || 0,
                            output: parsed.usage.completion_tokens || 0
                        }
                    }
                    root.messages = root.messages.concat([msgObj])
                    if (!root.userScrolledUp)
                        Qt.callLater(scrollToBottom)
                } else {
                    pushErrorMessage("The model returned an empty response.")
                }
            } catch (parseError) {
                pushErrorMessage("Failed to parse response: " + parseError)
            }

            triggerNotificationSound()
            saveCurrentSessionState(true)
            processNextQueuedMessage()
        }

        xhr.onerror = function() {
            if (errorHandled)
                return
            errorHandled = true
            root.loading = false
            root.activeXhr = null
            pushErrorMessage("Could not reach " + url + ". Check the server URL and whether that endpoint accepts API requests.")
            processNextQueuedMessage()
        }

        try {
            xhr.send(JSON.stringify({
                model: model,
                messages: buildOpenAICompatPayload(),
                stream: false
            }))
        } catch (sendError) {
            root.loading = false
            root.activeXhr = null
            pushErrorMessage("Failed to send request: " + sendError)
        }
    }

    function doAnthropicRequest(apiKey, model) {
        if (!apiKey) {
            pushErrorMessage("Anthropic API key missing in settings.")
            processNextQueuedMessage()
            return
        }

        var xhr = new XMLHttpRequest()
        var errorHandled = false
        root.loading = true
        root.activeXhr = xhr

        xhr.open("POST", "https://api.anthropic.com/v1/messages", true)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("x-api-key", apiKey)
        xhr.setRequestHeader("anthropic-version", "2023-06-01")

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            root.loading = false
            root.activeXhr = null

            if (xhr.status >= 200 && xhr.status < 300) {
                triggerNotificationSound()
                try {
                    var obj = JSON.parse(xhr.responseText)
                    var text = ""
                    if (obj.content && obj.content.length) {
                        for (var i = 0; i < obj.content.length; i++) {
                            if (obj.content[i].type === "text")
                                text += obj.content[i].text
                        }
                    }
                    var ts = Date.now()
                    var msgObj = {
                        role: "assistant",
                        content: text || "(empty response)",
                        time: nowTime(ts),
                        at: ts,
                        model: model || ""
                    }
                    if (obj.usage) {
                        msgObj.tokens = {
                            input: obj.usage.input_tokens || 0,
                            output: obj.usage.output_tokens || 0
                        }
                    }
                    root.messages = root.messages.concat([msgObj])
                } catch (e) {
                    pushErrorMessage("Failed to parse Anthropic response")
                }
            } else {
                var err = "Anthropic HTTP " + xhr.status
                try {
                    var eobj = JSON.parse(xhr.responseText)
                    if (eobj.error) {
                        if (typeof eobj.error === "string") {
                            err += " | " + eobj.error
                        } else {
                            if (eobj.error.message)
                                err = "Anthropic Error (" + xhr.status + "): " + eobj.error.message
                            if (eobj.error.type)
                                err = "[" + eobj.error.type + "] " + err
                        }
                    }
                } catch (e2) {
                }
                pushErrorMessage(err)
            }

            scrollToBottom()
            saveCurrentSessionState(true)
            processNextQueuedMessage()
        }

        xhr.onerror = function() {
            if (errorHandled)
                return
            errorHandled = true
            root.loading = false
            root.activeXhr = null
            pushErrorMessage("Could not reach https://api.anthropic.com/v1/messages. Check network access and API configuration.")
            processNextQueuedMessage()
        }

        xhr.send(JSON.stringify({
            model: model,
            max_tokens: 1024,
            system: plasmoid.configuration.systemPrompt
                    || "You are KDE AI Chat, a precise and helpful assistant. Give accurate answers, ask clarifying questions when context is missing, and clearly state uncertainty instead of inventing facts.",
            messages: buildAnthropicPayload()
        }))
    }

    P5Support.DataSource {
        id: soundDs
        engine: "executable"
        connectedSources: []
    }

    function triggerNotificationSound() {
        if (!plasmoid.configuration.playNotificationSound)
            return
        soundDs.connectSource("pw-play /usr/share/sounds/ocean/stereo/message-new-instant.oga || paplay /usr/share/sounds/ocean/stereo/message-new-instant.oga || aplay /usr/share/sounds/freedesktop/stereo/bell.oga || canberra-gtk-play -i message-new-instant")
    }

    function respondToPermission(permissionId, approved) {
        var sessionId = root.openCodeActiveSessionId
        if (!sessionId) {
            var idx = findSessionIndex(root.currentSessionId)
            if (idx >= 0) {
                sessionId = root.sessions[idx].openCodeSessionId || ""
            }
        }
        if (!sessionId || !permissionId)
            return

        var copy = root.messages.slice()
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                copy[i].status = approved ? "allowing..." : "denying..."
                break
            }
        }
        root.messages = copy

        var xhr = new XMLHttpRequest()
        var primaryUrl = openCodeBaseUrl() + "/session/" + sessionId + "/permission/" + permissionId
        var fallbackUrl = openCodeBaseUrl() + "/session/" + sessionId + "/permissions/" + permissionId
        var responseValue = approved ? "allow" : "deny"

        function sendToUrl(url, isRetry) {
            xhr.open("POST", url, true)
            xhr.setRequestHeader("Content-Type", "application/json")
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return

                if (xhr.status >= 200 && xhr.status < 300) {
                    var copy = root.messages.slice()
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                            copy[i].status = approved ? "allowed" : "denied"
                            break
                        }
                    }
                    root.messages = copy
                    saveCurrentSessionState(true)
                } else if (xhr.status === 404 && !isRetry) {
                    sendToUrl(fallbackUrl, true)
                } else {
                    var copy = root.messages.slice()
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                            copy[i].status = "pending"
                            break
                        }
                    }
                    root.messages = copy
                    pushErrorMessage("OpenCode: failed to reply to permission (HTTP " + xhr.status + ").")
                }
            }
            xhr.onerror = function() {
                if (!isRetry) {
                    sendToUrl(fallbackUrl, true)
                } else {
                    var copy = root.messages.slice()
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "permission_request" && copy[i].permissionId === permissionId) {
                            copy[i].status = "pending"
                            break
                        }
                    }
                    root.messages = copy
                    pushErrorMessage("OpenCode: could not reach permission reply server endpoint.")
                }
            }
            xhr.send(JSON.stringify({ response: responseValue }))
        }

        sendToUrl(primaryUrl, false)
    }

    function respondToQuestion(questionId, answerValue, isReject) {
        var sessionId = root.openCodeActiveSessionId
        if (!sessionId) {
            var idx = findSessionIndex(root.currentSessionId)
            if (idx >= 0) {
                sessionId = root.sessions[idx].openCodeSessionId || ""
            }
        }
        if (!questionId)
            return

        var copy = root.messages.slice()
        for (var i = 0; i < copy.length; i++) {
            if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                copy[i].status = isReject ? "dismissing..." : "answering..."
                break
            }
        }
        root.messages = copy

        var xhr = new XMLHttpRequest()
        var action = isReject ? "reject" : "reply"
        
        var urls = [
            openCodeBaseUrl() + "/question/" + questionId + "/" + action,
            openCodeBaseUrl() + "/session/" + sessionId + "/question/" + questionId + "/" + action,
            openCodeBaseUrl() + "/session/" + sessionId + "/questions/" + questionId + "/" + action
        ]

        var currentUrlIdx = 0

        function tryNextUrl() {
            if (currentUrlIdx >= urls.length) {
                var copy = root.messages.slice()
                for (var i = 0; i < copy.length; i++) {
                    if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                        copy[i].status = "pending"
                        break
                    }
                }
                root.messages = copy
                pushErrorMessage("OpenCode: failed to reply to question endpoint.")
                return
            }

            var url = urls[currentUrlIdx]
            currentUrlIdx++

            xhr.open("POST", url, true)
            xhr.setRequestHeader("Content-Type", "application/json")
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return

                if (xhr.status >= 200 && xhr.status < 300) {
                    var copy = root.messages.slice()
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                            copy[i].status = isReject ? "dismissed" : "answered"
                            copy[i].submittedAnswer = answerValue
                            break
                        }
                    }
                    root.messages = copy
                    saveCurrentSessionState(true)
                } else if (xhr.status === 404) {
                    tryNextUrl()
                } else {
                    var copy = root.messages.slice()
                    for (var i = 0; i < copy.length; i++) {
                        if (copy[i].role === "question_request" && copy[i].questionId === questionId) {
                            copy[i].status = "pending"
                            break
                        }
                    }
                    root.messages = copy
                    pushErrorMessage("OpenCode: failed to reply to question (HTTP " + xhr.status + ").")
                }
            }

            xhr.onerror = function() {
                tryNextUrl()
            }

            try {
                xhr.send(JSON.stringify(isReject ? {} : { answer: answerValue }))
            } catch (err) {
                tryNextUrl()
            }
        }

        tryNextUrl()
    }

    function stopStreaming() {
        if (root.activeXhr) {
            try {
                root.activeXhr.abort()
            } catch (e) {
            }
            root.activeXhr = null
        }
        root.loading = false
        saveCurrentSessionState(true)
        processNextQueuedMessage()
    }

    function convertMarkdownToHtml(markdown) {
        if (!markdown) return "";

        var isDark = root.popupIsDark;
        var codeBg = isDark ? "#2d3139" : "#f0f2f5";
        var codeColor = isDark ? "#abb2bf" : "#383a42";
        var inlineBg = isDark ? "#3e4452" : "#e5e5e5";
        var inlineColor = isDark ? "#e06c75" : "#a626a4";
        var linkColor = isDark ? "#61afef" : "#4078f2";
        var borderColor = isDark ? "#3e4452" : "#d0d4dc";

        var html = markdown;

        // 1. Escape HTML
        html = html.replace(/&/g, "&amp;")
                   .replace(/</g, "&lt;")
                   .replace(/>/g, "&gt;");

        // 2. Extract code blocks with safe placeholders
        var codeBlocks = [];
        
        // Code blocks with language specifiers
        html = html.replace(/```([a-zA-Z0-9+#-_]*)\n([\s\S]*?)```/g, function(match, lang, code) {
            var blockIdx = codeBlocks.length;
            var rendered = '<div style="background-color: ' + codeBg + '; color: ' + codeColor + '; font-family: monospace; padding: 10px; margin: 8px 0px; border-radius: 6px; border: 1px solid ' + borderColor + ';">'
                         + '<div style="font-size: 0.85em; color: ' + (isDark ? "#5c6370" : "#a0a1a7") + '; margin-bottom: 5px; font-weight: bold; border-bottom: 1px solid ' + borderColor + '; padding-bottom: 3px;">' + (lang || "code") + '</div>'
                         + '<pre style="margin: 0px; white-space: pre-wrap; font-family: monospace;">' + code.trim() + '</pre>'
                         + '</div>';
            codeBlocks.push(rendered);
            return "%%CODEBLOCKPLACEHOLDER" + blockIdx + "%%";
        });

        // Code blocks without language specifiers
        html = html.replace(/```([\s\S]*?)```/g, function(match, code) {
            var blockIdx = codeBlocks.length;
            var rendered = '<div style="background-color: ' + codeBg + '; color: ' + codeColor + '; font-family: monospace; padding: 10px; margin: 8px 0px; border-radius: 6px; border: 1px solid ' + borderColor + ';">'
                         + '<pre style="margin: 0px; white-space: pre-wrap; font-family: monospace;">' + code.trim() + '</pre>'
                         + '</div>';
            codeBlocks.push(rendered);
            return "%%CODEBLOCKPLACEHOLDER" + blockIdx + "%%";
        });

        // 3. Inline code
        html = html.replace(/`([^`\n]+)`/g, '<code style="background-color: ' + inlineBg + '; color: ' + inlineColor + '; font-family: monospace; padding: 2px 4px; border-radius: 3px; font-size: 0.95em;">$1</code>');

        // 4. Headers
        html = html.replace(/^#### (.*?)$/gm, '<h4 style="margin: 8px 0px; font-weight: bold;">$1</h4>');
        html = html.replace(/^### (.*?)$/gm, '<h3 style="margin: 10px 0px; font-weight: bold;">$1</h3>');
        html = html.replace(/^## (.*?)$/gm, '<h2 style="margin: 12px 0px; font-weight: bold;">$1</h2>');
        html = html.replace(/^# (.*?)$/gm, '<h1 style="margin: 14px 0px; font-weight: bold;">$1</h1>');

        // 5. Bold & Italic
        html = html.replace(/\*\*([^\*\n]+)\*\*/g, '<b>$1</b>');
        html = html.replace(/__([^\_\n]+)__/g, '<b>$1</b>');
        html = html.replace(/\*([^\*\n]+)\*/g, '<i>$1</i>');
        html = html.replace(/_([^\_\n]+)_/g, '<i>$1</i>');

        // 6. Links [text](url)
        html = html.replace(/\[([^\]\n]+)\]\(([^)\n]+)\)/g, '<a href="$2" style="color: ' + linkColor + '; text-decoration: underline;">$1</a>');

        // 7. Bullet Lists
        html = html.replace(/^\s*[-*+]\s+(.*?)$/gm, '<ul><li>$1</li></ul>');
        html = html.replace(/<\/ul>\s*\n?\s*<ul>/g, "");

        // 8. Numbered Lists
        html = html.replace(/^\s*(\d+)\.\s+(.*?)$/gm, '<ol><li value="$1">$2</li></ol>');
        html = html.replace(/<\/ol>\s*\n?\s*<ol>/g, "");

        // 9. Paragraph double and single newlines
        html = html.replace(/\n\n/g, "<br/><br/>");
        html = html.replace(/\n/g, "<br/>");

        // 10. Restore code blocks
        for (var idx = 0; idx < codeBlocks.length; idx++) {
            html = html.replace("%%CODEBLOCKPLACEHOLDER" + idx + "%%", codeBlocks[idx]);
        }

        return html;
    }

    function fileIconName(filename) {
        var ext = filename.split('.').pop().toLowerCase();
        if (ext === 'pdf') return 'document-pdf';
        if (ext === 'csv') return 'text-csv';
        if (ext === 'docx' || ext === 'doc') return 'document-word';
        if (ext === 'md' || ext === 'txt') return 'text-plain';
        return 'document-text';
    }

    function removeAttachedFile(index) {
        var files = root.attachedFiles.slice()
        if (index >= 0 && index < files.length) {
            files.splice(index, 1)
            root.attachedFiles = files
        }
    }

    function getDocExtractorPath() {
        var urlStr = String(Qt.resolvedUrl("doc_extractor.py"));
        if (urlStr.indexOf("file://") === 0) {
            urlStr = urlStr.substring(7);
        }
        return decodeURIComponent(urlStr);
    }

    function attachFile(fileUrl) {
        var localPath = String(fileUrl);
        if (localPath.indexOf("file://") === 0) {
            localPath = localPath.substring(7);
        }
        localPath = decodeURIComponent(localPath);

        var files = root.attachedFiles.slice();
        for (var i = 0; i < files.length; i++) {
            if (files[i].path === localPath) {
                return;
            }
        }

        var filename = localPath.substring(localPath.lastIndexOf("/") + 1);
        var newFile = {
            path: localPath,
            name: filename,
            loading: true,
            error: "",
            type: "",
            content: "",
            mimeType: "",
            size: 0
        };

        files.push(newFile);
        root.attachedFiles = files;

        var docExtractorPath = getDocExtractorPath();
        var escapedPath = localPath.replace(/'/g, "'\\''");
        var cmd = "python3 '" + docExtractorPath + "' '" + escapedPath + "'";
        fileReaderDs.connectSource(cmd);
    }

    function buildMessageContent(text, attachments, apiType) {
        var docs = []
        var imgs = []
        for (var i = 0; i < attachments.length; i++) {
            var att = attachments[i]
            if (att.type === "image") {
                imgs.push(att)
            } else if (att.type === "text") {
                docs.push(att)
            }
        }

        var compiledPrompt = ""
        for (var d = 0; d < docs.length; d++) {
            compiledPrompt += "[Attached File: " + docs[d].name + " (" + Math.round((docs[d].size || 0) / 1024) + " KB)]\n"
            compiledPrompt += "--- START OF FILE CONTENT ---\n"
            compiledPrompt += (docs[d].content || "") + "\n"
            compiledPrompt += "--- END OF FILE CONTENT ---\n\n"
        }
        compiledPrompt += text

        if (imgs.length === 0) {
            return compiledPrompt
        }

        var contentList = []
        if (compiledPrompt.trim() !== "") {
            contentList.push({ type: "text", text: compiledPrompt })
        }

        for (var imgIdx = 0; imgIdx < imgs.length; imgIdx++) {
            var image = imgs[imgIdx]
            if (apiType === "anthropic") {
                contentList.push({
                    type: "image",
                    source: {
                        type: "base64",
                        media_type: image.mimeType || "image/jpeg",
                        data: image.content
                    }
                })
            } else {
                contentList.push({
                    type: "image_url",
                    image_url: {
                        url: "data:" + (image.mimeType || "image/jpeg") + ";base64," + image.content
                    }
                })
            }
        }

        return contentList
    }

    P5Support.DataSource {
        id: fileReaderDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var exitCode = data["exit code"]
            var stdout = data["stdout"] || ""
            var stderr = data["stderr"] || ""

            if (sourceName.indexOf("--clipboard") !== -1) {
                if (exitCode === 0 && stderr.trim() === "") {
                    try {
                        var res = JSON.parse(stdout)
                        if (res.status === "success") {
                            var currentFiles = root.attachedFiles.slice()
                            if (res.mode === "files" && res.files) {
                                for (var f = 0; f < res.files.length; f++) {
                                    var fInfo = res.files[f]
                                    var exists = false
                                    for (var idx = 0; idx < currentFiles.length; idx++) {
                                        if (currentFiles[idx].path === fInfo.path) {
                                            exists = true
                                            break
                                        }
                                    }
                                    if (!exists) {
                                        currentFiles.push({
                                            name: fInfo.filename || fInfo.name,
                                            path: fInfo.path,
                                            type: fInfo.type,
                                            content: fInfo.content,
                                            mimeType: fInfo.mimeType,
                                            size: fInfo.size,
                                            loading: false,
                                            error: ""
                                        })
                                    }
                                }
                            } else if (res.mode === "image" && res.file) {
                                var fInfo = res.file
                                var exists = false
                                for (var idx = 0; idx < currentFiles.length; idx++) {
                                    if (currentFiles[idx].path === fInfo.path) {
                                        exists = true
                                        break
                                    }
                                }
                                if (!exists) {
                                    currentFiles.push({
                                        name: fInfo.name,
                                        path: fInfo.path,
                                        type: fInfo.type,
                                        content: fInfo.content,
                                        mimeType: fInfo.mimeType,
                                        size: fInfo.size,
                                        loading: false,
                                        error: ""
                                    })
                                }
                            }
                            root.attachedFiles = currentFiles
                        }
                    } catch (e) {
                        console.log("Failed to parse clipboard data: " + e)
                    }
                }
                disconnectSource(sourceName)
                return
            }

            var matchedIndex = -1
            var files = root.attachedFiles.slice()
            for (var i = 0; i < files.length; i++) {
                var filePath = files[i].path
                if (sourceName.indexOf(filePath) !== -1) {
                    matchedIndex = i
                    break
                }
            }

            if (matchedIndex === -1) {
                disconnectSource(sourceName)
                return
            }

            var fileObj = Object.assign({}, files[matchedIndex])
            fileObj.loading = false

            if (exitCode !== 0 || stderr.trim() !== "") {
                fileObj.error = stderr.trim() || ("Command exited with code " + exitCode)
            } else {
                try {
                    var res = JSON.parse(stdout)
                    if (res.status === "success") {
                        fileObj.type = res.type
                        fileObj.content = res.content
                        fileObj.mimeType = res.mimeType
                        fileObj.size = res.size
                    } else {
                        fileObj.error = res.message || "Failed to extract file contents"
                    }
                } catch (e) {
                    fileObj.error = "Failed to parse extractor output: " + e
                }
            }

            files[matchedIndex] = fileObj
            root.attachedFiles = files
            disconnectSource(sourceName)
        }
    }

    FileDialog {
        id: fileDialog
        title: "Attach Files"
        fileMode: FileDialog.OpenFiles
        nameFilters: [
            "All supported files (*.png *.jpg *.jpeg *.webp *.gif *.bmp *.pdf *.csv *.docx *.txt *.md *.json)",
            "Images (*.png *.jpg *.jpeg *.webp *.gif *.bmp)",
            "Documents (*.pdf *.docx *.csv *.txt *.md *.json)",
            "All files (*)"
        ]
        onAccepted: {
            for (var i = 0; i < selectedFiles.length; i++) {
                root.attachFile(selectedFiles[i])
            }
        }
    }

    // Invisible text editor acting as helper to interact with OS text clipboard (copy / paste)
    TextEdit {
        id: clipboardHelper
        visible: false
    }

    function checkClipboardForAttachments() {
        var docExtractorPath = getDocExtractorPath()
        var cmd = "python3 '" + docExtractorPath + "' --clipboard"
        fileReaderDs.connectSource(cmd)
    }

    function readClipboardText() {
        clipboardHelper.text = ""
        clipboardHelper.paste()
        return clipboardHelper.text
    }
}
