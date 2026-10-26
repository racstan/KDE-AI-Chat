// Keyboard shortcuts for the chat popup, and the Undo notice that floats
// above the composer (so it shows whichever page is open).
//
// The list (keys and labels) is in ShortcutList.js, also shown in
// Settings → Appearance. Popup only (Qt.WindowShortcut). None of them is a
// text-editing key, so the input keeps Ctrl+C/V/X/Z/A and Ctrl+arrows.
//
//   Ctrl+N          new chat
//   Ctrl+H          show or hide the history
//   Ctrl+I          show or hide the chat info panel (chatInfoRequested)
//   Ctrl+L          focus the input
//   Esc             stop the reply that is being written; cancel an edit
//   Ctrl+Shift+R    regenerate the last reply
//   Ctrl+Shift+C    copy the last reply
//   Ctrl+PgDown/Up  next / previous chat
//   Ctrl+,          open the settings
//   Ctrl+E          edit your last message
//   Up / Down       browse the messages (input empty, or the chat clicked)
//   PgUp / PgDown   first / latest message
//
// (The history has no search field, so there is no "search chats" key.)
// Up/Down/PgUp/PgDown (browsing; ChatView.qml and Composer.qml, which read
// the keys from the list below), Esc on a selected message and "/"
// (templates) are keys of the list or the input itself.
//
// Fills its parent and takes no mouse input; put it once in the popup.
import QtQuick
import org.kde.kirigami as Kirigami
import "ShortcutList.js" as ShortcutList

Item {
    id: shortcuts

    property var chat: null
    readonly property alias undoNotice: undo
    // Ctrl+I: the popup owns the info panel, so it listens to this.
    signal chatInfoRequested()

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

    UndoNotice {
        id: undo
        chat: shortcuts.chat
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: (shortcuts.chat && shortcuts.chat.composerRef ? shortcuts.chat.composerRef.height : 0) + Kirigami.Units.largeSpacing * 2
        width: Math.min(implicitWidth, parent.width - Kirigami.Units.largeSpacing * 2)
    }
}
