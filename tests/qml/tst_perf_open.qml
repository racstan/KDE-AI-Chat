// Performance budget: opening the chat view on a 500-message chat.
//
// What is measured ("open"): from creating chat/ChatView.qml, with the
// chat's 500 messages already in chat.messageModel (as when the popup opens:
// the model lives in main.qml), until the first frame is swapped at which
// the list has laid out at the end (atYEnd, last delegate created and inside
// the viewport). That includes creating the visible and cached delegates,
// Markdown and code-block layout, positioning at the end, and rendering.
//
// Also measured ("switch"): with the view open on another chat, assigning a
// different 500-message chat to chat.messages until the same settled frame
// (MessageModel.sync replacing the rows, plus the above).
//
// The messages' tool buttons are built after that frame, a few per frame
// (chat/DeferredBuilder.qml); the time until all are built is printed too,
// and the layout must not move when they appear.
//
// Budget: 150 ms each. Numbers are printed as "PERF ..." lines.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "PerfChat.js" as Perf

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

    Component {
        id: viewComponent
        Chat.ChatView {
            anchors.fill: parent
        }
    }

    // Time of the first frame at which `settledCheck()` held.
    property var settledCheck: null
    property real settledAt: 0
    property int framesUntilSettled: 0

    Connections {
        target: root.Window.window
        function onFrameSwapped() {
            if (!root.settledCheck || root.settledAt > 0)
                return;
            root.framesUntilSettled++;
            if (root.settledCheck())
                root.settledAt = Date.now();
        }
    }

    HarnessTestCase {
        id: test
        name: "PerfOpen"

        readonly property int budgetMs: 150
        property var view: null

        function settled() {
            if (!view) return false;
            var list = view.list;
            var last = list.itemAtIndex(list.count - 1);
            return list.count === chat.messageModel.count && list.atYEnd && last !== null
                && last.y + last.height <= list.contentY + list.height + 1 && last.height > 0;
        }

        // Runs `action` and returns ms until the first settled frame.
        function timeUntilSettledFrame(action) {
            root.settledAt = 0;
            root.framesUntilSettled = 0;
            root.settledCheck = settled;
            var start = Date.now();
            action();
            tryVerify(() => root.settledAt > 0, 5000, "the view settles at the end");
            root.settledCheck = null;
            return root.settledAt - start;
        }

        function cleanup() {
            if (view) view.destroy();
            view = null;
            wait(20);
        }

        function test_open_500_messages() {
            var syncStart = Date.now();
            chat.messages = Perf.conversation(500);
            var syncMs = Date.now() - syncStart;
            compare(chat.messageModel.count, 500);
            wait(50);

            var runs = [];
            var buttons = [];
            for (var r = 0; r < 3; r++) {
                var start = Date.now();
                runs.push(timeUntilSettledFrame(function() {
                    test.view = viewComponent.createObject(root, {"chat": chat});
                }));
                var list = view.list;
                var last = list.itemAtIndex(list.count - 1);
                var lastY = last.y;
                var contentY = list.contentY;
                tryVerify(() => !list.builder.running, 5000, "the buttons are built");
                buttons.push(Date.now() - start);
                compare(last.y, lastY, "the last message didn't move when its buttons appeared");
                compare(list.contentY, contentY, "the view didn't move when the buttons appeared");
                verify(list.atYEnd);
                if (r === 0) screenshot(root, "perf-open-500");
                cleanup();
            }
            // The first run pays one-off costs (type compilation, glyph
            // caches); a popup opened again behaves like the later runs.
            console.log("PERF open 500 messages: first " + runs[0] + " ms, then " + runs.slice(1).join(", ")
                        + " ms (frames until settled: " + root.framesUntilSettled + "); model load " + syncMs + " ms; all buttons built after "
                        + buttons.join(", ") + " ms");
            // The budget applies to the best of the later runs (a busy CI
            // machine slows single runs). The first is allowed more for the
            // one-off costs, and still catches the list not settling (before
            // these optimisations it never did with this chat: the delegates
            // were rebuilt over and over while their heights settled).
            verify(Math.min(runs[1], runs[2]) < budgetMs, "open took " + runs.join(", ") + " ms (budget " + budgetMs + ")");
            verify(runs[0] < budgetMs * 2.5, "first open took " + runs[0] + " ms (allowed " + budgetMs * 2.5 + ")");
        }

        function test_switch_to_500_message_chat() {
            chat.messages = Perf.conversation(20);
            view = viewComponent.createObject(root, {"chat": chat});
            tryVerify(settled, 5000);
            var other = Perf.conversation(500).map(function(m) { return Object.assign({}, m, {"id": "x" + m.id}); });
            var ms = timeUntilSettledFrame(function() { chat.messages = other; });
            console.log("PERF switch to 500-message chat: " + ms + " ms (frames until settled: " + root.framesUntilSettled + ")");
            verify(ms < budgetMs, "switching took " + ms + " ms (budget " + budgetMs + ")");
        }
    }
}
