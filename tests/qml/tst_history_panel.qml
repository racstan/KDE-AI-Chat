// The history: a side panel beside the chat in a wide popup, the whole view
// in a narrow one (chat/ChatBody.qml), with compact rows whose actions show on
// hover or keyboard focus only (chat/SessionList.qml).
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 760
    height: 600

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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Chat.ChatHeader { id: header; chat: chat; historyFull: body.historyFull }
        Chat.ChatBody {
            id: body
            chat: chat
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    HarnessTestCase {
        id: test
        name: "HistoryPanel"

        readonly property real day: 86400000

        function init() {
            root.width = 760;
            chat.historyOnlyMode = false;
            chat.calls = [];
            chat.editingSessionId = "";
            var now = Date.now();
            chat.currentSessionId = "a";
            chat.messages = [{role: "user", content: "Where should we go in May?", time: "10:01"},
                             {role: "assistant", model: "openrouter/auto", content: "Somewhere warm.", time: "10:01", tokens: {input: 30, output: 12}}];
            chat.sessions = [
                {value: "a", text: "Trip planning", count: 4, updatedAt: now},
                {value: "b", text: "OpenCode refactor", source: "opencode", count: 14, updatedAt: now - day},
                {value: "c", text: "Shell one-liners", count: 9, updatedAt: now - 20 * day},
                {value: "d", text: "Old chat", archived: true, count: 3, updatedAt: now - 60 * day}
            ];
            wait(20);
        }

        function find(item, name) {
            if (item.objectName === name) return item;
            var kids = item.children || [];
            for (var i = 0; i < kids.length; i++) {
                var found = find(kids[i], name);
                if (found) return found;
            }
            return null;
        }

        function row(index) {
            tryVerify(() => body.sessionList !== null && body.sessionList.list.itemAtIndex(index) !== null);
            return body.sessionList.list.itemAtIndex(index);
        }

        function open() {
            chat.historyOnlyMode = true;
            tryVerify(() => body.sessionList !== null);
        }

        function test_01_wide_popup_shows_history_beside_the_chat() {
            verify(body.sideHistory, "760 px popup is wide");
            compare(body.historyPane.width, 0);
            open();
            tryCompare(body.historyPane, "width", body.panelWidth + Kirigami.Units.smallSpacing);
            verify(!body.historyFull);
            verify(body.chatView.visible, "the chat stays visible");
            verify(body.composerItem.visible);
            verify(body.chatView.mapToItem(body, 0, 0).x >= body.historyPane.width, "chat is to the right of the history");
            verify(chat.historySidePanel);
            compare(body.sessionList.list.count, 3, "All chats: the archived one is in Archived");
            compare(header.historyFull, false);
            screenshot(root, "history-panel-wide");
        }

        function test_02_closing_slides_the_panel_away() {
            open();
            tryCompare(body.historyPane, "width", body.panelWidth + Kirigami.Units.smallSpacing);
            chat.historyOnlyMode = false;
            tryCompare(body.historyPane, "width", 0);
            tryVerify(() => !body.historyPane.visible);
        }

        function test_03_narrow_popup_shows_history_instead_of_the_chat() {
            root.width = 560;
            verify(!body.sideHistory);
            open();
            tryCompare(body.historyPane, "width", body.width);
            verify(body.historyFull);
            verify(!body.chatView.visible);
            verify(!body.composerItem.visible);
            verify(!chat.historySidePanel);
            compare(header.historyFull, true);
            screenshot(root, "history-panel-narrow");
        }

        function test_04_resizing_across_the_threshold_switches_layout() {
            open();
            tryCompare(body.historyPane, "width", body.panelWidth + Kirigami.Units.smallSpacing);
            verify(body.chatView.visible);
            root.width = 600;
            tryVerify(() => body.historyFull);
            tryVerify(() => !body.chatView.visible);
            root.width = 760;
            tryVerify(() => !body.historyFull);
            tryVerify(() => body.chatView.visible);
        }

        function test_05_rows_show_title_and_when() {
            open();
            var r0 = row(0);
            var date0 = find(r0, "dateLabel");
            compare(date0.text, "Today");
            compare(find(row(1), "dateLabel").text, "Yesterday");
            compare(find(row(2), "dateLabel").text, new Date(Date.now() - 20 * day).toLocaleDateString(Qt.locale(), Locale.ShortFormat));
            compare(body.sessionList.dayLabel(0), "");
            compare(row(0).title, "Trip planning");
        }

        function test_06_row_actions_show_on_hover_only() {
            open();
            tryCompare(body.historyPane, "width", body.panelWidth + Kirigami.Units.smallSpacing);
            var r = row(1);
            verify(!find(r, "renameButton").visible);
            verify(!find(r, "archiveButton").visible);
            verify(!find(r, "deleteButton").visible);
            verify(find(r, "dateLabel").visible);
            mouseMove(r, r.width / 2, r.height / 2);
            tryVerify(() => r.showActions);
            verify(find(r, "renameButton").visible);
            verify(find(r, "archiveButton").visible);
            verify(find(r, "deleteButton").visible);
            verify(!find(r, "dateLabel").visible);
            screenshot(root, "history-panel-hover");
            mouseMove(body.chatView, 10, 10);
            tryVerify(() => !r.showActions);
            verify(!find(r, "deleteButton").visible);
        }

        function test_07_row_actions_show_on_keyboard_focus() {
            open();
            var r = row(2);
            verify(!find(r, "deleteButton").visible);
            r.forceActiveFocus();
            verify(r.activeFocus);
            verify(find(r, "deleteButton").visible, "focused row shows its actions");
            // The actions are reachable from the row with Tab.
            keyClick(Qt.Key_Tab);
            verify(find(r, "renameButton").activeFocus);
            keyClick(Qt.Key_Tab);
            verify(find(r, "archiveButton").activeFocus);
            verify(find(r, "deleteButton").visible, "still shown while a button has focus");
            row(0).forceActiveFocus();
            tryVerify(() => !find(r, "deleteButton").visible);
        }

        // Click a row button once the row's layout has settled: toggling
        // rename shows/hides sibling buttons and moves the others on the next
        // polish, so a click at once could hit stale geometry (flaky).
        function clickRowButton(r, name, shown) {
            var b = find(r, name);
            tryCompare(b, "visible", shown);
            tryVerify(() => b.width > 0 && b.height > 0);
            // A fresh or re-laid-out row sits at its initial position until the
            // RowLayout polishes: the action buttons belong in the row's right
            // half. Then wait until the position holds still across frames.
            tryVerify(() => b.mapToItem(r, 0, 0).x > r.width / 2);
            var last = null;
            tryVerify(function() {
                waitForRendering(r);
                var p = b.mapToItem(root, 0, 0);
                var same = last !== null && last.x === p.x && last.y === p.y;
                last = p;
                return same;
            });
            mouseClick(b);
        }

        function test_08_actions_rename_archive_delete() {
            open();
            tryCompare(body.historyPane, "width", body.panelWidth + Kirigami.Units.smallSpacing);
            var r = row(1);
            mouseMove(r, r.width / 2, r.height / 2);
            tryVerify(() => r.showActions);
            clickRowButton(r, "renameButton", true);
            tryCompare(chat, "editingSessionId", "b");
            // While renaming the row keeps its buttons: save, cancel.
            verify(r.showActions);
            clickRowButton(r, "deleteButton", true);
            tryCompare(chat, "editingSessionId", "");
            clickRowButton(r, "archiveButton", true);
            compare(chat.calls[chat.calls.length - 1].name, "archive");
            compare(chat.calls[chat.calls.length - 1].args[0], "b");
            compare(chat.calls[chat.calls.length - 1].args[1], true);
            clickRowButton(r, "deleteButton", true);
            compare(chat.calls[chat.calls.length - 1].name, "deleteSession");
            compare(chat.calls[chat.calls.length - 1].args[0], "b");
        }

        function test_09_clicking_a_row_opens_that_chat() {
            open();
            tryCompare(body.historyPane, "width", body.panelWidth + Kirigami.Units.smallSpacing);
            mouseClick(row(1), 40, row(1).height / 2);
            compare(chat.currentSessionId, "b");
            verify(chat.historyOnlyMode, "beside the chat the history stays open");
            // Enter on a focused row does the same.
            row(2).forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(chat.currentSessionId, "c");
            verify(chat.historyOnlyMode);
        }

        function test_10_choosing_a_chat_in_the_narrow_view_goes_back_to_the_chat() {
            root.width = 560;
            open();
            tryCompare(body.historyPane, "width", body.width);
            mouseClick(row(1), 40, row(1).height / 2);
            compare(chat.currentSessionId, "b");
            verify(!chat.historyOnlyMode);
            tryVerify(() => body.chatView.visible);
        }

        function test_11_header_toggle_and_accessible_names() {
            var buttons = [];
            function collect(item) {
                if (item.hasOwnProperty("icon") && item.hasOwnProperty("display") && item.hasOwnProperty("pressed") && item.visible)
                    buttons.push(item);
                var kids = item.children || [];
                for (var i = 0; i < kids.length; i++) collect(kids[i]);
            }
            collect(header);
            verify(buttons.length >= 5, "header buttons found: " + buttons.length);
            for (var i = 0; i < buttons.length; i++)
                verify(buttons[i].Accessible.name !== "", "header button " + buttons[i].icon.name + " has an accessible name");
            // The first button is the history toggle.
            var historyButton = buttons[0];
            compare(historyButton.Accessible.name, "Show history");
            historyButton.clicked();
            verify(chat.historyOnlyMode);
            tryCompare(historyButton, "checked", true);
            compare(historyButton.Accessible.name, "Hide history");
            historyButton.clicked();
            verify(!chat.historyOnlyMode);
            root.width = 560;
            chat.historyOnlyMode = true;
            tryVerify(() => header.historyFull);
            compare(historyButton.Accessible.name, "Back to chat");
        }

        function test_12_the_chat_is_told_when_the_history_sits_beside_it() {
            // main.qml's createSession() keeps the history open (instead of
            // going back to the chat) while this is true.
            verify(chat.historySidePanel);
            root.width = 560;
            tryVerify(() => !chat.historySidePanel);
        }

        // Chats whose titles are far longer than any row.
        function longChats() {
            var now = Date.now();
            return [
                {value: "a", text: "Trip planning", count: 4, updatedAt: now},
                {value: "l1", text: "A very long title with many words that goes on and on and on and on well past the edge of any popup you could open", source: "opencode", updatedAt: now - day},
                {value: "l2", text: "Unbrokenlongtitlewithoutanyspacesatalleverywhereinthisstringsoitcannotwrapanywhere1234567890", source: "pi", updatedAt: now - 20 * day},
                {value: "l3", text: "Another long one that also has a long name to elide nicely", updatedAt: now - 60 * day},
                // Titles are the start of what was typed: markup and line breaks must not escape the row.
                {value: "l4", text: "<b>Fix</b> this <i>please</i>, it is a long html looking title that never ends and never ends and never ends", updatedAt: now - 3 * day},
                {value: "l5", text: "first line\nsecond line of a title that came from a multi line first message and is very long indeed", updatedAt: now - 4 * day}
            ];
        }

        // Every visible part of `item` lies inside `item` (give or take a pixel).
        function partsInside(item, what) {
            function walk(node) {
                var kids = node.children || [];
                for (var i = 0; i < kids.length; i++) {
                    var k = kids[i];
                    if (k.visible && k.width > 0 && k.height > 0) {
                        var p = k.mapToItem(item, 0, 0);
                        verify(p.x >= -1 && p.x + k.width <= item.width + 1,
                               what + ": " + k + " spans " + p.x + ".." + (p.x + k.width) + " of " + item.width);
                        walk(k);
                    }
                }
            }
            walk(item);
        }

        function checkHistoryFits(width) {
            root.width = width;
            chat.sessions = longChats();
            chat.historyOnlyMode = true;
            tryVerify(() => body.sessionList !== null);
            tryCompare(body.historyPane, "width", body.sideHistory ? body.panelWidth + Kirigami.Units.smallSpacing : body.width);
            wait(30);
            var list = body.sessionList;
            var at = list.mapToItem(body, 0, 0);
            verify(at.x >= 0 && at.x + list.width <= body.width + 1, width + ": the history is inside the popup");
            compare(body.mapToItem(root, 0, 0).x + body.width <= root.width + 1, true);
            for (var i = 0; i < 6; i++) {
                var r = row(i);
                verify(r.width <= list.list.width + 1, width + ": row " + i + " is no wider than the list");
                partsInside(r, width + " row " + i);
                // Hovered: the three actions appear and must still fit.
                mouseMove(r, r.width / 2, r.height / 2);
                tryVerify(() => r.showActions);
                wait(30);
                partsInside(r, width + " hovered row " + i);
                mouseMove(body.sessionList, -5, -5);
            }
            // Renaming shows a text field plus two buttons.
            chat.editingSessionDraft = longChats()[2].text;
            chat.editingSessionId = "l2";
            wait(50);
            partsInside(row(2), width + " renaming row");
            chat.editingSessionId = "";
            for (var j = 0; j < 6; j++) {
                var t = find(row(j), "titleLabel");
                verify(t !== null && t.width > 0, "title label exists");
                verify(t.truncated || t.implicitWidth <= t.width + 1, width + ": long titles elide");
            }
            // The title is the one to give way: the date or actions never vanish off the right edge.
            screenshot(root, "history-fit-" + width);
        }

        function test_13_rows_fit_the_panel_at_every_width() {
            var widths = [360, 520, 760, 1100];
            for (var i = 0; i < widths.length; i++) {
                chat.historyOnlyMode = false;
                tryCompare(body.historyPane, "width", 0);
                checkHistoryFits(widths[i]);
            }
        }

        function test_14_rows_stay_beside_the_scroll_bar_in_a_long_history() {
            var many = [];
            for (var i = 0; i < 25; i++)
                many.push({value: "m" + i, text: "Chat number " + i + " with a title long enough to need eliding in a narrow panel", updatedAt: Date.now() - i * day});
            var widths = [360, 760];
            chat.sessions = many;
            for (var w = 0; w < widths.length; w++) {
                root.width = widths[w];
                open();
                tryCompare(body.historyPane, "width", body.sideHistory ? body.panelWidth + Kirigami.Units.smallSpacing : body.width);
                var list = body.sessionList.list;
                tryVerify(() => list.contentHeight > list.height);
                var bar = list.QQC2.ScrollBar.vertical;
                var r = row(0);
                mouseMove(r, r.width / 2, r.height / 2);
                tryVerify(() => r.showActions);
                wait(30);
                verify(r.width <= list.width - bar.width + 1, widths[w] + ": rows leave room for the scroll bar");
                var del = find(r, "deleteButton");
                verify(del.mapToItem(list, del.width, 0).x <= list.width - bar.width + 1, widths[w] + ": the delete button is not under the scroll bar");
                partsInside(r, widths[w] + " row with scroll bar");
            }
        }
    }
}
