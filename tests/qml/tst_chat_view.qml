// chat/ChatView.qml: streaming, the scroll rule, and how each kind of message looks.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 640

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

    Chat.ChatView {
        id: view
        anchors.fill: parent
        chat: chat
    }

    HarnessTestCase {
        name: "ChatView"

        function conversation(n) {
            var msgs = [];
            for (var i = 0; i < n; i++) {
                msgs.push({role: "user", content: "Question number " + i + "?", time: "10:0" + (i % 10)});
                msgs.push({role: "assistant", model: "openrouter/auto", content: "Answer **" + i + "** with `code` and\n\n- a list\n- of items", time: "10:0" + (i % 10),
                           tokens: {input: 120, output: 40}});
            }
            return msgs;
        }

        function delegates() {
            var items = [];
            for (var i = 0; i < view.list.count; i++) items.push(view.list.itemAtIndex(i));
            return items;
        }

        function init() {
            chat.currentStreamIndex = -1;
            chat.currentStreamText = "";
            chat.userScrolledUp = false;
            chat.messages = [];
            chat.loading = false;
        }

        function test_1_streaming_updates_one_row_and_follows() {
            chat.messages = conversation(6).concat([{role: "user", content: "Write a long answer"}, {role: "assistant", content: "", model: "test"}]);
            chat.currentStreamIndex = chat.messages.length - 1;
            chat.loading = true;
            wait(50);
            var last = view.list.itemAtIndex(view.list.count - 1);
            for (var i = 0; i < 2000; i++) {
                chat.currentStreamText += "word" + i + (i % 12 === 11 ? "\n" : " ");
                if (i % 100 === 0) wait(5);
            }
            wait(100);
            verify(view.list.itemAtIndex(view.list.count - 1) === last, "the streaming row was not rebuilt");
            verify(view.list.atYEnd, "the view follows the stream");
            screenshot(root, "chat-view-streaming");
        }

        function test_2_scrolling_up_stays_put_while_streaming() {
            chat.messages = conversation(10).concat([{role: "assistant", content: "", model: "test"}]);
            chat.currentStreamIndex = chat.messages.length - 1;
            wait(50);
            view.list.positionViewAtEnd();
            mouseWheel(view.list, 100, 100, 0, 600);
            wait(20);
            verify(chat.userScrolledUp, "scrolling up stops following");
            var y = view.list.contentY;
            for (var i = 0; i < 300; i++) chat.currentStreamText += "more text " + i + "\n";
            wait(100);
            compare(view.list.contentY, y, "the user's place is kept");
            tryVerify(() => !view.list.builder.running, 2000, "the buttons are built");
            screenshot(root, "chat-view-scrolled-up");
            chat.scrollToBottom(true);
            wait(50);
            verify(view.list.atYEnd);
            verify(!chat.userScrolledUp);
        }

        function test_3_changing_one_message_keeps_the_others() {
            chat.messages = conversation(5);
            wait(50);
            var before = delegates();
            var copy = chat.messages.slice();
            copy[3] = Object.assign({}, copy[3], {content: "Edited answer"});
            copy.splice(0, 1);
            chat.messages = copy;
            wait(50);
            var after = delegates();
            for (var i = 0; i < after.length; i++)
                verify(after[i] === before[i + 1], "row " + i + " kept its delegate");
        }

        function test_4_states_screenshot() {
            chat.messages = [
                {role: "user", content: "Can you fix the failing test?", time: "09:41"},
                {role: "assistant", model: "Pi · qwen3:8b", time: "09:41", reasoning: "The test fails because…",
                 content: "Found it. The parser drops the last line:\n\n```python\nlines = text.split(\"\\n\")[:-1]\n```\n\nI changed it to keep every line.",
                 contextItems: ["✓ read: parser.py", "✓ edit: parser.py", "📝 parser.py"], tokens: {input: 2087, output: 95}},
                {role: "permission_request", model: "OpenCode", status: "pending", canAlways: true, permissionId: "p1",
                 content: "OpenCode asks for permission: **edit**"},
                {role: "question_request", model: "Pi", status: "pending", questionId: "q1", allowCustom: false,
                 questions: [{question: "Run the tests?", options: [{label: "Yes"}, {label: "No"}]}], content: "Pi is asking"},
                {role: "error", content: "OpenRouter: HTTP 402: requires more credits.", time: "09:42"},
                {role: "user", content: "Here's the log", time: "09:43", attachments: [{type: "file", name: "build.log", path: "/tmp/build.log"}]}
            ];
            wait(100);
            chat.scrollToBottom(true);
            wait(50);
            tryVerify(() => !view.list.builder.running, 2000, "the buttons are built");
            screenshot(root, "chat-view-states");
            chat.userScrolledUp = true;  // as main.qml's jumps do
            view.list.positionViewAtBeginning();
            wait(50);
            tryVerify(() => !view.list.builder.running, 2000, "the buttons are built");
            screenshot(root, "chat-view-states-top");
        }
    }
}
