// Keyboard shortcuts for the chat popup, and the Undo notice that floats
// above the composer (so it shows whichever page is open).
//
// The list (keys and labels) is in ShortcutList.js, also shown in
// Settings → Appearance. Popup only (Qt.WindowShortcut). None of them is a
// text-editing key, so the input keeps Ctrl+C/V/X/Z/A and Ctrl+arrows.
//
//   Ctrl+N          new chat
//   Ctrl+Shift+N    new incognito chat (chat/Incognito.qml)
//   Ctrl+Shift+F    search all chats (searchRequested: the history opens with its search field)
//   Ctrl+H          show or hide the history
//   Ctrl+I          show or hide the chat info panel (chatInfoRequested)
//   Ctrl+L          focus the input
//   Esc             stop the reply that is being written; cancel an edit
//   Ctrl+Shift+R    regenerate the last reply
//   Ctrl+Shift+C    copy the last reply
//   Ctrl+PgDown/Up  next / previous chat
//   Ctrl+,          open the settings
//   Ctrl+E          edit your last message
//   Ctrl+Shift+S    read aloud the selection / picked message; stop reading
//   Up / Down       browse the messages (input empty, or the chat clicked)
//   PgUp / PgDown   first / latest message
//
// Up/Down/PgUp/PgDown (browsing; ChatView.qml and Composer.qml, which read
// the keys from the list below), Esc on a selected message and "/"
// (templates) are keys of the list or the input itself.
//
// Fills its parent and takes no mouse input; put it once in the popup.
import QtQuick
import org.kde.kirigami as Kirigami
import "ShortcutList.js" as ShortcutList
import "ReadAloudAction.js" as ReadAloudAction

Item {
    id: shortcuts

    property var chat: null
    readonly property alias undoNotice: undo
    // Ctrl+I: the popup owns the info panel, so it listens to this.
    signal chatInfoRequested()
    // Ctrl+Shift+F: the popup opens the history and focuses its search field.
    signal searchRequested()

    function _browsing() {
        var list = shortcuts.chat ? shortcuts.chat.msgListViewRef : null;
        return !!list && list.selectedIndex >= 0;
    }
    function _lastReply() {
        return shortcuts.chat ? ShortcutList.lastReplyIndex(shortcuts.chat.messages) : -1;
    }
    function _goToChat(delta) {
        var id = ShortcutList.neighbourSessionId(shortcuts.chat.sessions, shortcuts.chat.currentSessionId, delta);
        if (id !== "")
            shortcuts.chat.switchSession(id);
    }

    anchors.fill: parent
    // The popup content under it keeps all mouse input.
    z: 5

    Shortcut {
        sequence: ShortcutList.keysFor("newChat")
        context: Qt.WindowShortcut
        onActivated: shortcuts.chat.createSession(true)
    }

    Shortcut {
        sequence: ShortcutList.keysFor("incognito")
        context: Qt.WindowShortcut
        enabled: !!shortcuts.chat && !!shortcuts.chat.incognito && !shortcuts.chat.loading
        onActivated: shortcuts.chat.incognito.start()
    }

    Shortcut {
        sequence: ShortcutList.keysFor("searchChats")
        context: Qt.WindowShortcut
        onActivated: shortcuts.searchRequested()
    }

    Shortcut {
        sequence: ShortcutList.keysFor("history")
        context: Qt.WindowShortcut
        onActivated: shortcuts.chat.historyOnlyMode = !shortcuts.chat.historyOnlyMode
    }

    Shortcut {
        sequence: ShortcutList.keysFor("stop")
        context: Qt.WindowShortcut
        // A selected message takes Esc first (ChatView.qml): it clears the selection.
        enabled: !!shortcuts.chat && !shortcuts._browsing() && (shortcuts.chat.loading || shortcuts.chat.editingMessageIndex >= 0)
        onActivated: {
            if (shortcuts.chat.loading) {
                shortcuts.chat.stopStreaming();
            } else {
                shortcuts.chat.editingMessageIndex = -1;
                shortcuts.chat.editingDraft = "";
            }
        }
    }

    Shortcut {
        sequence: ShortcutList.keysFor("info")
        context: Qt.WindowShortcut
        onActivated: shortcuts.chatInfoRequested()
    }

    Shortcut {
        sequence: ShortcutList.keysFor("focusInput")
        context: Qt.WindowShortcut
        onActivated: shortcuts.chat.focusInput()
    }

    Shortcut {
        sequence: ShortcutList.keysFor("regenerate")
        context: Qt.WindowShortcut
        enabled: !!shortcuts.chat && !shortcuts.chat.loading && shortcuts._lastReply() >= 0
        onActivated: shortcuts.chat.regenerateResponse(shortcuts._lastReply(), "")
    }

    Shortcut {
        sequence: ShortcutList.keysFor("copyReply")
        context: Qt.WindowShortcut
        enabled: !!shortcuts.chat && shortcuts._lastReply() >= 0
        onActivated: shortcuts.chat.copyTextToClipboard(shortcuts.chat.messages[shortcuts._lastReply()].content)
    }

    Shortcut {
        sequence: ShortcutList.keysFor("nextChat")
        context: Qt.WindowShortcut
        onActivated: shortcuts._goToChat(1)
    }

    Shortcut {
        sequence: ShortcutList.keysFor("prevChat")
        context: Qt.WindowShortcut
        onActivated: shortcuts._goToChat(-1)
    }

    Shortcut {
        sequence: ShortcutList.keysFor("settings")
        context: Qt.WindowShortcut
        onActivated: shortcuts.chat.openSettings()
    }

    Shortcut {
        sequence: ShortcutList.keysFor("editLast")
        context: Qt.WindowShortcut
        enabled: !!shortcuts.chat && !shortcuts.chat.loading
        onActivated: {
            var composer = shortcuts.chat.composerRef;
            if (composer && composer.editLastMessage() && shortcuts.chat.msgListViewRef)
                shortcuts.chat.msgListViewRef.clearSelection();
        }
    }

    // Ctrl+Shift+S: read aloud the selected text (a message, the input or an
    // edit box), else the picked message, else the last reply; stop if reading.
    Shortcut {
        sequence: ShortcutList.keysFor("readAloud")
        context: Qt.WindowShortcut
        enabled: !!shortcuts.chat && shortcuts.chat.voiceTtsEnabled === true && !!shortcuts.chat.voiceManagerRef
        onActivated: {
            var chat = shortcuts.chat;
            if (chat.voiceManagerRef.isPlaying) {
                chat.voiceManagerRef.stopTTS();
                chat.playingMessageIndex = -1;
                return;
            }
            var list = chat.msgListViewRef;
            var target = ReadAloudAction.shortcutTarget(shortcuts.Window.window ? shortcuts.Window.window.activeFocusItem : null,
                                                        chat.messages, list ? list.selectedIndex : -1, shortcuts._lastReply());
            if (target)
                ReadAloudAction.toggle(chat, target.index, target.text);
        }
    }

    UndoNotice {
        id: undo
        chat: shortcuts.chat
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: (shortcuts.chat && shortcuts.chat.composerRef ? shortcuts.chat.composerRef.height : 0) + Kirigami.Units.largeSpacing * 2
        width: Math.min(implicitWidth, parent.width - Kirigami.Units.largeSpacing * 2)
    }
}
