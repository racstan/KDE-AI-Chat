// chat/ResizeHandle.qml (problem 5): the popup grows by exactly the mouse's
// movement on screen even though the handle moves with the popup's corner,
// stays within min/max, and the size is saved to config once, on release.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 800
    height: 700

    // Stand-in for plasmoid.configuration; counts writes.
    QtObject {
        id: config
        property int customPopupWidth: 300
        property int customPopupHeight: 200
        property int writes: 0
        onCustomPopupWidthChanged: writes++
        onCustomPopupHeightChanged: writes++
    }

    // The size properties exactly as main.qml declares them.
    QtObject {
        id: chat
        property int livePopupWidth: 0
        property int livePopupHeight: 0
        readonly property int popupPreferredWidth: livePopupWidth > 0 ? livePopupWidth : (config.customPopupWidth > 0 ? config.customPopupWidth : 760)
        readonly property int popupPreferredHeight: livePopupHeight > 0 ? livePopupHeight : (config.customPopupHeight > 0 ? config.customPopupHeight : 760)
    }

    // The "popup": follows the chat's size, so the handle in its corner
    // moves while it is dragged.
    Rectangle {
        id: popup
        x: 20
        y: 20
        width: chat.popupPreferredWidth
        height: chat.popupPreferredHeight
        color: "white"
        border.color: "gray"

        Chat.ResizeHandle {
            id: handle
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            chat: chat
            config: config
            minimumWidth: 250
            minimumHeight: 150
            maximumWidth: 600
            maximumHeight: 500
        }
    }

    HarnessTestCase {
        name: "ResizeHandle"

        function init() {
            config.customPopupWidth = 300;
            config.customPopupHeight = 200;
            config.writes = 0;
        }

        // Press the handle's centre, then move the mouse along `path`
        // (offsets from the press point, in window coordinates) and record
        // the size after each step.
        function drag(path, release) {
            const start = handle.mapToItem(root, handle.width / 2, handle.height / 2);
            mousePress(root, start.x, start.y);
            const sizes = [];
            for (const step of path) {
                mouseMove(root, start.x + step[0], start.y + step[1], -1, Qt.LeftButton);
                sizes.push([chat.popupPreferredWidth, chat.popupPreferredHeight]);
            }
            if (release !== false) {
                const last = path[path.length - 1];
                mouseRelease(root, start.x + last[0], start.y + last[1]);
            }
            return sizes;
        }

        function test_1_grows_by_exactly_the_mouse_delta() {
            const path = [];
            for (let i = 1; i <= 10; i++)
                path.push([i * 10, i * 5]);
            const sizes = drag(path, false);
            for (let i = 0; i < path.length; i++) {
                compare(sizes[i][0], 300 + path[i][0], "width after step " + i);
                compare(sizes[i][1], 200 + path[i][1], "height after step " + i);
            }
            compare(popup.width, 400);
            compare(config.writes, 0, "config is not written while dragging");
            screenshot(root, "resize-handle-dragging");
            const at = handle.mapToItem(root, handle.width / 2, handle.height / 2);
            mouseRelease(root, at.x, at.y);
            compare(config.customPopupWidth, 400);
            compare(config.customPopupHeight, 250);
        }

        function test_2_holding_still_does_not_oscillate() {
            const path = [[40, 30]];
            for (let i = 0; i < 8; i++)
                path.push([40, 30]);
            const sizes = drag(path);
            for (const s of sizes) {
                compare(s[0], 340);
                compare(s[1], 230);
            }
        }

        function test_3_shrinking_stops_at_the_minimum() {
            const sizes = drag([[-20, -20], [-100, -100], [-300, -300], [-30, -30]]);
            compare(sizes[0][0], 280);
            compare(sizes[0][1], 180);
            compare(sizes[1][0], 250);
            compare(sizes[1][1], 150);
            compare(sizes[2][0], 250);
            compare(sizes[2][1], 150);
            // Back towards the start: the size follows the mouse again.
            compare(sizes[3][0], 270);
            compare(sizes[3][1], 170);
        }

        function test_4_growing_stops_at_the_maximum() {
            const sizes = drag([[450, 450]]);
            compare(sizes[0][0], 600);
            compare(sizes[0][1], 500);
            compare(config.customPopupWidth, 600);
            compare(config.customPopupHeight, 500);
        }

        function test_5_config_is_written_once_on_release() {
            drag([[5, 5], [10, 10], [15, 15], [20, 20], [25, 25]]);
            compare(config.writes, 2, "one write per dimension");
            compare(config.customPopupWidth, 325);
            compare(config.customPopupHeight, 225);
            compare(chat.livePopupWidth, 0, "live size cleared after release");
            compare(popup.width, 325, "popup keeps the saved size");
        }

        function test_6_top_left_handle_grows_up_and_left() {
            handle.growsLeft = true;
            handle.growsUp = true;
            const sizes = drag([[-30, -20], [-60, -40]]);
            compare(sizes[0][0], 330);
            compare(sizes[0][1], 220);
            compare(sizes[1][0], 360);
            compare(sizes[1][1], 240);
            handle.growsLeft = false;
            handle.growsUp = false;
        }
    }
}
