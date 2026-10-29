// A reply never makes the chat view load a picture by itself (audit 1.4.0, S1/S2): every Markdown
// image form and raw HTML <img> is rendered through the real chat/MessageBody.qml, and an agent's
// tool name and detail through chat/ToolCard.qml, while a loopback server (count_server.py)
// remembers each request it gets. Two plain Markdown TextEdits show the server does see Qt's fetches.
import QtQuick
import QtTest
import org.kde.plasma.plasma5support 2.0 as P5Support
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 600
    height: 900

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    function fileOf(relative) {
        return decodeURIComponent(String(Qt.resolvedUrl(relative)).replace(/^file:\/\//, ""));
    }

    property int port: 0
    readonly property string base: "http://127.0.0.1:" + port

    // Each variant fetches /v<n>... if Qt loads it.
    readonly property var variants: port === 0 ? [] : [
        "![a](" + base + "/v1 'single title')",
        "![a](<" + base + "/v2 with space>)",
        "![a][r]\n\n[r]: " + base + "/v3",
        "![a][]\n\n[a]: " + base + "/v4",
        "![r]\n\n[r]: " + base + "/v5",
        "![a](" + base + "/v6 (paren title))",
        "![a](" + base + "/v7_(x))",
        "<img src=\"" + base + "/v8\">",
        "text <img src=" + base + "/v9> inline",
        "<div>\n<img src=\"" + base + "/v10\">\n</div>",
        "\\\\![a](" + base + "/v11)",
        "\\`![a](" + base + "/v12)\\`",
        "`a\n\n![a](" + base + "/v13)\n\n`",
        "| a | b |\n|---|---|\n| `x | ![a](" + base + "/v14) | y` |",
        "<table background=\"" + base + "/v15\"><tr><td>x</td></tr></table>",
        "![a](" + base + "/v16 \"title\")",
        "[![a](" + base + "/v17)](https://kde.org)",
        "<p style=\"background-image:url(" + base + "/v18)\">x</p>",
        "- item\n\n    ![a](" + base + "/v19)",
        "![A][Ref Label]\n\n[ref   label]: <" + base + "/v20> \"t\""
    ]

    P5Support.DataSource {
        id: server
        engine: "executable"
        connectedSources: []
        property bool stopped: false
        onNewData: function(sourceName) { disconnectSource(sourceName); stopped = true; }
    }

    FakeChat { id: chat }

    Rectangle {
        anchors.fill: parent
        color: "white"
    }

    Column {
        id: column
        width: 560
        Repeater {
            model: root.variants
            delegate: Chat.MessageBody {
                required property string modelData
                width: column.width
                chat: chat
                text: modelData
            }
        }
        Chat.ToolCard {
            id: card
            width: 400
        }
        Chat.SenderName {
            id: sender
            chat: chat
            role: "assistant"
            maximumWidth: 400
        }
    }

    // Controls: plain Markdown TextEdits (as MessageText.qml renders), so the test sees that Qt does
    // fetch a Markdown image and an HTML background by itself.
    TextEdit {
        id: controlMarkdown
        y: 860
        textFormat: Text.MarkdownText
    }
    TextEdit {
        id: controlHtml
        x: 300
        y: 860
        textFormat: Text.MarkdownText
    }

    HarnessTestCase {
        name: "NoRemoteImages"
        when: windowShown

        function get(path) {
            var out = null;
            var xhr = new XMLHttpRequest();
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE)
                    out = {"status": xhr.status, "text": xhr.responseText};
            };
            xhr.open("GET", root.base + path);
            xhr.send();
            tryVerify(function() { return out !== null; }, 5000, "no answer for " + path);
            return out;
        }

        function requests() {
            return JSON.parse(get("/requests").text);
        }

        function initTestCase() {
            for (var attempt = 0; attempt < 5 && root.port === 0; attempt++) {
                var port = 20000 + Math.floor(Math.random() * 40000);
                server.connectSource("python3 -I '" + root.fileOf("count_server.py") + "' " + port);
                root.port = port;
                var up = false;
                for (var i = 0; i < 40 && !up; i++) {
                    wait(50);
                    up = get("/ping").status === 200;
                }
                if (!up)
                    root.port = 0;
            }
            verify(root.port !== 0, "the counting server started");
        }

        function cleanupTestCase() {
            if (root.port !== 0)
                get("/quit");
            tryVerify(function() { return server.stopped; }, 5000, "the counting server stopped");
        }

        function test_nothing_is_fetched() {
            card.tool = {"name": "<img src=\"" + root.base + "/tool-name\">", "status": "done",
                         "detail": "<img src=\"" + root.base + "/tool-detail\">", "output": ""};
            sender.model = "<img src=\"" + root.base + "/sender-model\">";
            verify(findChildren(column, "messageText").length >= root.variants.length, "every variant is rendered");
            controlMarkdown.text = "![c](" + root.base + "/control-markdown)";
            controlHtml.text = "<table background=\"" + root.base + "/control-html\"><tr><td>x</td></tr></table>";
            tryVerify(function() {
                var seen = requests();
                return seen.indexOf("/control-markdown") >= 0 && seen.indexOf("/control-html") >= 0;
            }, 10000, "Qt fetched the control images (the test can see a fetch)");
            wait(1000);
            var leaked = requests().filter(function(p) { return p.indexOf("/control-") !== 0; });
            compare(leaked, [], "the chat view fetched nothing by itself");
            screenshot(root, "no-remote-images");
        }

        function test_agent_strings_show_markup_literally() {
            card.tool = {"name": "<b>bash</b>", "status": "done", "detail": "<img src=\"" + root.base + "/x\">", "output": ""};
            sender.model = "<i>model</i>";
            var labels = [findChild(card, "toolName"), findChild(card, "toolDetail"), findChild(sender, "senderModel")];
            compare(labels.map(function(l) { return l.text; }), ["<b>bash</b>", "<img src=\"" + root.base + "/x\">", "<i>model</i>"]);
            labels.forEach(function(l) { compare(l.textFormat, Text.PlainText, l.objectName); });
        }
    }
}
