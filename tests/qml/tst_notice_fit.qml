// The Undo notice (chat/UndoNotice.qml, placed by ChatShortcuts.qml) and the
// notice banner (chat/NoticeBanner.qml) fit inside a narrow popup with a
// long text: the text wraps, the buttons stay inside.
import QtQuick
import QtQuick.Layouts
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 360
    height: 420

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat { id: chat }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 6

        Chat.NoticeBanner {
            id: banner
            isError: true
            actionText: "Replace stored history"
        }
    }

    Chat.ChatShortcuts {
        id: shortcuts
        chat: chat
    }

    HarnessTestCase {
        name: "NoticeFit"

        readonly property string longName: "A really rather long project name that goes on and on and on"

        // `item`'s left and right edges in root coordinates.
        function edges(item) {
            var p = item.mapToItem(root, 0, 0);
            return {"left": p.x, "right": p.x + item.width, "top": p.y, "bottom": p.y + item.height};
        }

        function inside(item, box, what) {
            var e = edges(item);
            verify(e.left >= box.left - 0.5, what + " starts inside (" + e.left + " < " + box.left + ")");
            verify(e.right <= box.right + 0.5, what + " ends inside (" + e.right + " > " + box.right + ")");
            verify(e.top >= box.top - 0.5 && e.bottom <= box.bottom + 0.5, what + " fits in height");
        }

        function check(width) {
            root.width = width;
            var notice = shortcuts.undoNotice;
            chat.projects.list = [{"id": "p1", "name": longName, "color": "#3daee9"}];
            chat.sessions = [{"value": "a", "text": "A", "projectId": "p1", "messages": []}];
            chat.projects.remove("p1");
            verify(notice.visible);
            wait(50);
            var box = edges(notice);
            verify(box.left >= 0 && box.right <= root.width, "the notice is inside the window at width " + width);
            inside(findChild(notice, "undoText"), box, "the text");
            inside(findChild(notice, "undoButton"), box, "Undo");
            inside(findChild(notice, "undoDismiss"), box, "the close button");
            verify(findChild(notice, "undoText").lineCount > 1, "the long text wraps");
            return notice;
        }

        function test_1_a_long_undo_notice_fits_a_narrow_window() {
            check(360);
            screenshot(root, "notice-fit-360");
        }

        function test_2_and_a_very_narrow_one() {
            check(240);
            screenshot(root, "notice-fit-240");
        }

        function test_3_a_short_notice_keeps_its_own_width() {
            root.width = 520;
            var notice = shortcuts.undoNotice;
            notice.show({"kind": "info"}, "Saved to memory");
            wait(50);
            verify(notice.width < root.width / 2, "not stretched");
            compare(findChild(notice, "undoText").lineCount, 1);
            notice.dismiss();
        }

        function test_4_the_banner_wraps_too() {
            root.width = 300;
            banner.text = "The stored chat history could not be read: " + longName + " " + longName;
            wait(50);
            verify(banner.width <= root.width);
            var box = edges(banner);
            for (var i = 0; i < banner.children.length; i++) {
                var kids = banner.children[i].children || [];
                for (var j = 0; j < kids.length; j++) {
                    if (kids[j].visible)
                        inside(kids[j], box, "banner part " + j);
                }
            }
            screenshot(root, "notice-fit-banner");
            banner.text = "";
        }
    }
}
