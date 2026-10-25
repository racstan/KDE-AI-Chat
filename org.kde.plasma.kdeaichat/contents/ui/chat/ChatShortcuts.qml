// Keyboard shortcuts for the chat popup, and the Undo notice that floats
// above the composer (so it shows whichever page is open).
//
//   Ctrl+N   new chat
//   Ctrl+H   show or hide the history
//   Esc      stop the reply that is being written; cancel an edit
//
// Up in an empty input (edit your last message) and "/" (templates) are
// keys of the input itself, in Composer.qml.
//
// Fills its parent and takes no mouse input; put it once in the popup.
import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: shortcuts

    property var chat: null
    readonly property alias undoNotice: undo

    anchors.fill: parent
    // The popup content under it keeps all mouse input.
    z: 5

    Shortcut {
        sequence: "Ctrl+N"
        context: Qt.WindowShortcut
        onActivated: shortcuts.chat.createSession(true)
    }

    Shortcut {
        sequence: "Ctrl+H"
        context: Qt.WindowShortcut
        onActivated: shortcuts.chat.historyOnlyMode = !shortcuts.chat.historyOnlyMode
    }

    Shortcut {
        sequence: "Esc"
        context: Qt.WindowShortcut
        enabled: !!shortcuts.chat && (shortcuts.chat.loading || shortcuts.chat.editingMessageIndex >= 0)
        onActivated: {
            if (shortcuts.chat.loading) {
                shortcuts.chat.stopStreaming();
            } else {
                shortcuts.chat.editingMessageIndex = -1;
                shortcuts.chat.editingDraft = "";
            }
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
