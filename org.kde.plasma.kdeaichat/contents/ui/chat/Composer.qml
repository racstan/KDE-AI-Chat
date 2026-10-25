// Everything under the message list: the status row (thinking/streaming,
// voice), files waiting to be sent, and the input with its buttons.
//
// The widget reaches the input only through this component: it registers
// itself as chat.composerRef, and chat.focusInput() calls focusInput() here.
//
// Keys in the input: Enter sends, Shift+Enter adds a line, "/" at the start
// suggests prompt templates. While the input is empty, Up/Down browse the
// messages (ChatView.qml); PageUp/PageDown jump to the first/latest message,
// also with text unless the input itself scrolls. Ctrl+E (ChatShortcuts.qml)
// edits your last message.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "PromptTemplates.js" as PromptTemplates
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: composer

    property var chat: null
    readonly property alias input: msgInput
    readonly property alias suggestions: suggestions

    readonly property alias bar: bar

    signal attachRequested()
    signal chatInfoRequested()

    // Starts editing the last message you wrote (Ctrl+E), if
    // there is one and no reply is being written. Returns whether it did.
    function editLastMessage() {
        if (composer.chat.loading)
            return false;
        var messages = composer.chat.messages || [];
        for (var i = messages.length - 1; i >= 0; i--) {
            var role = messages[i].role;
            if (role === "user" || role === "queued") {
                composer.chat.editingMessageIndex = i;
                composer.chat.editingDraft = messages[i].content || "";
                if (composer.chat.msgListViewRef)
                    composer.chat.msgListViewRef.positionViewAtIndex(i, ListView.Contain);
                return true;
            }
        }
        return false;
    }

    // Focus now and again shortly after: in a Plasma popup the window may
    // not be active yet when this is first called.
    function focusInput() {
        if (msgInput.enabled && msgInput.visible)
            msgInput.forceActiveFocus();
        focusTimer.start();
    }

    // A character typed while a message was selected: back into the input.
    function typeText(text) {
        msgInput.forceActiveFocus();
        msgInput.insert(msgInput.cursorPosition, text);
    }

    // Up/Down/PageUp/PageDown for browsing the messages; true if used.
    function browseKey(event) {
        var list = composer.chat.msgListViewRef;
        if (!list || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier)))
            return false;
        var empty = msgInput.text === "";
        if (event.key === Qt.Key_Up && empty)
            return list.browse(-1);
        if (event.key === Qt.Key_Down && empty)
            return list.browse(1);
        // With text, PageUp/PageDown keep scrolling the input when it overflows.
        var scrolls = !empty && msgInput.contentHeight > msgInput.height - msgInput.topPadding - msgInput.bottomPadding;
        if (event.key === Qt.Key_PageUp && !scrolls)
            return list.jumpFirst();
        if (event.key === Qt.Key_PageDown && !scrolls)
            return list.jumpLatest();
        return false;
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

    // What the chat talks to (click to change the model), then what it is doing.
    ComposerBar {
        id: bar
        chat: composer.chat
        onChatInfoRequested: composer.chatInfoRequested()
    }

    ComposerStatus {
        chat: composer.chat
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
                            Accessible.name: i18n("Remove %1", fileChip.modelData.name)
                            QQC2.ToolTip.visible: hovered
                            QQC2.ToolTip.text: i18n("Remove file")
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
            placeholderText: i18n("Message")
            Accessible.name: i18n("Message")
            focus: true

            onActiveFocusChanged: {
                if (activeFocus) {
                    composer.chat.ensureWalletLoaded();
                    if (composer.chat.msgListViewRef && composer.chat.msgListViewRef.clearSelection)
                        composer.chat.msgListViewRef.clearSelection();
                }
            }
            // Mirrored into chat.chatInputText so the widget's functions can read/clear it
            onTextChanged: composer.chat.chatInputText = text
            Keys.onPressed: function(event) {
                if (suggestions.active && suggestions.handleKey(event.key)) {
                    event.accepted = true;
                } else if (composer.browseKey(event)) {
                    event.accepted = true;
                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
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

            TemplateSuggestions {
                id: suggestions
                objectName: "templateSuggestions"
                templates: PromptTemplates.suggest(msgInput.text, composer.chat.promptTemplates || [])
                onChosen: (template) => {
                    msgInput.text = "/" + template.name + " ";
                    msgInput.cursorPosition = msgInput.length;
                }

                // Arrow keys move, Enter/Tab picks, Esc hides (until the text changes).
                function handleKey(key) {
                    if (key === Qt.Key_Down)
                        next();
                    else if (key === Qt.Key_Up)
                        previous();
                    else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Tab)
                        accept();
                    else if (key === Qt.Key_Escape)
                        dismissed = true;
                    else
                        return false;
                    return true;
                }
            }

            Connections {
                target: msgInput
                function onTextChanged() {
                    suggestions.dismissed = false;
                }
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
                Accessible.name: (voice && voice.isRecording) ? i18n("Stop recording") : i18n("Record voice")
                QQC2.ToolTip.visible: hovered
                QQC2.ToolTip.text: (voice && voice.isRecording) ? i18n("Stop recording") : i18n("Record voice (beta speech-to-text)")
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
            Accessible.name: i18n("Attach files")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Attach files (images, PDF, CSV, Word documents)")
            onClicked: composer.attachRequested()
        }

        PC3.ToolButton {
            icon.name: "edit-paste"
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
            Layout.preferredWidth: Kirigami.Units.gridUnit * 1.5
            enabled: true
            Accessible.name: i18n("Paste from clipboard")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Paste file or text from clipboard")
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
            text: composer.chat.loading ? i18n("Queue") : i18n("Send")
            Layout.minimumWidth: Kirigami.Units.gridUnit * 5
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
            enabled: composer.chat.attachmentsReadyToSend() && (composer.chat.chatInputText.trim() !== "" || composer.chat.attachedFiles.length > 0)
            highlighted: true
            Accessible.name: text
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: composer.chat.loading ? i18n("Send this after the current reply finishes") : i18n("Send message")
            onClicked: composer.chat.sendMessage()
        }

        PC3.Button {
            objectName: "stopButton"
            visible: composer.chat.loading
            icon.name: "media-playback-stop"
            text: i18n("Stop")
            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
            Accessible.name: i18n("Stop the reply")
            QQC2.ToolTip.visible: hovered
            QQC2.ToolTip.text: i18n("Stop the reply (Esc)")
            onClicked: composer.chat.stopStreaming()
        }
    }
}
