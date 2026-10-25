// How a reply looks while it streams: no raw Markdown markers, the spinner
// and status next to the name, no action buttons.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 360

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
        name: "StreamingUi"

        // Every text drawn under `item` (Text, TextEdit, Label: they wrap) that has the word in it.
        function textsWith(item, word, into) {
            if (item.text !== undefined && item.wrapMode !== undefined && String(item.text).indexOf(word) >= 0 && item.visible)
                into.push(String(item.text));
            for (var i = 0; i < item.children.length; i++)
                textsWith(item.children[i], word, into);
            return into;
        }

        function init() {
            chat.messages = [{role: "user", content: "Write a poem", time: "10:00"}, {role: "assistant", model: "m", content: ""}];
            chat.currentStreamIndex = 1;
            chat.currentStreamText = "";
            chat.loading = true;
            wait(50);
        }

        function cleanup() {
            chat.loading = false;
            chat.currentStreamIndex = -1;
            chat.currentStreamText = "";
        }

        function test_1_no_markdown_markers_while_streaming() {
            chat.currentStreamText = "## The sea\n\nThe tide comes in with **quiet** hands,\nand *writes* its name on silver sands;\nthe **gu";
            wait(100);
            var shown = textsWith(view.list.itemAtIndex(1), "tide", []);
            verify(shown.length > 0, "the streamed text is shown");
            for (var i = 0; i < shown.length; i++) {
                verify(shown[i].indexOf("**") < 0, "no ** in: " + shown[i]);
                verify(shown[i].indexOf("quiet hands") > 0);
                verify(shown[i].indexOf("*writes*") < 0, "no *italic* markers");
                verify(shown[i].indexOf("##") < 0, "no heading marks");
                verify(shown[i].indexOf("the gu") > 0, "the unfinished bold marker is hidden too");
            }
            screenshot(root, "streaming-no-markers");
        }

        function test_2_the_spinner_and_status_sit_next_to_the_name() {
            var delegate = view.list.itemAtIndex(1);
            var spinner = findChild(delegate, "streamSpinner");
            var status = findChild(delegate, "streamStatus");
            verify(spinner && spinner.visible);
            compare(status.text, "Thinking…");
            verify(spinner.mapToItem(delegate, 0, 0).x < delegate.width / 3, "near the left, by the name");
            chat.currentStreamText = "Hello";
            compare(status.text, "Writing…");
        }

        function test_3_the_spinner_goes_when_done() {
            var delegate = view.list.itemAtIndex(1);
            chat.currentStreamIndex = -1;
            chat.loading = false;
            wait(50);
            verify(!findChild(delegate, "streamSpinner"));
        }
    }
}
