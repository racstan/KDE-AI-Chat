// Everything under the message list: the status row (thinking/streaming,
// voice), files waiting to be sent, and the input with its buttons.
//
// The widget reaches the input only through this component: it registers
// itself as chat.composerRef, and chat.focusInput() calls focusInput() here.
//
// Messages quoted with the Quote button show as chips above the box (QuoteChips.qml).
//
// Keys in the input: Enter sends, Shift+Enter adds a line (or, with "Send
// with Ctrl+Enter" in Settings → Chat, Ctrl+Enter sends and Enter adds a line), "/" at the start
// lists the slash commands (Commands.js, run by CommandRunner.qml) and then the
// prompt templates; Enter on a command runs it instead of sending. While the input is empty, Up/Down browse the
// messages (ChatView.qml); PageUp/PageDown jump to the first/latest message,
// also with text unless the input itself scrolls. Ctrl+E (ChatShortcuts.qml)
// edits your last message.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "Commands.js" as Commands
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

ColumnLayout {
    id: composer

    property var chat: null
    // The look and behaviour options (chat/ChatPrefs.qml), or null.
    readonly property var prefs: chat && chat.prefs ? chat.prefs : null
    readonly property alias input: msgInput
    readonly property alias suggestions: suggestions
    readonly property alias quoteChips: quoteChips

    // focusInput() focuses again shortly after; tests wait for that to pass.
    readonly property bool refocusPending: focusTimer.running

    // The quick model picker, opened by /model and /variant (CommandRunner.qml).
    readonly property alias picker: modelPicker

    signal attachRequested()
    signal chatInfoRequested()

    // Quotes `message` for the next message: a chip above the box, focus in the box.
    function addQuote(message) {
        quoteChips.add(message);
        focusInput();
    }

    // The quotes for the message being sent (chips cleared); [{id, role, text}].
    function takeQuotes() {
        return quoteChips.take();
    }

    // A chat's settings were saved (ChatSettingsDraft.save): the status line may
    // say that the provider's cache starts over (CommandRunner.noteModelSwitch).
    function noteModelSwitch(sessionId, before, after) {
        runner.noteModelSwitch(sessionId, before, after);
    }

    // A short note in the status line from outside the composer (a budget alert, chat/SpendingLog.qml).
    // Typing clears it, as with the other notes.
    function showNotice(text) {
        runner.show(text);
    }

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

    ComposerStatus {
        chat: composer.chat
        notice: runner.notice
    }

    // Messages quoted for the next message (Quote button, Ctrl+Q).
    QuoteChips {
        id: quoteChips
        chat: composer.chat
    }

    CommandRunner {
        id: runner
        chat: composer.chat
        picker: modelPicker
        input: msgInput
    }

    // Files waiting to be sent
    PendingFiles {
        chat: composer.chat
    }

    RowLayout {
        id: inputRow

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        // Opens above the message box.
        ComposerPicker {
            id: modelPicker
            chat: composer.chat
            onChatInfoRequested: composer.chatInfoRequested()
        }

        PC3.TextArea {
            // Tab and Shift+Tab leave the box (they never type a tab).
            // Tab picks the highlighted template; otherwise Tab and Shift+Tab leave the box (they never type a tab).
            Keys.onTabPressed: function(event) {
                if (!(suggestions.active && suggestions.handleKey(Qt.Key_Tab)))
                    nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason);
                event.accepted = true;
            }
            Keys.onBacktabPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.BacktabFocusReason)
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
            onTextChanged: {
                composer.chat.chatInputText = text;
                runner.track(text);
            }
            Keys.onPressed: function(event) {
                if (suggestions.active && suggestions.handleKey(event.key)) {
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape && composer.chat.voiceManagerRef && composer.chat.voiceManagerRef.isRecording) {
                    composer.chat.voiceManagerRef.cancelRecording();
                    event.accepted = true;
                } else if (composer.browseKey(event)) {
                    event.accepted = true;
                } else if (composer.prefs ? composer.prefs.sendsMessage(event)
                           : (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                    event.accepted = true;
                    if (!runner.run(msgInput.text))
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
            // The text size from Settings → Appearance; the theme's font otherwise.
            Binding on font {
                when: !!composer.prefs && composer.prefs.fontFactor !== 1
                value: composer.prefs ? composer.prefs.scaledFont(Kirigami.Theme.defaultFont) : Kirigami.Theme.defaultFont
            }

            TemplateSuggestions {
                id: suggestions
                objectName: "templateSuggestions"
                entries: Commands.suggest(msgInput.text, composer.chat.promptTemplates || [], runner.context)
                onChosen: (entry) => runner.complete(entry)
                onActivated: (entry) => runner.activate(entry, msgInput.text)
            }

            Connections {
                target: msgInput
                function onTextChanged() {
                    suggestions.dismissed = false;
                }
            }
        }

        Item {
            visible: composer.chat.sttEnabled
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
            onClicked: {
                if (!runner.run(msgInput.text))
                    composer.chat.sendMessage();
            }
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
