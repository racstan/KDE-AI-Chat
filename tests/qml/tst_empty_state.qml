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
            chat.sessions = [];
            chat.currentSessionId = "a";
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
            compare(list.length, 6, "two templates, then built-in suggestions");
            compare(list[0].text, "Fix code");
            compare(list[1].text, "Summarise");
            screenshot(root, "empty-state-templates");
            mouseClick(list[1]);
            compare(chat.chatInputText, "Summarise the following:\n");
        }

        function test_5_without_templates_there_are_six_suggestions_that_fill_the_input() {
            compare(chips().length, 6);
            mouseClick(chips()[0]);
            verify(chat.chatInputText !== "", "a suggestion fills the input");
            compare(chat.calls.filter(c => c[0] === "send").length, 0, "and is never sent by itself");
            screenshot(root, "empty-state-suggestions");
        }

        function test_6_at_most_six_chips_and_templates_never_crowd_out_the_rest() {
            var many = [];
            for (var i = 0; i < 10; i++)
                many.push({name: "T" + i, prompt: "p" + i});
            chat.promptTemplates = many;
            wait(50);
            var list = chips();
            compare(list.length, 6);
            compare(list.filter(c => /^T\d$/.test(c.text)).length, 3);
        }

        function test_6b_agent_modes_get_project_tasks() {
            chat.piMode = true;
            wait(50);
            var all = ["Explain this project", "Find and fix a bug", "Write tests", "Summarise recent changes",
                       "Review my changes", "Find the TODOs", "Refactor", "Write documentation",
                       "Check dependencies", "How do I run it?", "What should I do first?", "Wrap up today's work"];
            var list = chips();
            compare(list.length, 6);
            for (var i = 0; i < list.length; i++)
                verify(all.indexOf(list[i].text) >= 0, "agent chip: " + list[i].text);
            screenshot(root, "empty-state-agent");
        }

        function test_6c_a_chat_keeps_its_chips_and_the_next_one_differs() {
            var names = () => chips().map(c => c.text).join("|");
            var first = names();
            wait(50);
            compare(names(), first, "stable while the chat is open");
            var differs = false;
            for (var i = 0; i < 6 && !differs; i++) {
                chat.currentSessionId = "other-" + i;
                wait(30);
                differs = names() !== first;
            }
            verify(differs, "another chat gets other suggestions");
            chat.currentSessionId = "a";
        }

        function test_6d_continue_chip_switches_to_the_latest_other_chat() {
            chat.currentSessionId = "a";
            chat.sessions = [{value: "a", text: "Trip planning", updatedAt: 9},
                             {value: "b", text: "Tax questions", updatedAt: 5},
                             {value: "c", text: "Old", updatedAt: 1}];
            wait(50);
            var list = chips();
            compare(list.length, 6);
            compare(list[0].text, "Continue: Tax questions");
            screenshot(root, "empty-state-continue");
            mouseClick(list[0]);
            compare(chat.currentSessionId, "b");
            compare(chat.chatInputText, "", "switching does not fill the input");
            chat.currentSessionId = "a";
            chat.sessions = [];
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
