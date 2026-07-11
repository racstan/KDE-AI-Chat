import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.plasma.plasmoid

Item {
    id: repRoot
    anchors.fill: parent

    Kirigami.Theme.inherit: false
    Kirigami.Theme.colorGroup: root.popupIsDark ? Kirigami.Theme.Dark : Kirigami.Theme.Light
    Kirigami.Theme.backgroundColor: root.popupIsDark ? "#121212" : "#ffffff"
    Kirigami.Theme.alternateBackgroundColor: root.popupIsDark ? "#1a1a1a" : "#f5f7fa"
    Kirigami.Theme.textColor: root.popupIsDark ? "#f7fafc" : "#1a202c"
    Kirigami.Theme.highlightColor: "#3182ce"

    property int playingMessageIndex: -1
    property color activeHighlightColor: Kirigami.Theme.highlightColor

    SequentialAnimation {
        id: highlightPulse
        running: root.voiceManagerRef && root.voiceManagerRef.isPlaying
        loops: Animation.Infinite
        alwaysRunToEnd: false
        
        ColorAnimation {
            target: repRoot
            property: "activeHighlightColor"
            to: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.4)
            duration: 1000
            easing.type: Easing.InOutQuad
        }
        ColorAnimation {
            target: repRoot
            property: "activeHighlightColor"
            to: Kirigami.Theme.highlightColor
            duration: 1000
            easing.type: Easing.InOutQuad
        }
        
        onRunningChanged: {
            if (!running) {
                repRoot.activeHighlightColor = Kirigami.Theme.highlightColor;
            }
        }
    }

    Connections {
        target: root.voiceManagerRef || null
        function onIsPlayingChanged() {
            if (root.voiceManagerRef && !root.voiceManagerRef.isPlaying) {
                repRoot.playingMessageIndex = -1;
            }
        }
    }


    DropArea {
        id: dropArea

        anchors.fill: parent
        onEntered: function(drag) {
            if (drag.hasUrls)
                drag.accept(Qt.CopyAction);

        }
        onDropped: function(drop) {
            if (drop.hasUrls) {
                for (var i = 0; i < drop.urls.length; i++) {
                    root.attachFile(drop.urls[i]);
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
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

            PC3.ToolButton {
                icon.name: "window-pin"
                checkable: true
                checked: !root.hideOnWindowDeactivate
                onToggled: root.hideOnWindowDeactivate = !checked
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: checked ? "Unpin (close when clicking away)" : "Pin (keep open)"
            }

            PC3.ToolButton {
                icon.name: "configure"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Open Settings"
                onClicked: Plasmoid.internalAction("configure").trigger()
            }

            Item {
                Layout.fillWidth: true
            }

            PC3.Label {
                text: root.historyOnlyMode ? ((plasmoid.configuration.appDisplayName || "KDE AI Chat") + " History") : (root.currentSessionTitle || "New Chat")
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                Layout.fillWidth: false
                Layout.maximumWidth: Math.max(50, parent.width - 220)
                clip: true
            }

            Item {
                Layout.fillWidth: true
            }

            PC3.ToolButton {
                visible: !root.historyOnlyMode
                icon.name: "document-edit"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Rename current chat"
                onClicked: {
                    root.renamingCurrentChat = !root.renamingCurrentChat;
                    root.currentChatRenameDraft = root.currentSessionTitle || "";
                }
            }

            PC3.ToolButton {
                visible: !root.historyOnlyMode
                icon.name: "go-top"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Jump to first message"
                onClicked: {
                    if (root.msgListViewRef && root.msgListViewRef.count > 0) {
                        root.userScrolledUp = true;
                        root.msgListViewRef.positionViewAtBeginning();
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
                    root.userScrolledUp = false;
                    root.scrollToBottom();
                }
            }

            PC3.ToolButton {
                visible: !root.historyOnlyMode
                icon.name: "edit-clear-all"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Clear current chat history"
                enabled: !root.loading && root.messages.length > 0
                onClicked: {
                    root.messages = [];
                    root.editingMessageIndex = -1;
                    root.editingDraft = "";
                    root.clearCurrentOpenCodeSessionIfNeeded();
                    root.saveCurrentSessionState(true);
                }
            }

            PC3.ToolButton {
                visible: !root.historyOnlyMode && root.messages.length > 0
                icon.name: "document-export"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Export chat session"
                enabled: !root.loading
                onClicked: {
                    var cleanTitle = (root.currentSessionTitle || "New Chat").replace(/[\/\?<>\\:\*\|":\s]+/g, "_");
                    var now = new Date();
                    var year = now.getFullYear();
                    var month = String(now.getMonth() + 1).padStart(2, "0");
                    var day = String(now.getDate()).padStart(2, "0");
                    var hour = String(now.getHours()).padStart(2, "0");
                    var min = String(now.getMinutes()).padStart(2, "0");
                    var sec = String(now.getSeconds()).padStart(2, "0");
                    var timestamp = year + "-" + month + "-" + day + "_" + hour + "-" + min + "-" + sec;
                    exportFileDialog.currentFile = "file:///home/home/Documents/" + cleanTitle + "_" + timestamp + ".md";
                    exportFileDialog.open();
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
                color: Kirigami.Theme.textColor
                background: Rectangle {
                    color: Kirigami.Theme.backgroundColor
                    radius: Kirigami.Units.smallSpacing
                    border.color: parent.activeFocus ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
                    border.width: 1
                }
                onTextChanged: root.currentChatRenameDraft = text
                onAccepted: {
                    root.renameCurrentSession(root.currentChatRenameDraft);
                    root.renamingCurrentChat = false;
                }
            }

            PC3.ToolButton {
                icon.name: "dialog-ok-apply"
                onClicked: {
                    root.renameCurrentSession(root.currentChatRenameDraft);
                    root.renamingCurrentChat = false;
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
                            function onClearChatInput() {
                                msgInput.text = "";
                            }

                            target: root
                        }

                        ListView {
                            id: msgList

                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            model: root.messages
                            spacing: Kirigami.Units.largeSpacing
                            clip: true
                            reuseItems: true
                            cacheBuffer: 1000
                            Component.onCompleted: root.msgListViewRef = msgList
                            // Track whether user manually scrolled away from bottom
                            onMovementStarted: {
                                if (!msgList.atYEnd)
                                    root.userScrolledUp = true;

                            }
                            onAtYEndChanged: {
                                if (msgList.atYEnd)
                                    root.userScrolledUp = false;

                            }
                            onContentYChanged: {
                                if (!msgList.atYEnd) {
                                    if (msgList.moving || msgList.dragging || verticalScrollBar.pressed || verticalScrollBar.active)
                                        root.userScrolledUp = true;

                                }
                            }

                            QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                                id: verticalScrollBar
                            }

                            delegate: Item {
                                property bool showDayHeader: index === 0 || root.messageDayKeyAt(index) !== root.messageDayKeyAt(index - 1)
                                property bool reasoningExpanded: false

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
                                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
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
                                            color: modelData.role === "user" ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.2) : modelData.role === "queued" ? Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.18) : modelData.role === "error" ? Kirigami.Theme.negativeBackgroundColor : (modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "system_compacted") ? Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.12) : Kirigami.Theme.backgroundColor
                                            border.width: modelData.role === "error" || modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "system_compacted" ? 2 : 1
                                            border.color: modelData.role === "error" ? Kirigami.Theme.negativeTextColor : (modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "system_compacted") ? Kirigami.Theme.focusColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.16)
                                            anchors.right: modelData.role === "user" || modelData.role === "queued" ? parent.right : undefined
                                            anchors.left: modelData.role === "assistant" || modelData.role === "error" || modelData.role === "permission_request" || modelData.role === "question_request" || modelData.role === "system_compacted" ? parent.left : undefined
                                            anchors.margins: Kirigami.Units.largeSpacing

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
                                                        text: modelData.role === "user" ? "You" : modelData.role === "queued" ? "You (Queued)" : modelData.role === "error" ? "Error" : modelData.role === "question_request" ? "OpenCode Interactive Question" : modelData.role === "permission_request" ? "OpenCode Security Request" : modelData.role === "system_compacted" ? "Context Compacted" : "AI"
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

                                                Rectangle {
                                                    id: reasoningBlock

                                                    property string reasoningText: (root.currentStreamIndex === index && root.currentStreamReasoning !== "") ? root.currentStreamReasoning : (modelData.reasoning || "")

                                                    visible: modelData.role === "assistant" && reasoningText.length > 0 && root.editingMessageIndex !== index
                                                    width: parent.width
                                                    implicitHeight: reasoningCol.implicitHeight + Kirigami.Units.smallSpacing
                                                    radius: 6
                                                    color: Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.08)
                                                    border.width: 1
                                                    border.color: Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.22)

                                                    ColumnLayout {
                                                        id: reasoningCol
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.top: parent.top
                                                        anchors.margins: Kirigami.Units.smallSpacing
                                                        spacing: Kirigami.Units.smallSpacing

                                                        RowLayout {
                                                            Layout.fillWidth: true
                                                            spacing: Kirigami.Units.smallSpacing

                                                            Kirigami.Icon {
                                                                source: "help-about"
                                                                Layout.preferredWidth: Kirigami.Units.gridUnit
                                                                Layout.preferredHeight: Kirigami.Units.gridUnit
                                                            }

                                                            PC3.Label {
                                                                Layout.fillWidth: true
                                                                text: "Thinking"
                                                                font.bold: true
                                                                opacity: 0.85
                                                            }

                                                            QQC2.ToolButton {
                                                                text: reasoningExpanded ? "Hide" : "Show"
                                                                icon.name: reasoningExpanded ? "go-up" : "go-down"
                                                                onClicked: reasoningExpanded = !reasoningExpanded
                                                            }
                                                        }

                                                        PC3.Label {
                                                            visible: reasoningExpanded
                                                            Layout.fillWidth: true
                                                            wrapMode: Text.Wrap
                                                            textFormat: Text.PlainText
                                                            text: reasoningBlock.reasoningText
                                                            opacity: 0.82
                                                        }
                                                    }
                                                }

                                                Loader {
                                                    active: root.editingMessageIndex === index && modelData.role !== "error"
                                                    width: parent.width

                                                    sourceComponent: QQC2.TextArea {
                                                        width: parent ? parent.width : implicitWidth
                                                        text: root.editingDraft
                                                        wrapMode: Text.WordWrap
                                                        onTextChanged: root.editingDraft = text
                                                    }

                                                }

                                                TextEdit {
                                                     id: msgTextLabel
                                                     readOnly: true
                                                     cursorVisible: false

                                                    visible: root.editingMessageIndex !== index || modelData.role === "error"
                                                    width: parent.width
                                                    wrapMode: Text.Wrap
                                                    selectByMouse: true
                                                    
                                                    textFormat: modelData.role === "error" ? Text.PlainText : Text.MarkdownText
                                                    text: {
                                                        let baseText = (root.currentStreamIndex === index && root.currentStreamText !== "") ? root.currentStreamText : modelData.content;
                                                        let isPlayingThisMessage = root.voiceManagerRef && root.voiceManagerRef.isPlaying && repRoot.playingMessageIndex === index;
                                                        if (isPlayingThisMessage && root.voiceManagerRef.currentPlayingChunk) {
                                                            let chunk = root.voiceManagerRef.currentPlayingChunk;
                                                            if (chunk.length > 2) {
                                                                // Clean and split chunk into words
                                                                let cleanChunk = chunk.replace(/[^\w\s]/g, ' ').trim();
                                                                let words = cleanChunk.split(/\s+/).filter(function(w) { return w.length > 0; });
                                                                if (words.length > 0) {
                                                                    let regexStr = "";
                                                                    for (let i = 0; i < words.length; i++) {
                                                                        let escapedWord = words[i].replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                                                                        if (i > 0) {
                                                                            regexStr += "[^a-zA-Z0-9]*?";
                                                                        }
                                                                        regexStr += escapedWord;
                                                                    }
                                                                    try {
                                                                        let regex = new RegExp("(" + regexStr + ")", "i");
                                                                        let match = baseText.match(regex);
                                                                        if (match) {
                                                                            let matchedText = match[0];
                                                                            let startIdx = match.index;
                                                                            let before = baseText.substring(0, startIdx);
                                                                            let after = baseText.substring(startIdx + matchedText.length);
                                                                            let highlightStart = "<span style=\"background-color: " + repRoot.activeHighlightColor + "; color: " + Kirigami.Theme.highlightedTextColor + "; font-weight: bold;\"><u>";
                                                                            let highlightEnd = "</u></span>";
                                                                            return before + highlightStart + matchedText + highlightEnd + after;
                                                                        }
                                                                    } catch(e) {}
                                                                }
                                                                
                                                                // Fallback to simple replace
                                                                let escaped = chunk.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
                                                                let regex = new RegExp("(" + escaped + ")", "gi");
                                                                return baseText.replace(regex, "<span style=\"background-color: " + repRoot.activeHighlightColor + "; color: " + Kirigami.Theme.highlightedTextColor + "; font-weight: bold;\"><u>$1</u></span>");
                                                            }
                                                        }
                                                        return baseText;
                                                    }
                                                    color: modelData.role === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                                     font: Kirigami.Theme.defaultFont
                                                    onLinkActivated: function(link) {
                                                        Qt.openUrlExternally(link);
                                                    }
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
                                                            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.05)
                                                            border.width: 1
                                                            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)

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
                                                        text: modelData.status === "allowed" ? "Approved ✅" : modelData.status === "denied" ? "Rejected ❌" : modelData.status === "allowing..." ? "Approving..." : "Rejecting..."
                                                        font.bold: true
                                                        color: modelData.status === "allowed" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                                                    }

                                                }

                                                Column {
                                                    id: questionCol

                                                    property string qId: modelData.questionId || ""
                                                    property var qQuestions: modelData.questions || []
                                                    property bool qAllowCustom: modelData.allowCustom !== false
                                                    property string qStatus: modelData.status || ""

                                                    visible: modelData.role === "question_request"
                                                    width: parent.width
                                                    spacing: Kirigami.Units.smallSpacing

                                                    // Per-question sections when structured options are available
                                                    Repeater {
                                                        model: (questionCol.qStatus === "pending" && questionCol.qQuestions.length > 0) ? questionCol.qQuestions : []

                                                        delegate: Column {
                                                            id: questionItemCol

                                                            required property var modelData
                                                            required property int index
                                                            property bool qMultiple: modelData.multiple || false

                                                            width: parent.width
                                                            spacing: Kirigami.Units.smallSpacing

                                                            // Question header chip
                                                            Rectangle {
                                                                visible: (modelData.header || "") !== ""
                                                                width: qHeaderLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                                                                height: qHeaderLabel.implicitHeight + Kirigami.Units.smallSpacing
                                                                radius: 999
                                                                color: Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.18)

                                                                PC3.Label {
                                                                    id: qHeaderLabel

                                                                    anchors.centerIn: parent
                                                                    text: modelData.header || ""
                                                                    font.bold: true
                                                                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                                                                    color: Kirigami.Theme.focusColor
                                                                }

                                                            }

                                                            // Clickable option buttons
                                                            Flow {
                                                                width: parent.width
                                                                spacing: Kirigami.Units.smallSpacing
                                                                visible: modelData.options && modelData.options.length > 0

                                                                Repeater {
                                                                    model: modelData.options || []

                                                                    delegate: Rectangle {
                                                                        id: optionBtn

                                                                        required property var modelData
                                                                        required property int index
                                                                        property bool selected: false

                                                                        width: optBtnLabel.implicitWidth + Kirigami.Units.largeSpacing * 2
                                                                        height: optBtnLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                                                                        radius: 6
                                                                        color: selected ? Qt.rgba(Kirigami.Theme.focusColor.r, Kirigami.Theme.focusColor.g, Kirigami.Theme.focusColor.b, 0.3) : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                                                        border.width: selected ? 2 : 1
                                                                        border.color: selected ? Kirigami.Theme.focusColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                                                                        QQC2.ToolTip.visible: optionMa.containsMouse && (optionBtn.modelData.description || "") !== ""
                                                                        QQC2.ToolTip.text: optionBtn.modelData.description || ""

                                                                        PC3.Label {
                                                                            id: optBtnLabel

                                                                            anchors.centerIn: parent
                                                                            text: (optionBtn.selected ? "✓ " : "") + (optionBtn.modelData.label || "")
                                                                            font.bold: optionBtn.selected
                                                                            color: optionBtn.selected ? Kirigami.Theme.focusColor : Kirigami.Theme.textColor
                                                                        }

                                                                        MouseArea {
                                                                            id: optionMa

                                                                            anchors.fill: parent
                                                                            hoverEnabled: true
                                                                            cursorShape: Qt.PointingHandCursor
                                                                            onClicked: {
                                                                                optionBtn.selected = !optionBtn.selected;
                                                                                // For non-multiple questions, submit immediately on click
                                                                                if (!questionItemCol.qMultiple && optionBtn.selected)
                                                                                    root.respondToQuestion(questionCol.qId, optionBtn.modelData.label || "", false);

                                                                            }
                                                                        }

                                                                    }

                                                                }

                                                            }

                                                            // Separator between questions
                                                            Rectangle {
                                                                visible: index < (parent.model ? parent.model.length - 1 : 0)
                                                                width: parent.width
                                                                height: 1
                                                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                                                            }

                                                        }

                                                    }

                                                    // Custom answer text field (shown when custom is allowed or no options exist)
                                                    PC3.Label {
                                                        text: (questionCol.qQuestions.length > 0) ? "Or type a custom answer:" : "Your Answer:"
                                                        font.bold: true
                                                        visible: questionCol.qStatus === "pending" && questionCol.qAllowCustom
                                                    }

                                                    PC3.TextField {
                                                        id: questionReplyField

                                                        visible: questionCol.qStatus === "pending" && questionCol.qAllowCustom
                                                        width: parent.width
                                                        placeholderText: "Type your answer here..."
                                                        onAccepted: {
                                                            if (text.trim() !== "")
                                                                root.respondToQuestion(questionCol.qId, text, false);

                                                        }
                                                    }

                                                    Row {
                                                        width: parent.width
                                                        spacing: Kirigami.Units.largeSpacing

                                                        PC3.Button {
                                                            visible: questionCol.qStatus === "pending"
                                                            text: "Submit"
                                                            icon.name: "mail-send"
                                                            onClicked: root.submitQuestionAnswer(questionCol.qId, questionCol.qQuestions, questionReplyField)
                                                        }

                                                        PC3.Button {
                                                            visible: questionCol.qStatus === "pending"
                                                            text: "Dismiss"
                                                            icon.name: "dialog-cancel"
                                                            onClicked: root.respondToQuestion(questionCol.qId, "", true)
                                                        }

                                                        PC3.Label {
                                                            visible: questionCol.qStatus !== "pending"
                                                            text: questionCol.qStatus === "answered" ? "Answered: \"" + (modelData.submittedAnswer || "") + "\" ✅" : questionCol.qStatus === "dismissed" ? "Dismissed ❌" : questionCol.qStatus === "answering..." ? "Submitting..." : "Dismissing..."
                                                            font.bold: true
                                                            color: questionCol.qStatus === "answered" ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                                                        }

                                                    }

                                                }

                                                Rectangle {
                                                    visible: root.editingMessageIndex === index && modelData.role !== "error"
                                                    width: parent.width
                                                    height: editWarn.implicitHeight + Kirigami.Units.smallSpacing * 2
                                                    radius: 6
                                                    color: Qt.rgba(Kirigami.Theme.neutralTextColor.r, Kirigami.Theme.neutralTextColor.g, Kirigami.Theme.neutralTextColor.b, 0.1)

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

                                                // Context items (tool invocations) display
                                                Column {
                                                    visible: modelData.role === "assistant" && modelData.contextItems !== undefined && modelData.contextItems.length > 0
                                                    width: parent.width
                                                    spacing: 2

                                                    Row {
                                                        spacing: Kirigami.Units.smallSpacing

                                                        PC3.Label {
                                                            text: "📂 Context (" + (modelData.contextItems ? modelData.contextItems.length : 0) + ")"
                                                            font.pointSize: 7
                                                            font.bold: true
                                                            opacity: 0.6
                                                        }

                                                        PC3.Label {
                                                            id: contextToggle

                                                            property bool expanded: false

                                                            text: expanded ? "▲ hide" : "▼ show"
                                                            font.pointSize: 7
                                                            opacity: 0.5

                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: contextToggle.expanded = !contextToggle.expanded
                                                            }

                                                        }

                                                    }

                                                    Flow {
                                                        visible: contextToggle.expanded
                                                        width: parent.width
                                                        spacing: 3

                                                        Repeater {
                                                            model: modelData.contextItems || []

                                                            delegate: Rectangle {
                                                                required property string modelData

                                                                width: ctxLabel.implicitWidth + 10
                                                                height: ctxLabel.implicitHeight + 4
                                                                radius: 999
                                                                color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)

                                                                PC3.Label {
                                                                    id: ctxLabel

                                                                    anchors.centerIn: parent
                                                                    text: modelData
                                                                    font.pointSize: 7
                                                                    opacity: 0.6
                                                                    elide: Text.ElideMiddle
                                                                    maximumLineCount: 1
                                                                }

                                                            }

                                                        }

                                                    }

                                                }

                                                Row {
                                                    width: parent.width
                                                    spacing: Kirigami.Units.smallSpacing

                                                    PC3.ToolButton {
                                                        visible: root.editingMessageIndex !== index && modelData.role !== "error"
                                                        enabled: root.currentStreamIndex !== index
                                                        icon.name: "document-edit"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.text: modelData.role === "queued" ? "Edit queued message" : "Edit message"
                                                        onClicked: {
                                                            root.editingMessageIndex = index;
                                                            root.editingDraft = modelData.content;
                                                        }
                                                    }

                                                    PC3.ToolButton {
                                                        visible: root.editingMessageIndex === index && modelData.role !== "error"
                                                        icon.name: "dialog-ok-apply"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.text: "Apply edit"
                                                        onClicked: root.saveEditedMessage()
                                                    }

                                                    PC3.ToolButton {
                                                        visible: root.editingMessageIndex === index && modelData.role !== "error"
                                                        icon.name: "dialog-cancel"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.text: "Cancel edit"
                                                        onClicked: {
                                                            root.editingMessageIndex = -1;
                                                            root.editingDraft = "";
                                                        }
                                                    }

                                                    PC3.ToolButton {
                                                        visible: plasmoid.configuration.voiceEnabled && plasmoid.configuration.voiceTtsEnabled && modelData.role !== "error"
                                                        enabled: root.currentStreamIndex !== index
                                                        icon.name: (root.voiceManagerRef && root.voiceManagerRef.isPlaying && repRoot.playingMessageIndex === index) ? "media-playback-stop" : "audio-speakers"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.text: (root.voiceManagerRef && root.voiceManagerRef.isPlaying && repRoot.playingMessageIndex === index) ? "Stop speaking" : ((msgTextLabel.selectedText && msgTextLabel.selectedText.trim().length > 0) ? "Read selected text" : "Read aloud")
                                                        onClicked: {
                                                            if (root.voiceManagerRef) {
                                                                let isPlayingThis = root.voiceManagerRef.isPlaying && repRoot.playingMessageIndex === index;
                                                                if (isPlayingThis) {
                                                                    root.voiceManagerRef.stopTTS();
                                                                    repRoot.playingMessageIndex = -1;
                                                                } else {
                                                                    if (root.voiceManagerRef.isPlaying) {
                                                                        root.voiceManagerRef.stopTTS();
                                                                    }
                                                                    let textToPlay = (msgTextLabel.selectedText && msgTextLabel.selectedText.trim().length > 0) ? msgTextLabel.selectedText : modelData.content;
                                                                    repRoot.playingMessageIndex = index;
                                                                    root.voiceManagerRef.playTTS(textToPlay);
                                                                }
                                                            }
                                                        }
                                                    }

                                                    PC3.ToolButton {
                                                        visible: true
                                                        enabled: root.currentStreamIndex !== index
                                                        icon.name: "edit-copy"
                                                        display: PC3.AbstractButton.IconOnly
                                                        QQC2.ToolTip.visible: hovered
                                                        QQC2.ToolTip.text: "Copy message"
                                                        onClicked: {
                                                            root.copyTextToClipboard(modelData.content);
                                                        }
                                                    }

                                                    PC3.ToolButton {
                                                        visible: true
                                                        enabled: root.currentStreamIndex !== index
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
                                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.14)
                                    }

                                }

                            }

                        }

                    }

                    RowLayout {
                        visible: root.loading

                        PC3.BusyIndicator {
                            running: root.loading
                            width: 20
                            height: 20
                        }

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
                                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                                    border.width: 1
                                    border.color: modelData.error !== "" ? Kirigami.Theme.negativeTextColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
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

                        QQC2.TextArea {
                            id: msgInput

                            // Dual-stage focus mechanism for Plasma 6
                            property alias focusTimerRef: focusTimer

                            Layout.fillWidth: true
                            Layout.minimumHeight: Kirigami.Units.gridUnit * 3
                            Layout.maximumHeight: Kirigami.Units.gridUnit * 7
                            Layout.preferredHeight: Math.min(Layout.maximumHeight, Math.max(Layout.minimumHeight, contentHeight + topPadding + bottomPadding))
                            wrapMode: Text.WordWrap
                            clip: true
                            enabled: !root.loading
                            placeholderText: "Type message (Enter sends, Shift+Enter newline)"
                            focus: true
                            
                            background: Rectangle {
                                color: Kirigami.Theme.backgroundColor
                                radius: 4
                                border.width: 1
                                border.color: msgInput.activeFocus ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
                            }
                            color: Kirigami.Theme.textColor
                            
                            onActiveFocusChanged: {
                                if (activeFocus)
                                    root.ensureWalletLoaded();

                            }
                            // Sync to root property so root-scope functions can read/clear it
                            onTextChanged: root.chatInputText = text
                            Keys.onPressed: function(event) {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                    event.accepted = true;
                                    root.sendMessage();
                                } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                                    root.checkClipboardForAttachments();
                                    event.accepted = false;
                                }
                            }
                            Component.onCompleted: {
                                if (root.expanded)
                                    focusTimer.start();

                            }

                            Timer {
                                id: focusTimer

                                interval: 120
                                repeat: false
                                onTriggered: {
                                    if (msgInput.enabled && msgInput.visible)
                                        msgInput.forceActiveFocus();

                                }
                            }

                            Connections {
                                function onExpandedChanged() {
                                    if (root.expanded)
                                        focusTimer.start();

                                }

                                target: root
                            }

                        }



                        PC3.ToolButton {
                            visible: plasmoid.configuration.voiceEnabled
                            icon.name: (root.voiceManagerRef && root.voiceManagerRef.isRecording) ? "media-playback-stop" : "audio-input-microphone"
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: (root.voiceManagerRef && root.voiceManagerRef.isRecording) ? "Stop Recording" : "Record Voice (STT)"
                            onClicked: {
                                if (root.voiceManagerRef) {
                                    if (root.voiceManagerRef.isRecording) {
                                        root.voiceManagerRef.stopRecording();
                                    } else {
                                        root.voiceManagerRef.startRecording();
                                    }
                                }
                            }
                        }

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
                                root.checkClipboardForAttachments();
                                var txt = root.readClipboardText();
                                if (txt && txt.trim() !== "") {
                                    var curPos = msgInput.cursorPosition;
                                    msgInput.insert(curPos, txt);
                                }
                            }
                        }

                        QQC2.Button {
                            icon.name: root.loading ? "list-add" : "document-send"
                            text: root.loading ? "Queue" : "Send"
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 5
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            enabled: root.chatInputText.trim() !== "" || root.attachedFiles.length > 0
                            highlighted: true
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

            Loader {
                id: historyLoader

                Layout.fillWidth: true
                Layout.fillHeight: true
                active: root.historyOnlyMode
                visible: status === Loader.Ready

                sourceComponent: Component {
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

                            QQC2.ScrollBar.vertical: QQC2.ScrollBar {
                            }

                            delegate: Rectangle {
                                required property var modelData

                                width: historyList.width
                                height: historyCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                                radius: 8
                                opacity: modelData.archived ? 0.72 : 1
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
                                            color: Qt.rgba(0.2, 0.48, 0.92, 0.18)

                                            PC3.Label {
                                                id: modeBadgeText

                                                anchors.centerIn: parent
                                                text: "OC"
                                                font.bold: true
                                                color: Qt.rgba(0.12, 0.35, 0.78, 1)
                                            }

                                        }

                                        QQC2.TextField {
                                            visible: root.editingSessionId === modelData.value
                                            width: parent.width - saveRename.width - archiveChat.width - removeChat.width - (modeBadge.visible ? modeBadge.width + Kirigami.Units.smallSpacing / 2 : 0) - Kirigami.Units.smallSpacing * 3
                                            text: root.editingSessionDraft
                                            color: Kirigami.Theme.textColor
                                            background: Rectangle {
                                                color: Kirigami.Theme.backgroundColor
                                                radius: Kirigami.Units.smallSpacing
                                                border.color: parent.activeFocus ? Kirigami.Theme.highlightColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.3)
                                                border.width: 1
                                            }
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
                                                    root.switchSession(modelData.value);
                                                    root.historyOnlyMode = false;
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
                                                    root.saveSessionRename(modelData.value);
                                                else
                                                    root.startSessionRename(modelData.value);
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
                                                    root.cancelSessionRename();
                                                else
                                                    root.deleteSession(modelData.value);
                                            }
                                        }

                                    }

                                    PC3.Label {
                                        opacity: root.popupIsDark ? 1 : 0.7
                                        color: root.popupIsDark ? "#ffffff" : Kirigami.Theme.textColor
                                        text: root.sessionSubtitle(modelData)
                                    }

                                }

                            }

                        }

                    }

                }

            }

        }

    }

    MouseArea {
        property real startX: 0
        property real startY: 0
        property real startW: 0
        property real startH: 0

        anchors.right: parent.right
        anchors.bottom: parent.bottom
        width: Kirigami.Units.gridUnit
        height: Kirigami.Units.gridUnit
        cursorShape: Qt.SizeFDiagCursor
        onPressed: function(mouse) {
            startX = mouse.x;
            startY = mouse.y;
            startW = parent.implicitWidth;
            startH = parent.implicitHeight;
        }
        onPositionChanged: function(mouse) {
            if (pressed) {
                var dx = mouse.x - startX;
                var dy = mouse.y - startY;
                var newW = Math.max(500, startW + dx);
                var newH = Math.max(620, startH + dy);
                parent.implicitWidth = newW;
                parent.implicitHeight = newH;
                plasmoid.configuration.customPopupWidth = newW;
                plasmoid.configuration.customPopupHeight = newH;
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
