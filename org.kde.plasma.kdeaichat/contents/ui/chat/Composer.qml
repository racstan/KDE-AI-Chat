// Everything under the message list: the status row (thinking/streaming,
// voice), files waiting to be sent, and the input with its buttons.
//
// The widget reaches the input only through this component: it registers
// itself as chat.composerRef, and chat.focusInput() calls focusInput() here.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

ColumnLayout {
    id: composer

    property var chat: null
    readonly property alias input: msgInput

    signal attachRequested()

    // Focus now and again shortly after: in a Plasma popup the window may
    // not be active yet when this is first called.
    function focusInput() {
        if (msgInput.enabled && msgInput.visible)
            msgInput.forceActiveFocus();
        focusTimer.start();
    }

    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing

    Component.onCompleted: composer.chat.composerRef = composer
    Component.onDestruction: {
        if (composer.chat && composer.chat.composerRef === composer)
            composer.chat.composerRef = null;
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
        target: composer.chat
        function onClearChatInput() {
            msgInput.text = "";
        }
        function onChatInputTextChanged() {
            if (msgInput.text !== composer.chat.chatInputText)
                msgInput.text = composer.chat.chatInputText;
        }
        function onExpandedChanged() {
            if (composer.chat.expanded)
                focusTimer.start();
        }
    }

    RowLayout {
        readonly property var voice: composer.chat.voiceManagerRef

        visible: composer.chat.loading || (!!voice && voice.statusText !== "")
        spacing: Kirigami.Units.smallSpacing

        PC3.BusyIndicator {
            readonly property var voice: composer.chat.voiceManagerRef
            running: composer.chat.loading || (!!voice && voice.statusText !== "" && voice.statusText !== "Reading aloud..." && voice.statusText !== "Paused" && !voice.callModeActive)
            visible: running
            width: Kirigami.Units.iconSizes.small
            height: Kirigami.Units.iconSizes.small
        }

        PC3.ToolButton {
            readonly property var voice: composer.chat.voiceManagerRef
            icon.name: (voice && voice.callModeActive) ? "call-start" : "media-playback-stop"
            visible: !composer.chat.loading && !!voice && (voice.statusText === "Reading aloud..." || voice.statusText === "Generating speech..." || voice.callModeActive === true)
            display: PC3.AbstractButton.IconOnly
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: (voice && voice.callModeActive) ? "Call Mode Active" : "Stop reading"
            onClicked: {
                if (voice) {
                    if (voice.callModeActive)
                        voice.stopCallMode();
                    else
                        voice.stopTTS();
                }
                composer.chat.playingMessageIndex = -1;
            }
        }

        PC3.Label {
            text: {
                var voice = composer.chat.voiceManagerRef;
                if (composer.chat.loading)
                    return composer.chat.streamingResponse ? "Streaming response..." : "Thinking...";
                else if (voice && voice.statusText)
                    return voice.statusText;
                return "";
            }
            opacity: 0.8
            font.italic: true
        }
    }

    // Files waiting to be sent
    QQC2.ScrollView {
        Layout.fillWidth: true
        visible: composer.chat.attachedFiles.length > 0
        height: Kirigami.Units.gridUnit * 2
        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff
        QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AlwaysOff

        Row {
            spacing: Kirigami.Units.smallSpacing
            padding: Kirigami.Units.smallSpacing

            Repeater {
                model: composer.chat.attachedFiles

                delegate: Rectangle {
                    id: fileChip

                    required property var modelData
                    required property int index

                    width: Math.min(Kirigami.Units.gridUnit * 10, filenameLabel.implicitWidth + Kirigami.Units.iconSizes.smallMedium * 2 + Kirigami.Units.smallSpacing * 4)
                    height: Kirigami.Units.gridUnit * 1.5
                    radius: Kirigami.Units.cornerRadius
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08)
                    border.width: 1
                    border.color: modelData.error !== "" ? Kirigami.Theme.negativeTextColor : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
                    QQC2.ToolTip.visible: fileMouseArea.containsMouse && modelData.error !== ""
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
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small

                            PC3.BusyIndicator {
                                anchors.centerIn: parent
                                visible: fileChip.modelData.loading
                                running: fileChip.modelData.loading
                                width: Kirigami.Units.iconSizes.small
                                height: Kirigami.Units.iconSizes.small
                            }

                            Image {
                                anchors.fill: parent
                                visible: !fileChip.modelData.loading && fileChip.modelData.type === "image"
                                source: fileChip.modelData.content ? ("data:" + (fileChip.modelData.mimeType || "image/png") + ";base64," + fileChip.modelData.content) : ("file://" + fileChip.modelData.path)
                                fillMode: Image.PreserveAspectCrop
                                clip: true
                            }

                            Kirigami.Icon {
                                anchors.fill: parent
                                visible: !fileChip.modelData.loading && fileChip.modelData.type !== "image"
                                source: composer.chat.fileIconName(fileChip.modelData.name)
                            }
                        }

                        PC3.Label {
                            id: filenameLabel

                            Layout.fillWidth: true
                            text: fileChip.modelData.name
                            elide: Text.ElideRight
                            font: Kirigami.Theme.smallFont
                        }

                        PC3.ToolButton {
                            icon.name: "dialog-close"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            display: PC3.AbstractButton.IconOnly
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: "Remove file"
                            onClicked: composer.chat.removeAttachedFile(fileChip.index)
                        }
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PC3.TextArea {
            id: msgInput

            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 3
            Layout.maximumHeight: Kirigami.Units.gridUnit * 7
            Layout.preferredHeight: Math.min(Layout.maximumHeight, Math.max(Layout.minimumHeight, contentHeight + topPadding + bottomPadding))
            wrapMode: Text.WordWrap
            clip: true
            enabled: true
            placeholderText: "Type message (Enter sends, Shift+Enter newline)"
            focus: true

            onActiveFocusChanged: {
                if (activeFocus)
                    composer.chat.ensureWalletLoaded();
            }
            // Mirrored into chat.chatInputText so the widget's functions can read/clear it
            onTextChanged: composer.chat.chatInputText = text
            Keys.onPressed: function(event) {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                    event.accepted = true;
                    composer.chat.sendMessage();
                } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                    composer.chat.checkClipboardForAttachments();
                    event.accepted = false;
                }
            }
            Component.onCompleted: {
                if (composer.chat.expanded)
                    focusTimer.start();
                msgInput.text = composer.chat.chatInputText;
            }
        }

        Item {
            visible: composer.chat.voiceEnabled
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5

            PC3.ToolButton {
                id: recordButton
                readonly property var voice: composer.chat.voiceManagerRef
                anchors.fill: parent
                icon.name: (voice && voice.isRecording) ? "media-playback-stop" : "audio-input-microphone"
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: (voice && voice.isRecording) ? "Stop Recording" : "Record Voice (Beta STT)"
                onClicked: {
                    if (voice) {
                        if (voice.isRecording)
                            voice.stopRecording();
                        else
                            voice.startRecording();
                    }
                }
            }

            PC3.BusyIndicator {
                readonly property var voice: composer.chat.voiceManagerRef
                anchors.centerIn: parent
                width: parent.width * 0.6
                height: parent.height * 0.6
                running: !!voice && (voice.statusText.indexOf("Loading") !== -1 || voice.statusText.indexOf("Transcribing") !== -1 || voice.statusText.indexOf("Processing") !== -1)
                visible: running
            }
        }

        PC3.ToolButton {
            icon.name: "mail-attachment"
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
            enabled: true
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: "Attach files (Images, PDF, CSV, Word documents)"
            onClicked: composer.attachRequested()
        }

        PC3.ToolButton {
            icon.name: "edit-paste"
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
            enabled: true
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: "Paste file or text from clipboard"
            onClicked: {
                composer.chat.checkClipboardForAttachments();
                var txt = composer.chat.readClipboardText();
                if (txt && txt.trim() !== "")
                    msgInput.insert(msgInput.cursorPosition, txt);
            }
        }

        QQC2.Button {
            id: sendButton
            objectName: "sendButton"
            icon.name: composer.chat.loading ? "list-add" : "document-send"
            text: composer.chat.loading ? "+ Queue" : "Send"
            Layout.minimumWidth: Kirigami.Units.gridUnit * 5
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
            enabled: composer.chat.attachmentsReadyToSend() && (composer.chat.chatInputText.trim() !== "" || composer.chat.attachedFiles.length > 0)
            highlighted: true
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: composer.chat.loading ? "Queue message to send after current response finishes" : "Send message"
            onClicked: composer.chat.sendMessage()
        }

        PC3.ToolButton {
            visible: composer.chat.loading
            icon.name: "process-stop"
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: "Stop current response"
            onClicked: composer.chat.stopStreaming()
        }
    }
}
