// chat/ToolCard.qml and the activity list: tool name, input summary, status
// and expandable output, built from the events the agents really send.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/backends/AgentEvents.js" as AgentEvents
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

    FakeChat { id: chat; openCodeMode: true }  // these are OpenCode replies: they keep the Context list

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    Chat.ToolCard {
        id: card
        x: 10
        y: 10
        width: 400
    }

    Chat.ChatView {
        id: view
        x: 0
        y: 150
        width: parent.width
        height: parent.height - 150
        chat: chat
    }

    HarnessTestCase {
        name: "ToolCard"

        // A reply built from agent events, as main.qml stores it.
        function reply() {
            var r = {role: "assistant", model: "OpenCode", content: "I fixed the off-by-one.", time: "10:10"};
            AgentEvents.applyToReply(r, {type: "tool_start", callId: "c1", name: "read", input: {filePath: "src/parser.py"}});
            AgentEvents.applyToReply(r, {type: "tool_end", callId: "c1", output: "def parse_line(s):\n    return s.split(',')", isError: false});
            AgentEvents.applyToReply(r, {type: "tool_start", callId: "c2", name: "bash", input: {command: "pytest -q"}});
            AgentEvents.applyToReply(r, {type: "tool_end", callId: "c2", output: "1 failed, 12 passed", isError: true});
            AgentEvents.applyToReply(r, {type: "tool_start", callId: "c3", name: "edit", input: {filePath: "src/parser.py"}});
            AgentEvents.applyToReply(r, {type: "file_changed", path: "src/parser.py"});
            return r;
        }

        function init() {
            chat.calls = [];
            chat.messages = [];
            card.expanded = false;
        }

        function test_1_name_summary_and_status() {
            card.tool = {name: "bash", detail: "pytest -q", status: "running", input: "{\"command\":\"pytest -q\"}", output: ""};
            compare(findChild(card, "toolDetail").text, "pytest -q");
            verify(findChild(card, "toolRunning").visible, "a running tool shows a busy indicator");
            verify(!findChild(card, "toolStatusIcon").visible);
            compare(card.running, true);
            card.tool = {name: "bash", detail: "pytest -q", status: "done", input: "{}", output: "12 passed"};
            verify(!findChild(card, "toolRunning").visible);
            compare(String(findChild(card, "toolStatusIcon").source), "dialog-ok-apply");
            card.tool = {name: "bash", detail: "pytest -q", status: "error", input: "{}", output: "boom"};
            compare(String(findChild(card, "toolStatusIcon").source), "dialog-error");
            compare(card.failed, true);
        }

        function test_2_output_is_one_click_away() {
            card.tool = {name: "bash", detail: "pytest -q", status: "done", input: "{\"command\":\"pytest -q\"}", output: "12 passed in 0.4s"};
            verify(!findChild(card, "toolOutput"), "collapsed: no output built");
            mouseClick(findChild(card, "toolHead"));
            var output = findChild(card, "toolOutput");
            verify(output && output.visible);
            compare(output.text, "12 passed in 0.4s");
            compare(findChild(card, "toolInput").text, "{\n  \"command\": \"pytest -q\"\n}");
            screenshot(root, "tool-card-expanded");
            mouseClick(findChild(card, "toolHead"));
            verify(!findChild(card, "toolOutput"), "collapsed again");
        }

        function test_3_a_tool_without_output_has_nothing_to_open() {
            card.tool = {name: "read", detail: "a.py", status: "running", input: "{}", output: ""};
            verify(!findChild(card, "toolHead").enabled);
        }

        function test_4_the_activity_line_summarises_and_opens_to_tool_cards() {
            chat.messages = [{role: "user", content: "Fix the parser", time: "10:09"}, reply()];
            wait(100);
            var delegate = view.list.itemAtIndex(1);
            var summary = findChild(delegate, "contextSummary");
            verify(summary, "the activity line");
            verify(findChild(delegate, "toolHead") === null, "collapsed: no tool cards yet");
            mouseClick(summary);
            wait(50);
            var heads = findChildren(delegate, "toolHead");
            compare(heads.length, 3);
            screenshot(root, "tool-card-activity");
            mouseClick(heads[1]);
            compare(findChild(delegate, "toolOutput").text, "1 failed, 12 passed");
        }

        function test_5_summary_counts_failed_and_running() {
            var ctx = Qt.createQmlObject('import QtQuick; import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat; Chat.ContextList {}', root);
            var r = reply();
            ctx.items = r.contextItems;
            ctx.tools = r.tools;
            ctx.files = r.filesChanged;
            compare(ctx.stepCount, 4, "3 tools and 1 changed file");
            compare(ctx.failedCount, 1);
            compare(ctx.runningCount, 1);
            ctx.destroy();
        }

        function test_6_older_chats_with_only_summary_lines_still_list_them() {
            chat.messages = [{role: "assistant", model: "OpenCode", content: "Done", contextItems: ["read src/a.py", "edit src/a.py"]}];
            wait(100);
            var delegate = view.list.itemAtIndex(0);
            mouseClick(findChild(delegate, "contextSummary"));
            wait(50);
            compare(findChildren(delegate, "toolHead").length, 0);
        }
    }
}
