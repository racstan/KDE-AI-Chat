// The history: a side panel beside the chat in a wide popup, the whole view
// in a narrow one (chat/ChatBody.qml), with compact rows whose actions show on
// hover or keyboard focus only (chat/SessionList.qml).
import QtQuick
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
            compare(body.sessionList.list.count, 4);
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
            row(3).forceActiveFocus();
            tryVerify(() => !find(r, "deleteButton").visible);
        }

        function test_08_actions_rename_archive_delete() {
            open();
            var r = row(1);
            mouseMove(r, r.width / 2, r.height / 2);
            tryVerify(() => find(r, "renameButton").visible && find(r, "renameButton").width > 0);
            wait(50);
            mouseClick(find(r, "renameButton"));
            compare(chat.editingSessionId, "b");
            // While renaming the row keeps its buttons: save, cancel.
            verify(r.showActions);
            mouseClick(find(r, "deleteButton"));
            compare(chat.editingSessionId, "");
            mouseClick(find(r, "archiveButton"));
            compare(chat.calls[chat.calls.length - 1].name, "archive");
            compare(chat.calls[chat.calls.length - 1].args[0], "b");
            compare(chat.calls[chat.calls.length - 1].args[1], true);
            mouseClick(find(r, "deleteButton"));
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
    }
}
