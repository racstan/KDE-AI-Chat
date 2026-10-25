import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support 2.0 as P5Support
import org.kde.plasma.plasmoid
import "ProviderService.js" as ProviderService
import "Security.js" as Sec
import "chat" as Chat

Item {
    id: repRoot
    anchors.fill: parent

    Kirigami.Theme.inherit: false
    Kirigami.Theme.backgroundColor: root.popupIsDark ? "#121212" : "#ffffff"
    Kirigami.Theme.alternateBackgroundColor: root.popupIsDark ? "#1a1a1a" : "#f5f7fa"
    Kirigami.Theme.textColor: root.popupIsDark ? "#f7fafc" : "#1a202c"
    Kirigami.Theme.highlightColor: "#3182ce"

    Connections {
        target: root.voiceManagerRef || null
        function onIsPlayingChanged() {
            if (root.voiceManagerRef && !root.voiceManagerRef.isPlaying) {
                root.playingMessageIndex = -1;
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
        id: mainContentColumn
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        anchors.rightMargin: chatSettingsDialog.visible ? chatSettingsDialog.width + Kirigami.Units.smallSpacing : Kirigami.Units.smallSpacing
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
                icon.name: "preferences-other"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Open chat controls sidebar"
                onClicked: chatSettingsDialog.toggleForSession(root.currentSessionId)
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
                    root.scrollToBottom(true);
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

        Chat.NoticeBanner {
            isError: true
            text: root.sessionHistoryLoadError
            actionText: "Replace stored history"
            actionIcon: "edit-clear-all"
            onActionTriggered: root.resetUnreadableSessionHistory()
        }

        Chat.NoticeBanner {
            text: root.privacyNotice
            onDismissed: root.privacyNotice = ""
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !root.historyOnlyMode && root.openCodeMode
            spacing: Kirigami.Units.smallSpacing

            Component.onCompleted: {
                if (root.openCodeMode && root.openCodeAgentsList.length === 0)
                    root.fetchOpenCodeAgents();
            }
            onVisibleChanged: {
                if (visible && root.openCodeAgentsList.length === 0)
                    root.fetchOpenCodeAgents();
            }

            PC3.ToolButton {
                icon.name: "folder"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: root.openCodeWorkspaceCwd ? ("Workspace: " + root.openCodeWorkspaceCwd) : "Select OpenCode Workspace Directory"
                onClicked: workspaceFolderDialog.open()
            }

            PC3.Label {
                text: {
                    var folder = "";
                    if (root.openCodeWorkspaceCwd) {
                        var p = root.openCodeWorkspaceCwd;
                        folder = p.substring(p.lastIndexOf("/") + 1) || p;
                    }
                    var sess = root.currentOpenCodeSessionId();
                    var labelStr = folder ? ("📁 " + folder) : "📁 Workspace";
                    if (sess) labelStr += " (" + sess.substring(0, 10) + "…)";
                    return labelStr;
                }
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                font.bold: true
                opacity: 0.85
                elide: Text.ElideMiddle
                Layout.maximumWidth: parent.width - 260
            }

            Item {
                Layout.fillWidth: true
            }

            QQC2.ComboBox {
                id: agentSelectorCombo
                implicitWidth: Kirigami.Units.gridUnit * 7
                implicitHeight: Kirigami.Units.gridUnit * 1.8
                // The list is populated from OpenCode's API/configuration.
                // Never invent agent names locally: an empty list means that
                // OpenCode has not reported any agents yet.
                model: root.openCodeAgentsList
                textRole: "text"
                valueRole: "value"
                enabled: model.length > 0
                currentIndex: {
                    var cur = root.openCodeAgent || "";
                    for (var i = 0; i < model.length; i++) {
                        if (model[i].value === cur) return i;
                    }
                    return 0;
                }
                onActivated: {
                    if (!model[currentIndex]) return;
                    var val = model[currentIndex].value;
                    root.openCodeAgent = val;
                    plasmoid.configuration.openCodeAgent = val;
                }
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Agent profile — uses model from opencode.json\nCurrently: " + (root.openCodeAgent || "(default)")
            }

            PC3.ToolButton {
                icon.name: "view-list-details"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: "Refresh agent list from opencode.json"
                onClicked: root.fetchOpenCodeAgents()
            }

            PC3.ToolButton {
                icon.name: "view-refresh"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: i18n("Sync session history from OpenCode")
                enabled: !root.loading && root.currentOpenCodeSessionId() !== ""
                onClicked: root.syncOpenCodeSessionHistory()
            }
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

                        Chat.ChatView {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            visible: !root.historyOnlyMode
                            chat: root
                        }
                    }

                    RowLayout {
                        visible: root.loading || (!!root.voiceManagerRef && root.voiceManagerRef.statusText !== "")
                        spacing: Kirigami.Units.smallSpacing

                        PC3.BusyIndicator {
                            running: root.loading || (!!root.voiceManagerRef && root.voiceManagerRef.statusText !== "" && root.voiceManagerRef.statusText !== "Reading aloud..." && root.voiceManagerRef.statusText !== "Paused" && !root.voiceManagerRef.callModeActive)
                            visible: running
                            width: 16
                            height: 16
                        }

                        PC3.ToolButton {
                            icon.name: (root.voiceManagerRef && root.voiceManagerRef.callModeActive) ? "call-start" : "media-playback-stop"
                            visible: !root.loading && !!root.voiceManagerRef && (root.voiceManagerRef.statusText === "Reading aloud..." || root.voiceManagerRef.statusText === "Generating speech..." || root.voiceManagerRef.callModeActive === true)
                            display: PC3.AbstractButton.IconOnly
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: (root.voiceManagerRef && root.voiceManagerRef.callModeActive) ? "Call Mode Active" : "Stop reading"
                            onClicked: {
                                if (root.voiceManagerRef) {
                                    if (root.voiceManagerRef.callModeActive) {
                                        root.voiceManagerRef.stopCallMode();
                                    } else {
                                        root.voiceManagerRef.stopTTS();
                                    }
                                }
                                root.playingMessageIndex = -1;
                            }
                        }

                        PC3.Label {
                            text: {
                                if (root.loading) {
                                    return root.streamingResponse ? "Streaming response..." : "Thinking...";
                                } else if (root.voiceManagerRef && root.voiceManagerRef.statusText) {
                                    return root.voiceManagerRef.statusText;
                                }
                                return "";
                            }
                            opacity: 0.8
                            font.italic: true
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
                                                source: modelData.content ? ("data:" + (modelData.mimeType || "image/png") + ";base64," + modelData.content) : ("file://" + modelData.path)
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
                            enabled: true
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
                                msgInput.text = root.chatInputText;
                            }

                            Connections {
                                target: root
                                function onChatInputTextChanged() {
                                    if (msgInput.text !== root.chatInputText) {
                                        msgInput.text = root.chatInputText;
                                    }
                                }
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



                        Item {
                            visible: root.voiceEnabled
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5

                            PC3.ToolButton {
                                id: recordButton
                                anchors.fill: parent
                                icon.name: (root.voiceManagerRef && root.voiceManagerRef.isRecording) ? "media-playback-stop" : "audio-input-microphone"
                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: (root.voiceManagerRef && root.voiceManagerRef.isRecording) ? "Stop Recording" : "Record Voice (Beta STT)"
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

                            PC3.BusyIndicator {
                                anchors.centerIn: parent
                                width: parent.width * 0.6
                                height: parent.height * 0.6
                                running: !!root.voiceManagerRef && (root.voiceManagerRef.statusText.indexOf("Loading") !== -1 || root.voiceManagerRef.statusText.indexOf("Transcribing") !== -1 || root.voiceManagerRef.statusText.indexOf("Processing") !== -1)
                                visible: running
                            }
                        }


                        PC3.ToolButton {
                            icon.name: "camera-photo-symbolic"
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                            enabled: true
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: "Capture screen region (Spectacle)"
                            onClicked: root.captureScreenRegion()
                        }

                        PC3.ToolButton {
                            icon.name: "mail-attachment"
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                            enabled: true
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: "Attach files (Images, PDF, CSV, Word documents)"
                            onClicked: fileDialog.open()
                        }

                        PC3.ToolButton {
                            icon.name: "edit-paste"
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
                            enabled: true
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
                            text: root.loading ? "+ Queue" : "Send"
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 5
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            enabled: root.attachmentsReadyToSend() && (root.chatInputText.trim() !== "" || root.attachedFiles.length > 0)
                            highlighted: true
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: root.loading ? "Queue message to send after current response finishes" : "Send message"
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

    } // MouseArea

    ChatSettingsDialog {
        id: chatSettingsDialog
        rootRef: root
        hostItem: repRoot
    }
}
