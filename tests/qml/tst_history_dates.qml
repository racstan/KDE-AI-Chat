// The history's rows keep their date ("Today", "Yesterday", a date) whole and
// in view: a long title is cut instead. Checked as geometry in a narrow popup
// (history instead of the chat), and beside the chat in a wide and a very wide one.
import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 760
    height: 560

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat { id: chat }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    Chat.ChatBody {
        id: body
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        chat: chat
    }

    HarnessTestCase {
        name: "HistoryDates"

        readonly property real day: 86400000

        function init() {
            chat.historyOnlyMode = false;
            chat.editingSessionId = "";
            var now = Date.now();
            chat.currentSessionId = "a";
            chat.messages = [];
            chat.sessions = [
                {value: "a", text: "Planning a two week trip through the north of Italy by train", projectId: "p-1", updatedAt: now},
                {value: "b", text: "Why does my OpenCode refactor keep failing the type checker", source: "opencode", updatedAt: now - day},
                {value: "c", text: "Shell one-liners for renaming thousands of photos by date", updatedAt: now - 20 * day},
                {value: "d", text: "Short", updatedAt: now - 2 * day}
            ];
            wait(20);
        }

        function cleanup() {
            chat.historyOnlyMode = false;
            tryCompare(body.historyPane, "width", 0);
        }

        function rows() {
            var list = body.sessionList.list;
            var out = [];
            for (var i = 0; i < list.count; i++) {
                var item = list.itemAtIndex(i);
                if (item && item.y - list.contentY < list.height)
                    out.push(item);
            }
            return out;
        }

        // Every row's date is shown whole, inside the row and inside the visible history.
        function checkDates(tag) {
            chat.historyOnlyMode = true;
            tryVerify(() => body.sessionList !== null, 2000);
            tryVerify(() => Math.abs(body.historyPane.width - body.historyPane.shownWidth) < 0.5, 3000, "the history has slid in");
            wait(50);
            var all = rows();
            verify(all.length >= 4);
            for (var i = 0; i < all.length; i++) {
                var date = findChild(all[i], "dateLabel");
                var title = findChild(all[i], "titleLabel");
                verify(date.visible, tag + ": row " + i + " shows its date");
                verify(!date.truncated, tag + ": row " + i + " date is whole: " + date.text);
                verify(date.width >= date.implicitWidth - 0.5, tag + ": row " + i + " date has its room");
                var inRow = date.mapToItem(all[i], 0, 0);
                verify(inRow.x >= 0 && inRow.x + date.width <= all[i].width + 0.5, tag + ": row " + i + " date inside the row");
                var inPane = date.mapToItem(body.historyPane, 0, 0);
                verify(inPane.x + date.width <= body.historyPane.width + 0.5, tag + ": row " + i + " date inside the visible history");
                verify(title.x + title.width <= date.x + 0.5, tag + ": row " + i + " the title ends before the date");
            }
            verify(findChild(all[0], "titleLabel").truncated, tag + ": a long title is cut instead");
        }

        function test_many_chats_with_a_scroll_bar() {
            var many = chat.sessions.slice();
            for (var i = 0; i < 40; i++)
                many.push({value: "x" + i, text: "Another fairly long chat title number " + i, updatedAt: Date.now() - i * day});
            chat.sessions = many;
            root.width = 760;
            checkDates("scroll bar");
            screenshot(root, "history-dates-scrollbar");
        }

        function test_narrow_popup() {
            root.width = 360;
            verify(!body.sideHistory);
            checkDates("360 px");
            screenshot(root, "history-dates-narrow");
        }

        function test_wide_popup_side_panel() {
            root.width = 760;
            verify(body.sideHistory);
            checkDates("760 px");
            screenshot(root, "history-dates-wide");
        }

        function test_very_wide_popup_side_panel() {
            root.width = 1300;
            verify(body.sideHistory);
            checkDates("1300 px");
            verify(body.panelWidth > Kirigami.Units.gridUnit * 15, "a wide popup gives the history more room");
            verify(body.panelWidth <= body.width / 3 + 0.5, "the chat keeps most of the room");
            screenshot(root, "history-dates-very-wide");
        }

        // The project list on top keeps its counts in view as well.
        function test_project_rows_keep_their_counts() {
            root.width = 760;
            chat.projects.create({"name": "A project with a really quite long name", "color": "#3daee9"});
            chat.historyOnlyMode = true;
            tryVerify(() => body.sessionList !== null, 2000);
            tryVerify(() => Math.abs(body.historyPane.width - body.historyPane.shownWidth) < 0.5, 3000);
            wait(50);
            var list = body.sessionList.sidebar.list;
            for (var i = 0; i < list.count; i++) {
                var count = findChild(list.itemAtIndex(i), "viewCount");
                if (!count.visible || count.text === "")
                    continue;
                var at = count.mapToItem(body.historyPane, 0, 0);
                verify(at.x + count.width <= body.historyPane.width + 0.5, "count " + i + " in view");
            }
        }
    }
}
