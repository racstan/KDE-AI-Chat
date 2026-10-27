// The empty chat: who you are talking to, a hint, and starting points from
// the prompt templates.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 480

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
        name: "EmptyState"

        function init() {
            chat.calls = [];
            chat.messages = [];
            chat.chatInputText = "";
            chat.openCodeMode = false;
            chat.piMode = false;
            chat.providerId = "openrouter";
            chat.providerModel = "openrouter/auto";
            chat.providerBaseUrl = "https://openrouter.ai/api/v1";
            chat.promptTemplates = [];
            wait(50);
        }

        function chips() { return findChildren(view, "starterChip"); }

        function test_1_names_the_model_and_says_where_it_runs() {
            compare(findChild(view, "emptyTitle").text, "Chat with openrouter/auto");
            var line = findChild(view, "emptyProvider").text;
            verify(line.indexOf("OpenRouter") === 0, line);
            verify(line.indexOf("sent to its servers") > 0, "a remote provider says your messages leave the computer: " + line);
            screenshot(root, "empty-state-remote");
        }

        function test_2_a_local_model_says_it_stays_here() {
            chat.providerId = "ollama";
            chat.providerModel = "qwen3:8b";
            chat.providerBaseUrl = "http://localhost:11434/v1";
            wait(50);
            compare(findChild(view, "emptyTitle").text, "Chat with qwen3:8b");
            verify(findChild(view, "emptyProvider").text.indexOf("runs on this computer") > 0);
        }

        function test_3_agent_modes_are_named() {
            chat.openCodeMode = true;
            wait(50);
            compare(findChild(view, "emptyProvider").text, "OpenCode agent · runs here, sends your messages to its model");
        }

        function test_4_templates_are_the_chips_and_a_click_fills_the_input() {
            chat.promptTemplates = [{name: "Fix code", prompt: "Fix this code:\n"}, {name: "Summarise", prompt: "Summarise the following:\n"}];
            wait(50);
            var list = chips();
            compare(list.length, 2);
            compare(list[0].text, "Fix code");
            compare(list[1].text, "Summarise");
            screenshot(root, "empty-state-templates");
            mouseClick(list[1]);
            compare(chat.chatInputText, "Summarise the following:\n");
        }

        function test_5_without_templates_there_are_a_few_examples() {
            compare(chips().length, 3);
            mouseClick(chips()[0]);
            verify(chat.chatInputText !== "", "an example fills the input");
        }

        function test_6_at_most_six_chips() {
            var many = [];
            for (var i = 0; i < 10; i++)
                many.push({name: "T" + i, prompt: "p" + i});
            chat.promptTemplates = many;
            wait(50);
            compare(chips().length, 6);
        }

        function test_7_gone_as_soon_as_there_is_a_message() {
            verify(findChild(view, "emptyTitle"));
            chat.messages = [{role: "user", content: "Hi", time: "10:00"}];
            wait(50);
            verify(!findChild(view, "emptyTitle"), "no guidance next to a conversation");
            chat.messages = [];
            wait(50);
            verify(findChild(view, "emptyTitle"));
        }

        function test_8_chips_have_accessible_names() {
            verify(chips()[0].Accessible.name !== "");
        }
    }
}
