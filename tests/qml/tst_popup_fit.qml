// Nothing in the chat popup reaches past its right edge, at any width down
// to the widget's minimum: the header's last button, the composer's Send
// button and the composer itself stay inside, for a normal and an incognito
// chat and a very long title. Laid out as FullRepresentationContent.qml does.
import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 640
    height: 700

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
        id: column
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Kirigami.Units.smallSpacing

        Chat.ChatHeader { id: header; chat: chat }

        Chat.ChatBody {
            id: body
            chat: chat
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    HarnessTestCase {
        name: "PopupFit"

        // The widget's minimum width (main.qml fullRepresentation).
        readonly property int minimumWidth: 500

        function rightEdge(item) {
            return item.mapToItem(root, item.width, 0).x;
        }

        function check(width, tag) {
            root.width = width;
            wait(120);
            var send = findChild(root, "sendButton");
            var more = findChild(root, "moreButton");
            var composer = findChild(root, "composer");
            verify(more !== null && send !== null, tag + ": found the buttons");
            verify(rightEdge(more) <= width + 0.5, tag + ": the More button is inside (" + rightEdge(more) + " of " + width + ")");
            verify(rightEdge(send) <= width + 0.5, tag + ": Send is inside (" + rightEdge(send) + " of " + width + ")");
            if (composer)
                verify(rightEdge(composer) <= width + 0.5, tag + ": the composer is inside (" + rightEdge(composer) + ")");
            verify(rightEdge(header) <= width + 0.5, tag + ": the header is inside (" + rightEdge(header) + ")");
            verify(rightEdge(body) <= width + 0.5, tag + ": the body is inside (" + rightEdge(body) + ")");
            screenshot(root, "popup-fit-" + tag);
        }

        function init() {
            chat.messages = [];
            chat.currentSessionTitle = "New Chat";
            chat.currentSessionId = "a";
        }

        function test_1_normal() {
            check(640, "normal-640");
            check(560, "normal-560");
            check(minimumWidth, "normal-min");
        }

        function test_2_long_title() {
            chat.currentSessionTitle = "A very long chat title that keeps going and going well past any header";
            check(640, "long-640");
            check(minimumWidth, "long-min");
        }

        function test_3_incognito() {
            chat.currentSessionId = chat.incognito.makeId();
            check(640, "incognito-640");
            check(560, "incognito-560");
            check(minimumWidth, "incognito-min");
        }

        function test_4_incognito_long_title() {
            chat.currentSessionId = chat.incognito.makeId();
            chat.currentSessionTitle = "A very long chat title that keeps going and going well past any header";
            check(640, "incognito-long-640");
            check(minimumWidth, "incognito-long-min");
        }

        // Content that has no good break: a long word typed, a long link or
        // path in a reply, a wide code line, a long file name; recording on
        // and a reply running (the Stop button joins the row).
        function test_5_wide_content() {
            var wide = "https://example.com/" + "averyveryverylongpathsegment".repeat(8);
            chat.messages = [
                {role: "user", content: wide, time: "10:01"},
                {role: "assistant", model: "a-very-long-model-name/with-a-long-variant-name-v2", content: wide + "\n\n```\n" + "x".repeat(200) + "\n```\n\n| a | b |\n|---|---|\n| " + "y".repeat(120) + " | z |", time: "10:01"}
            ];
            chat.chatInputText = wide;
            chat.attachedFiles = [{name: "a-very-long-file-name-for-a-report-final-v3-copy.pdf", type: "document", path: "", content: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", loading: false, error: ""}];
            chat.sttEnabled = true;
            chat.loading = true;
            check(640, "wide-640");
            check(minimumWidth, "wide-min");
            chat.currentSessionId = chat.incognito.makeId();
            check(minimumWidth, "wide-incognito-min");
            chat.loading = false;
            chat.sttEnabled = false;
            chat.attachedFiles = [];
            chat.chatInputText = "";
        }
    }
}
