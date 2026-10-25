// Design-review mockups: the real chat components in each chat-view state,
// saved as build/qml-screens/mockup-<state>-<light|dark>.png at a realistic
// popup size.
//
// Nothing here sets a colour. tests/test_qml.py runs this file once per
// colour scheme (Breeze Light, Breeze Dark) with KDE's platform theme reading
// that scheme from a temporary kdeglobals, which is how Plasma itself gives
// Kirigami.Theme and the controls their colours. The file name says which
// scheme was really in effect (read from Kirigami.Theme), not which was asked
// for. Not named tst_*, so the main QML suite doesn't run it.
import QtQuick
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui" as Ui

Item {
    id: root
    width: 760
    height: 700

    readonly property bool dark: popup.Kirigami.Theme.backgroundColor.hslLightness < 0.5
    readonly property string themeName: dark ? "dark" : "light"

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat { id: chat }

    Item {
        id: popup
        anchors.fill: parent

        // Stands in for the Plasma popup's own background.
        Rectangle {
            anchors.fill: parent
            color: Kirigami.Theme.backgroundColor
        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            anchors.rightMargin: infoPanel.visible ? infoPanel.width + Kirigami.Units.smallSpacing : Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Chat.ChatHeader { id: header; chat: chat; appName: "KDE AI Chat"; historyFull: body.historyFull }
            Chat.RenameRow { chat: chat; historyFull: body.historyFull }

            // As in FullRepresentationContent: the history beside the chat in a wide popup.
            Chat.ChatBody {
                id: body
                chat: chat
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        Ui.ChatSettingsDialog {
            id: infoPanel
            rootRef: chat
            hostItem: popup
        }
    }

    readonly property var view: body.chatView
    readonly property var composer: body.composerItem

    HarnessTestCase {
        name: "Mockups"

        readonly property var markdownReply: "Here is a plan for **Lisbon** in May:\n\n"
            + "## Itinerary\n\n- Day 1: Alfama and the *miradouros*\n- Day 2: Belem and the `pastel de nata` queue\n- Day 3: day trip to Sintra\n\n"
            + "To list the sights from a script:\n\n```python\nsights = [\"Alfama\", \"Belem\", \"Sintra\"]\nfor s in sights:\n    print(s.upper())\n```\n\n"
            + "1. Book Sintra tickets early\n2. Take the 28 tram before 9am\n\nSee [the guide](https://example.com) for more."

        // The composer chip loads an Image for every attachment (even non-images),
        // so give each a real 1x1 PNG to keep the log free of "Cannot open" warnings.
        readonly property string tinyPng: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

        function reset() {
            chat.currentStreamIndex = -1;
            chat.currentStreamText = "";
            chat.currentStreamReasoning = "";
            chat.currentStreamExtractedReasoning = "";
            chat.loading = false;
            chat.streamingResponse = false;
            chat.userScrolledUp = false;
            chat.historyOnlyMode = false;
            chat.attachedFiles = [];
            chat.chatInputText = "";
            chat.messages = [];
            chat.sessions = [];
            infoPanel.close();
        }

        // Builds the state, waits for layout, saves the shot.
        function shoot(state, setup) {
            reset();
            setup();
            wait(150);
            var name = "mockup-" + state + "-" + root.themeName;
            var path = screenshot(root, name);
            verify(path.indexOf(name + ".png") > 0);
        }

        function lightness(c) {
            return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
        }

        // The composer's text box and the popup are both light or both dark
        // (the old custom palette left the box white in a dark popup).
        function test_00_composer_matches_the_scheme() {
            reset();
            wait(100);
            var input = composer.input;
            var img = grabImage(input);
            // Inside the frame, below the placeholder text.
            var inside = img.pixel(img.width - Kirigami.Units.largeSpacing * 2, img.height - Kirigami.Units.largeSpacing);
            console.log("MOCKUP theme", root.themeName, "background", popup.Kirigami.Theme.backgroundColor, "input", inside, "link", popup.Kirigami.Theme.linkColor);
            compare(lightness(inside) < 0.5, root.dark, "composer box " + inside + " in a " + root.themeName + " popup");
        }

        function findFirst(item, predicate) {
            if (predicate(item)) return item;
            var kids = item.children || [];
            for (var i = 0; i < kids.length; i++) {
                var found = findFirst(kids[i], predicate);
                if (found) return found;
            }
            return null;
        }

        function test_01_empty() {
            shoot("empty", function() {});
            compare(view.list.count, 0);
        }

        function test_02_conversation() {
            shoot("conversation", function() {
                chat.messages = [
                    {role: "user", content: "Where should we go in May? Somewhere warm, not too crowded.", time: "10:01"},
                    {role: "assistant", model: "openrouter/auto", content: markdownReply, time: "10:01", tokens: {input: 30, output: 212}},
                    {role: "user", content: "Great, thanks. Can you make it 4 days?", time: "10:03"},
                    {role: "assistant", model: "openrouter/auto", content: "Sure, add a **beach day** at Cascais.", time: "10:03", tokens: {input: 260, output: 14}}
                ];
            });
            verify(view.list.count >= 4);
        }

        function test_03_streaming() {
            shoot("streaming", function() {
                chat.messages = [
                    {role: "user", content: "Write a short poem about the sea.", time: "10:05"},
                    {role: "assistant", content: "", model: "openrouter/auto"}
                ];
                chat.currentStreamIndex = 1;
                chat.currentStreamText = "The tide comes in with **quiet** hands,\nand writes its name on silver sands;\nthe gulls";
                chat.loading = true;
                chat.streamingResponse = true;
            });
        }

        function test_04_reasoning() {
            shoot("reasoning", function() {
                chat.messages = [
                    {role: "user", content: "Is 391 prime?", time: "10:07"},
                    {role: "assistant", model: "deepseek/deepseek-r1", time: "10:07",
                     reasoning: "I need to check divisibility. sqrt(391) is about 19.8.\nTry 17: 17 * 23 = 391. So it is divisible by 17.",
                     content: "No. **391 = 17 x 23**, so it is not prime."}
                ];
                wait(100);
                var block = findFirst(view, function(i) { return i.hasOwnProperty("expanded") && i.hasOwnProperty("streaming"); });
                if (block) block.expanded = true;
            });
        }

        function test_05_tool_context() {
            shoot("tool-context", function() {
                chat.messages = [
                    {role: "user", content: "Fix the failing test in the parser.", time: "10:10"},
                    {role: "assistant", model: "OpenCode", time: "10:10",
                     contextItems: ["read src/parser.py", "read tests/test_parser.py", "edit src/parser.py", "bash pytest -q"],
                     content: "I fixed the off-by-one in `parse_line` and the tests pass."}
                ];
            });
        }

        function test_06_permission_and_question() {
            shoot("permission-question", function() {
                chat.messages = [
                    {role: "user", content: "Clean up the build folder.", time: "10:12"},
                    {role: "permission_request", model: "OpenCode", status: "pending", canAlways: true, permissionId: "p1",
                     content: "Run command: rm -rf build/"},
                    {role: "question_request", model: "OpenCode", status: "pending", questionId: "q1", allowCustom: true,
                     content: "Which folders should I keep?",
                     questions: [{header: "Which folders should I keep?", multiple: true,
                                  options: [{label: "build/cache", description: "Compiler cache"}, {label: "build/docs"}, {label: "None"}]}]}
                ];
            });
        }

        function test_07_error() {
            shoot("error", function() {
                chat.messages = [
                    {role: "user", content: "Hello?", time: "10:15"},
                    {role: "error", content: "Request failed: 401 Unauthorized. The API key for OpenRouter looks invalid or expired.", time: "10:15"}
                ];
            });
        }

        function test_08_history() {
            shoot("history", function() {
                chat.messages = [
                    {role: "user", content: "Where should we go in May? Somewhere warm, not too crowded.", time: "10:01"},
                    {role: "assistant", model: "openrouter/auto", content: "Somewhere **warm**:\n\n- Lisbon\n- Valencia", time: "10:01", tokens: {input: 30, output: 12}}
                ];
                var now = Date.now();
                chat.sessions = [
                    {value: "a", text: "Trip planning", count: 4, updatedAt: now},
                    {value: "b", text: "OpenCode refactor", source: "opencode", count: 14, updatedAt: now - 86400000},
                    {value: "c", text: "Shell one-liners", source: "pi", count: 9, updatedAt: now - 5 * 86400000},
                    {value: "d", text: "Old chat", archived: true, count: 3, updatedAt: now - 40 * 86400000}
                ];
                chat.historyOnlyMode = true;
            });
            verify(body.sideHistory && !body.historyFull, "the history sits beside the chat in a wide popup");
        }

        function test_10_chat_info() {
            shoot("chat-info", function() {
                var created = Date.now() - 5 * 86400000;
                chat.plasmoid = {configuration: {provider: "openrouter", providersJson: JSON.stringify([
                    {id: "openrouter", name: "OpenRouter", type: "openai-compat", baseUrl: "", model: "openrouter/auto"},
                    {id: "ollama", name: "Ollama", type: "openai-compat", baseUrl: "", model: "llama3"}])}};
                chat.messages = [
                    {role: "user", content: "Where should we go in May? Somewhere warm, not too crowded.", time: "10:01", at: created},
                    {role: "assistant", model: "openrouter/auto", content: markdownReply, time: "10:01", at: created + 1000, tokens: {input: 30, output: 212}, cost: 0.00132},
                    {role: "user", content: "Great, thanks. Can you make it 4 days?", time: "10:03", at: created + 2000},
                    {role: "assistant", model: "anthropic/claude-sonnet-4.5", content: "Sure, add a **beach day** at Cascais.", time: "10:03", at: created + 3000, tokens: {input: 1260, output: 14}, cost: 0.00471}
                ];
                chat.sessions = [{value: "a", text: "Trip planning", createdAt: created, updatedAt: Date.now(), chatModel: "openrouter/auto",
                                  chatSystemPromptEnabled: true, chatSystemPrompt: "You are a concise travel planner.", responseLength: 2}];
                infoPanel.toggleForSession("a");
                // The fake provider has no server to list models from; don't show that failure.
                wait(60);
                infoPanel.draft.invalidate();
            });
            verify(infoPanel.visible);
        }

        function test_09_attachments() {
            shoot("attachments", function() {
                chat.messages = [{role: "assistant", model: "openrouter/auto", content: "Send me the files and I will summarise them.", time: "10:20"}];
                chat.attachedFiles = [
                    {name: "report-2026-Q3.pdf", type: "document", error: "", loading: false, content: tinyPng},
                    {name: "notes.txt", type: "text", error: "", loading: false, content: tinyPng},
                    {name: "huge-archive-with-a-very-long-name.docx", type: "document", error: "Could not read this file", loading: false, content: tinyPng},
                    {name: "scan.png", type: "image", error: "", loading: true, content: tinyPng, mimeType: "image/png"}
                ];
                chat.chatInputText = "Summarise these, please";
            });
        }
    }
}
