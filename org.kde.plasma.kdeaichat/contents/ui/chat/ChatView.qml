// The list of messages in the current chat.
//
// The one scroll rule: the list follows new content while chat.userScrolledUp
// is false. Scrolling away from the end (wheel, drag, scrollbar) stops
// following; reaching the end again, or pressing "Latest", resumes it.
//
// Browsing by keyboard: list.selectedIndex is the message picked with
// Up/Down (-1: none). The input (Composer.qml) calls browse()/jumpFirst()/
// jumpLatest() through chat.msgListViewRef while it is empty; once a message
// is selected the list itself has focus and handles the keys below.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "MessageContent.js" as MessageContent
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

Item {
    id: chatView

    property var chat: null
    readonly property alias list: list
    // True while the model replaces all its rows: the list lets go of it and
    // takes it back afterwards, which builds only the delegates at the end.
    // (Positioning at the end while the list applies a big insert makes it
    // build delegates one by one up from the end.)
    property bool replacing: false
    onReplacingChanged: if (replacing) chatView.list.clearSelection()

    Connections {
        target: chatView.chat ? chatView.chat.messageModel : null
        function onAboutToReplace() { chatView.replacing = true; }
        function onReplaced() { chatView.replacing = false; }
    }

    ListView {
        id: list

        anchors.fill: parent
        model: chatView.chat && !chatView.replacing ? chatView.chat.messageModel : null
        spacing: Kirigami.Units.largeSpacing
        clip: true
        cacheBuffer: Kirigami.Units.gridUnit * 40
        // No current item: it would keep row 0's delegate alive for nothing.
        currentIndex: -1
        // Delegates build their buttons after the first frame and keep this
        // much room for them.
        readonly property DeferredBuilder builder: DeferredBuilder {}
        readonly property real buttonHeight: buttonMetrics.implicitHeight
        // Smooth touchpad kinetics (issue #3).
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: 1800
        maximumFlickVelocity: 6000
        pixelAligned: false
        keyNavigationEnabled: false

        // The message picked with the keyboard, or -1.
        property int selectedIndex: -1
        function clearSelection() { selectedIndex = -1; }
        function select(i) {
            if (i < 0 || i >= count)
                return;
            selectedIndex = i;
            if (chatView.chat)
                chatView.chat.userScrolledUp = i < count - 1;
            positionViewAtIndex(i, ListView.Contain);
            forceActiveFocus();
        }
        // Ctrl+Q: quotes the picked message for the next one (chips above the
        // input, which gets the focus). Returns whether it did.
        function quoteSelected() {
            var message = chatView.chat && selectedIndex >= 0 ? chatView.chat.messages[selectedIndex] : null;
            if (!message || !chatView.chat.composerRef || !MessageContent.canQuote(message))
                return false;
            chatView.chat.composerRef.addQuote(message);
            return true;
        }
        // Jumps to (picks and shows) the message with this id, e.g. from a
        // quote: false when it is no longer in the chat.
        function jumpToMessage(id) {
            var row = chatView.chat && id !== "" ? chatView.chat.messageModel.indexOfKey(String(id)) : -1;
            if (row < 0)
                return false;
            select(row);
            return true;
        }
        // Up (delta -1) or Down (+1) one message. Down past the latest hands
        // focus back to the input. Returns whether it did anything.
        function browse(delta) {
            if (count === 0)
                return false;
            if (selectedIndex < 0) {
                if (delta > 0)
                    return false;
                select(count - 1);
            } else if (selectedIndex + delta >= count) {
                leave();
            } else {
                select(Math.max(0, selectedIndex + delta));
            }
            return true;
        }
        function leave() {
            clearSelection();
            if (chatView.chat)
                chatView.chat.focusInput();
        }
        function jumpFirst() {
            if (count === 0)
                return false;
            select(0);
            return true;
        }
        // The latest message: no selection, and the list follows again.
        function jumpLatest() {
            if (count === 0)
                return false;
            clearSelection();
            if (chatView.chat)
                chatView.chat.scrollToBottom(true);
            return true;
        }

        Keys.onPressed: function(event) {
            var plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier));
            if (event.key === Qt.Key_Up && plain && selectedIndex >= 0) {
                browse(-1);
            } else if (event.key === Qt.Key_Down && plain && selectedIndex >= 0) {
                browse(1);
            } else if (event.key === Qt.Key_PageUp && plain) {
                jumpFirst();
            } else if (event.key === Qt.Key_PageDown && plain) {
                jumpLatest();
                if (chatView.chat)
                    chatView.chat.focusInput();
            } else if (event.key === Qt.Key_Q && selectedIndex >= 0 && (event.modifiers & Qt.ControlModifier) && !(event.modifiers & (Qt.AltModifier | Qt.MetaModifier | Qt.ShiftModifier))) {
                if (!quoteSelected())
                    return;
            } else if (event.key === Qt.Key_Escape && selectedIndex >= 0) {
                leave();
            } else if (selectedIndex >= 0 && plain && event.text.length === 1 && event.text >= " " && event.text !== "\x7f") {
                // Typing goes to the input, with this character.
                clearSelection();
                if (chatView.chat && chatView.chat.composerRef)
                    chatView.chat.composerRef.typeText(event.text);
            } else {
                return;
            }
            event.accepted = true;
        }

        delegate: MessageDelegate {
            width: list.width - (scrollBar.visible ? scrollBar.width : 0)
            chat: chatView.chat
        }

        function follow() {
            // Not while the user drags or flicks: userMoved() decides then.
            if (chatView.chat && !chatView.chat.userScrolledUp && count > 0 && !moving && !scrollBar.pressed)
                positionViewAtEnd();
        }
        function userMoved() {
            if (chatView.chat)
                chatView.chat.userScrolledUp = !atYEnd;
        }

        onContentHeightChanged: follow()
        onHeightChanged: follow()
        onCountChanged: {
            if (selectedIndex >= count)
                selectedIndex = -1;
            follow();
        }
        onMovementEnded: userMoved()
        onDraggingChanged: if (!dragging) userMoved()
        Component.onCompleted: if (chatView.chat) chatView.chat.msgListViewRef = list

        WheelHandler {
            target: list
            orientation: Qt.Vertical
            onWheel: function(event) {
                var delta = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 8;
                if (delta === 0)
                    return;
                var top = list.originY;
                var bottom = Math.max(top, list.originY + list.contentHeight - list.height);
                var target = Math.max(top, Math.min(list.contentY - delta, bottom));
                // Stop following first: moving can build a delegate, change
                // contentHeight and call follow() before userMoved() runs.
                if (chatView.chat && target < bottom)
                    chatView.chat.userScrolledUp = true;
                list.contentY = target;
                list.userMoved();
                event.accepted = true;
            }
        }

        QQC2.ScrollBar.vertical: QQC2.ScrollBar {
            id: scrollBar
            onPressedChanged: if (!pressed) list.userMoved()
            onPositionChanged: if (pressed) list.userMoved()
        }
    }

    // An empty chat: guidance instead of a blank panel. Decided from the
    // chat's messages, not the list's count, which is 0 for a moment while a
    // chat opens (building this then would slow opening every chat).
    Loader {
        anchors.fill: parent
        active: !!chatView.chat && !chatView.replacing && (chatView.chat.messages || []).length === 0
        visible: active
        sourceComponent: EmptyState {
            chat: chatView.chat
        }
    }

    PC3.ToolButton {
        id: buttonMetrics
        visible: false
        icon.name: "edit-copy"
        display: PC3.AbstractButton.IconOnly
    }

    PC3.Button {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Kirigami.Units.largeSpacing
        visible: !!chatView.chat && chatView.chat.userScrolledUp && list.count > 0
        text: chatView.chat && chatView.chat.loading ? i18n("New messages") : i18n("Latest")
        icon.name: "go-down"
        onClicked: chatView.chat.scrollToBottom(true)
    }
}
