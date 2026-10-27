// Search across all chats (chat/ChatSearchPanel.qml, chat/ChatSearch.js) in
// the history: chat names and message text, archived and project chats
// labelled, never an incognito chat; opening a result opens its chat at the
// message; Ctrl+Shift+F and the arrow keys.
import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 980
    height: 640

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat { id: chat }

    // FakeChat's switchSession only sets the id: the chat's messages follow here, as in main.qml.
    Connections {
        target: chat
        function onCurrentSessionIdChanged() {
            var at = chat.sessionIndexById(chat.currentSessionId);
            chat.messages = at >= 0 ? chat.sessions[at].messages || [] : [];
        }
    }

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

    Chat.ChatShortcuts {
        id: shortcuts
        chat: chat
        onSearchRequested: body.openSearch()
    }

    HarnessTestCase {
        id: test
        name: "ChatSearch"

        readonly property real day: 86400000

        function messages(prefix, texts, start) {
            return texts.map(function(t, i) {
                return {id: prefix + "-" + i, role: i % 2 ? "assistant" : "user", content: t, at: start + i * 60000, time: "10:0" + (i % 10)};
            });
        }

        function init() {
            root.width = 980;
            chat.historyOnlyMode = false;
            chat.calls = [];
            var now = Date.now();
            chat.projects.list = [{id: "p-1", name: "Work", color: "#1cdc9a", instructions: "", folder: "", provider: "", model: "", createdAt: 1}];
            var long = [];
            for (var i = 0; i < 40; i++)
                long.push(i === 3 ? "The Lisbon office opens in May, next to the river." : "Status update number " + i + " about the quarterly numbers.");
            chat.sessions = [
                {value: "a", text: "Weekend ideas", updatedAt: now, messages: messages("a", ["Any ideas for the weekend?", "A day trip to Sintra, near Lisbon, is lovely."], now - 3600000)},
                {value: "b", text: "Lisbon trip", updatedAt: now - day, messages: messages("b", ["Where to eat?", "Try the pastéis de nata in Belém."], now - day)},
                {value: "c", text: "Office notes", projectId: "p-1", updatedAt: now - 3 * day, messages: messages("c", long, now - 3 * day)},
                {value: "d", text: "Old travel plans", archived: true, updatedAt: now - 60 * day, messages: messages("d", ["Flights to Lisbon in March were cheap."], now - 60 * day)},
                {value: "s-incognito-1-1", text: "Lisbon secret", incognito: true, updatedAt: now, messages: messages("x", ["Lisbon surprise party"], now)}
            ];
            chat.currentSessionId = "a";
            chat.currentSessionTitle = "Weekend ideas";
            chat.messages = chat.sessions[0].messages;
            wait(20);
        }

        function panel() {
            tryVerify(function() { return body.sessionList !== null; });
            return body.sessionList.search;
        }

        function search(text) {
            chat.historyOnlyMode = true;
            var p = panel();
            p.field.text = text;
            tryVerify(function() { return p.query === text.trim(); }, 2000, "the search runs after the pause");
            return p;
        }

        function test_1_titles_and_message_text_of_every_chat() {
            var p = search("lisbon");
            var found = p.found.results.map(function(r) { return r.chatId + ":" + r.kind; });
            compare(found, ["a:message", "b:title", "c:message", "d:message"]);
            verify(!p.resultList.visible === false);
            verify(!body.sessionList.list.visible, "the results take the place of the chat list");
            tryVerify(function() { return p.resultList.count === 4; });
            // The archived chat and the project's chat are labelled; the match is marked.
            var places = findChildren(p.resultList, "resultPlace").map(function(l) { return l.visible ? l.text : ""; });
            verify(places.indexOf("Work") >= 0, places);
            verify(places.indexOf("Archived") >= 0, places);
            var snippets = findChildren(p.resultList, "resultSnippet").filter(function(l) { return l.visible; });
            verify(snippets[0].text.indexOf("<b><font color=") >= 0 && snippets[0].text.indexOf(">Lisbon</font>") >= 0, snippets[0].text);
            compare(findChild(p, "searchStatus").text, "4 matches");
            screenshot(root, "chat-search-results");
            // Clearing the field brings the history back.
            p.field.text = "";
            tryVerify(function() { return body.sessionList.list.visible; });
        }

        function test_2_opening_a_result_jumps_to_the_message() {
            var p = search("river");
            compare(p.found.results.length, 1);
            tryVerify(function() { return p.resultList.itemAtIndex(0) !== null; });
            mouseClick(p.resultList.itemAtIndex(0));
            compare(chat.currentSessionId, "c");
            var list = body.chatView.list;
            tryVerify(function() { return list.selectedIndex === 3; }, 3000, "the matching message is picked and shown");
            verify(chat.userScrolledUp, "the view stays at the message instead of following the end");
            screenshot(root, "chat-search-opened");
        }

        function test_3_narrow_popup_goes_back_to_the_chat() {
            root.width = 520;
            var p = search("cheap");
            verify(body.historyFull);
            compare(p.found.results[0].chatId, "d");
            compare(p.found.results[0].archived, true);
            tryVerify(function() { return p.resultList.itemAtIndex(0) !== null; });
            screenshot(root, "chat-search-narrow");
            mouseClick(p.resultList.itemAtIndex(0));
            compare(chat.currentSessionId, "d");
            verify(!chat.historyOnlyMode, "the history closes in a narrow popup");
            tryVerify(function() { return body.chatView.list.selectedIndex === 0; });
        }

        function test_4_keyboard() {
            body.forceActiveFocus();
            keyClick(Qt.Key_F, Qt.ControlModifier | Qt.ShiftModifier);
            tryVerify(function() { return chat.historyOnlyMode && body.sessionList && body.sessionList.search.field.activeFocus; },
                      2000, "Ctrl+Shift+F opens the history with the search field focused");
            var p = body.sessionList.search;
            keyClick("n");
            keyClick("a");
            keyClick("t");
            keyClick("a");
            tryVerify(function() { return p.query === "nata"; });
            keyClick(Qt.Key_Down);
            verify(p.resultList.activeFocus);
            compare(p.resultList.currentIndex, 0);
            keyClick(Qt.Key_Up);
            verify(p.field.activeFocus, "Up on the first result goes back to the field");
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(chat.currentSessionId, "b");
            // Esc clears the field.
            p.field.forceActiveFocus();
            keyClick(Qt.Key_Escape);
            compare(p.field.text, "");
        }

        function test_5_short_queries_and_nothing_found() {
            var p = search("x");
            compare(findChild(p, "searchStatus").text, "Type at least two characters.");
            p.field.text = "zebra";
            tryVerify(function() { return p.query === "zebra"; });
            compare(findChild(p, "searchStatus").text, "No chats match “zebra”.");
            compare(p.resultList.count, 0);
            // A chat that changes while the results show (a reply came in): they follow.
            chat.sessions = chat.sessions.concat([{value: "e", text: "Zoo", updatedAt: Date.now(), messages: messages("e", ["A zebra!"], Date.now())}]);
            tryVerify(function() { return p.resultList.count === 1; });
            compare(findChild(p, "searchStatus").text, "1 match");
        }
    }
}
