// The list of messages in the current chat.
//
// The one scroll rule: the list follows new content while chat.userScrolledUp
// is false. Scrolling away from the end (wheel, drag, scrollbar) stops
// following; reaching the end again, or pressing "Latest", resumes it.
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Item {
    id: chatView

    property var chat: null
    readonly property alias list: list

    ListView {
        id: list

        anchors.fill: parent
        model: chatView.chat ? chatView.chat.messageModel : null
        spacing: Kirigami.Units.largeSpacing
        clip: true
        cacheBuffer: Kirigami.Units.gridUnit * 40
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
            if (chatView.chat && !chatView.chat.userScrolledUp && count > 0)
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
                list.contentY = Math.max(top, Math.min(list.contentY - delta, bottom));
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
