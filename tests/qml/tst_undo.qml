// chat/UndoNotice.qml: Undo after clearing a chat or deleting one, for a
// few seconds.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 200

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

    Chat.UndoNotice {
        id: notice
        chat: chat
        anchors.centerIn: parent
        timeout: 5000
    }

    HarnessTestCase {
        name: "Undo"

        readonly property var two: [{role: "user", content: "Hi"}, {role: "assistant", content: "Hello"}]
        readonly property var three: [{value: "a", text: "Trip planning", messages: []},
                                      {value: "b", text: "Shell tips", messages: [{role: "user", content: "ls"}]},
                                      {value: "c", text: "Old chat", messages: []}]

        function init() {
            notice.dismiss();
            notice.timeout = 5000;
            chat.calls = [];
            chat.currentSessionId = "a";
            chat.messages = [];
            chat.sessions = [];
            notice.dismiss();
            wait(20);
        }

        function test_1_clearing_a_chat_can_be_undone() {
            chat.messages = two;
            verify(!notice.visible, "nothing to undo yet");
            chat.messages = [];
            verify(notice.visible);
            compare(findChild(notice, "undoText").text, "Chat cleared");
            screenshot(root, "undo-clear");
            mouseClick(findChild(notice, "undoButton"));
            compare(chat.messages.length, 2);
            compare(chat.messages[1].content, "Hello");
            verify(!notice.visible, "the notice goes after undoing");
        }

        function test_2_deleting_the_only_message_can_be_undone() {
            chat.messages = [two[0]];
            chat.messages = [];
            compare(findChild(notice, "undoText").text, "Message deleted");
            notice.undo();
            compare(chat.messages.length, 1);
        }

        function test_3_switching_to_an_empty_chat_is_not_a_clear() {
            chat.messages = two;
            chat.currentSessionId = "b";
            chat.messages = [];
            verify(!notice.visible);
            chat.messages = [{role: "user", content: "x"}];
            chat.currentSessionId = "a";
            chat.messages = [];
            verify(!notice.visible, "a new chat starting empty is not a clear");
        }

        function test_4_undo_is_gone_after_the_timeout() {
            notice.timeout = 100;
            chat.messages = two;
            chat.messages = [];
            verify(notice.visible);
            tryVerify(() => !notice.visible, 2000);
            notice.undo();
            compare(chat.messages.length, 0, "nothing comes back after it is gone");
        }

        function test_5_undo_does_not_overwrite_what_was_typed_since() {
            chat.messages = two;
            chat.messages = [];
            chat.messages = [{role: "user", content: "new"}];
            notice.undo();
            compare(chat.messages.length, 1);
            compare(chat.messages[0].content, "new");
        }

        function test_6_deleting_a_chat_can_be_undone() {
            chat.sessions = three;
            chat.deleteSession("b");
            compare(chat.sessions.length, 2);
            verify(notice.visible);
            compare(findChild(notice, "undoText").text, "Chat “Shell tips” deleted");
            screenshot(root, "undo-delete");
            mouseClick(findChild(notice, "undoButton"));
            compare(chat.sessions.map(function(s) { return s.value; }), ["a", "b", "c"], "back where it was");
            compare(chat.sessions[1].messages.length, 1, "with its messages");
            verify(chat.calls.some(function(c) { return c.name === "persist"; }), "saved");
            verify(!chat.calls.some(function(c) { return c.name === "switch"; }), "not the open chat: stays on the current one");
        }

        function test_7_undoing_the_delete_of_the_open_chat_opens_it_again() {
            chat.sessions = three;
            chat.currentSessionId = "b";
            chat.deleteSession("b");
            notice.undo();
            var switched = chat.calls.filter(function(c) { return c.name === "switch"; });
            compare(switched.length, 1);
            compare(switched[0].args[0], "b");
        }

        function test_8_the_close_button_has_a_name() {
            chat.messages = two;
            chat.messages = [];
            var buttons = [];
            for (var i = 0; i < findChild(notice, "undoText").parent.children.length; i++)
                buttons.push(findChild(notice, "undoText").parent.children[i]);
            verify(buttons.some(function(b) { return b.Accessible && b.Accessible.name === "Dismiss"; }));
        }

        function test_9_regenerating_can_be_undone() {
            var before = [{role: "user", content: "Q1"}, {role: "assistant", content: "A1"}, {role: "user", content: "Q2"}];
            chat.messages = before;
            chat.messages = before.slice(0, 1);
            chat.messagesDropped("a", before);
            verify(notice.visible);
            compare(findChild(notice, "undoText").text, "2 messages removed");
            chat.calls = [];
            mouseClick(findChild(notice, "undoButton"));
            compare(chat.messages, before);
            compare(chat.calls[0].name, "stop", "the new answer is stopped first");
            verify(!notice.visible);
        }

        function test_a_undoing_a_regenerate_is_for_the_same_chat_only() {
            var before = [{role: "user", content: "Q1"}, {role: "assistant", content: "A1"}];
            chat.messages = before.slice(0, 1);
            chat.messagesDropped("a", before);
            chat.currentSessionId = "b";
            chat.messages = [{role: "user", content: "other"}];
            notice.undo();
            compare(chat.messages.length, 1);
            compare(chat.messages[0].content, "other");
        }
    }
}
