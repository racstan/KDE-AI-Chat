// The activity box: one box per direct or Pi reply for the thinking and the
// steps, in the order they happened. The real chat/ReplyEvents.qml records the
// events, the real chat/ThinkingSlot.qml and ActivityBox.qml show them. Checks
// the order, the live status while streaming, the summary once done, a message
// saved before the activity list, and that OpenCode keeps its own block.
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 460
    height: 520

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    QtObject {
        id: chat
        property var messages: []
        property string currentStreamKey: ""
        property int currentStreamIndex: -1
        property string currentStreamText: ""
        property string currentStreamReasoning: ""
        property string currentStreamExtractedReasoning: ""
        property bool streamingResponse: false
        property bool loading: false
        property bool openCodeMode: false
        property var currentStreamUsage: ({})
        property string currentSessionId: "s1"
        property string currentSessionTitle: "t"
        property var activeXhr: null
        property int requestGeneration: 0
        property string activeRequestSessionId: ""
        property var streamBuffer: Chat.StreamBuffer { target: chat; maxChars: 2000000 }
        property var imageStore: QtObject {
            function hasImages(message) { return false; }
            function takeInlineImages(sessionId, reply) { return reply; }
        }
        function applyBackendEvent(e, m, x) { replies.applyBackendEvent(e, m, x); }
        function saveCurrentSessionState(t) {}
        function pushErrorMessage(t) {}
        function triggerNotificationSound() {}
        function maybeGenerateChatTitle() {}
        function processNextQueuedMessage() {}
        function resetProviderStreamingState() { replies.resetProviderStreamingState(); }
    }

    Chat.ReplyEvents {
        id: replies
        chat: chat
        notifierRef: QtObject { function replyFinished() {} }
    }

    readonly property var current: (chat.currentStreamIndex >= 0 ? chat.messages[chat.currentStreamIndex] : chat.messages[chat.messages.length - 1]) || ({})

    Rectangle { anchors.fill: parent; color: "white" }

    Column {
        width: parent.width - 20
        x: 10
        y: 10
        spacing: 10

        Chat.ThinkingSlot {
            id: slot
            objectName: "slot"
            width: parent.width
            chat: chat
            message: root.current
            streaming: chat.currentStreamIndex >= 0
        }

        // A message saved before the activity list.
        Chat.ThinkingSlot {
            id: oldSlot
            objectName: "oldSlot"
            width: parent.width
            chat: chat
            message: ({"role": "assistant", "reasoning": "Old thinking.", "content": "x",
                       "tools": {"t1": {"name": "read_file", "detail": "a.txt", "status": "done", "input": "{}", "output": "ok"}},
                       "contextItems": ["✓ read_file: a.txt"]})
        }
    }

    HarnessTestCase {
        name: "ActivityBox"

        function init() {
            chat.openCodeMode = false;
            chat.messages = [{"id": "u1", "role": "user", "content": "hi", "at": 1}];
            chat.currentStreamIndex = -1;
            chat.currentStreamKey = "";
            chat.currentStreamText = "";
            chat.currentStreamReasoning = "";
        }

        function box() { return findChild(slot, "activitySummary"); }
        function summaryText() { return findChild(slot, "activityText").text; }

        function test_1_streams_thinking_a_step_and_text_in_order() {
            chat.applyBackendEvent({"type": "reasoning_delta", "delta": "First I look at the file."}, "m");
            wait(60);
            verify(box(), "the box shows as soon as thinking starts");
            compare(summaryText(), "Thinking…");
            chat.applyBackendEvent({"type": "tool_start", "callId": "c1", "name": "read_file", "input": {"path": "a.txt"}}, "m");
            compare(summaryText(), "Running read_file… · 1 step");
            screenshot(root, "activity-running");
            chat.applyBackendEvent({"type": "tool_end", "callId": "c1", "output": "42", "isError": false}, "m");
            chat.applyBackendEvent({"type": "reasoning_delta", "delta": "Now I answer."}, "m");
            wait(60);
            compare(summaryText(), "Thinking… · 1 step");
            chat.applyBackendEvent({"type": "text_delta", "delta": "The answer is 42."}, "m");
            wait(60);
            compare(summaryText(), "Writing… · 1 step");

            // Opened while streaming: the live thinking is at the end.
            box().clicked();
            wait(60);
            var thinkingTexts = [];
            var message = chat.messages[chat.currentStreamIndex];
            compare(message.activity.map(function(a) { return a.kind; }).join(","), "thinking,tool");
            verify(slot.item.expanded);
            verify(slot.item.liveText === "Now I answer.", "live tail: " + slot.item.liveText);
            // A delta while open grows the tail without touching the list.
            var before = slot.item.list;
            chat.applyBackendEvent({"type": "reasoning_delta", "delta": " More."}, "m");
            wait(60);
            compare(slot.item.liveText, "Now I answer. More.");
            verify(slot.item.list === before, "the list is not rebuilt per delta");
            screenshot(root, "activity-streaming-open");

            chat.applyBackendEvent({"type": "done", "reason": "complete"}, "m");
            wait(60);
            var done = chat.messages[chat.messages.length - 1];
            compare(done.activity.map(function(a) { return a.kind; }).join(","), "thinking,tool,thinking");
            compare(done.activity[2].text, "Now I answer. More.");
            verify(done.reasoning === "First I look at the file.Now I answer. More.", "reasoning kept for old readers");
            compare(done.content, "The answer is 42.");
        }

        function test_2_collapsed_summary_when_done() {
            chat.applyBackendEvent({"type": "reasoning_delta", "delta": "Thinking about it."}, "m");
            wait(40);
            replies.thinkStart = Date.now() - 12000;
            replies.thinkEnd = Date.now();
            chat.applyBackendEvent({"type": "tool_start", "callId": "a", "name": "grep", "input": {"pattern": "x"}}, "m");
            chat.applyBackendEvent({"type": "tool_end", "callId": "a", "output": "boom", "isError": true}, "m");
            chat.applyBackendEvent({"type": "tool_start", "callId": "b", "name": "read_file", "input": {"path": "b"}}, "m");
            chat.applyBackendEvent({"type": "tool_end", "callId": "b", "output": "ok", "isError": false}, "m");
            chat.applyBackendEvent({"type": "notice", "level": "info", "message": "Took a while"}, "m");
            chat.applyBackendEvent({"type": "text_delta", "delta": "Done."}, "m");
            chat.applyBackendEvent({"type": "done", "reason": "complete"}, "m");
            wait(60);
            compare(summaryText(), "Thought for 12 s · 3 steps · 1 failed");
            verify(!slot.item.expanded, "collapsed once the reply is finished");
            compare(slot.item.list.map(function(i) { return i.kind; }).join(","), "thinking,tool,tool,notice");
            box().clicked();
            wait(60);
            verify(slot.item.expanded);
            screenshot(root, "activity-done-open");
            box().clicked();
            wait(30);
            screenshot(root, "activity-done-collapsed");
        }

        function test_3_old_message_shows_in_the_same_box() {
            var box2 = findChild(oldSlot, "activitySummary");
            verify(box2, "the old message gets the box");
            compare(findChild(oldSlot, "activityText").text, "Thought · 1 step");
            box2.clicked();
            wait(60);
            compare(oldSlot.item.list.map(function(i) { return i.kind; }).join(","), "thinking,tool");
            screenshot(root, "activity-old-message");
            box2.clicked();
        }

        function test_4_the_header_is_keyboard_and_screen_reader_friendly() {
            chat.applyBackendEvent({"type": "tool_start", "callId": "k", "name": "bash", "input": {"command": "ls"}}, "m");
            chat.applyBackendEvent({"type": "tool_end", "callId": "k", "output": "", "isError": false}, "m");
            chat.applyBackendEvent({"type": "text_delta", "delta": "ok"}, "m");
            chat.applyBackendEvent({"type": "done", "reason": "complete"}, "m");
            wait(60);
            var b = box();
            verify(b.activeFocus === false);
            b.forceActiveFocus(Qt.TabFocusReason);
            verify(b.activeFocus);
            compare(b.Accessible.name, "Show activity: 1 step");
            keyClick(Qt.Key_Space);
            verify(slot.item.expanded, "Space opens it");
            compare(b.Accessible.name, "Hide activity: 1 step");
            keyClick(Qt.Key_Return);
            verify(!slot.item.expanded, "Return closes it");
        }

        function test_5_opencode_keeps_its_own_block() {
            chat.openCodeMode = true;
            chat.applyBackendEvent({"type": "reasoning_delta", "delta": "Thinking in OpenCode."}, "m");
            wait(60);
            verify(slot.active, "OpenCode thinking shows");
            compare(findChild(slot, "activitySummary"), null);
            verify(chat.messages[chat.currentStreamIndex].activity === undefined, "no activity list for OpenCode replies");
            chat.applyBackendEvent({"type": "done", "reason": "complete"}, "m");
        }
    }
}
