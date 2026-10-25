// The list of messages in the current chat.
//
// The one scroll rule: the list follows new content while chat.userScrolledUp
// is false. Scrolling away from the end (wheel, drag, scrollbar) stops
// following; reaching the end again, or pressing "Latest", resumes it.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
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
        onCountChanged: follow()
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
