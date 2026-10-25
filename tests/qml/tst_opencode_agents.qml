// OpenCode agent selection (chat/OpenCodeBar.qml, chat/OpenCodeMode.qml,
// chat/ModeSync.qml): the selector shows the agent the chat really sends
// with, a picked agent sticks to the chat it was picked in, loading or
// failing to load the list never changes the chat's agent, and the list is
// reloaded for the chat's own workspace folder.
import QtQuick
import QtQuick.Layouts
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 560
    height: 120

    function i18n(text) { return text; }

    // plasmoid.configuration: a real QObject so the settings emit change signals.
    QtObject {
        id: cfg
        property bool useOpenCode: true
        property bool usePi: false
        property bool perChatModelSettings: false
        property string perChatPriority: "chat"
        property string provider: "openai"
        property string openCodeAgent: "build"
        property string openCodeWorkspaceCwd: "/work/main"
        property string openCodeProvider: "opencode"
        property string openCodeModel: "zen-x"
    }

    FakeChat {
        id: chat
        plasmoid: ({configuration: cfg})
        modeSync: sync
    }

    Chat.ModeSync {
        id: sync
        chat: chat
    }

    Chat.OpenCodeMode {
        id: openCode
        chat: chat
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        Chat.OpenCodeBar {
            id: bar
            chat: chat
            onAgentChosen: function(value) { openCode.chooseAgent(value); }
        }
        Item { Layout.fillHeight: true }
    }

    HarnessTestCase {
        name: "OpenCodeAgents"

        readonly property var agents: [{text: "build", value: "build"}, {text: "plan", value: "plan"}, {text: "go", value: "go"}]

        function combo() {
            for (var i = 0; i < bar.children.length; i++) {
                if (bar.children[i].textRole === "text")
                    return bar.children[i];
            }
            return null;
        }

        function open(id) {
            chat.currentSessionId = id;
            sync.apply(chat.sessions[chat.sessionIndexById(id)]);
        }

        function session(id) {
            return chat.sessions[chat.sessionIndexById(id)];
        }

        function init() {
            cfg.perChatModelSettings = false;
            cfg.perChatPriority = "chat";
            cfg.openCodeAgent = "build";
            cfg.openCodeWorkspaceCwd = "/work/main";
            chat.sessions = [
                {value: "a", text: "Own agent", source: "opencode", messages: [], ownModel: true, openCodeAgent: "plan"},
                {value: "b", text: "Main agent", source: "opencode", messages: []},
                {value: "c", text: "Own folder", source: "opencode", messages: [], openCodeWorkspaceCwd: "/work/c"}
            ];
            chat.openCodeAgentsList = agents;
            chat.openCodeAgentsDirectory = "/work/main";
            open("b");
        }

        function test_selector_shows_the_agent_the_chat_sends_with() {
            cfg.perChatModelSettings = true;
            open("a");
            compare(chat.openCodeAgent, "plan");
            compare(chat.effectiveConfig("a").agent, "plan");
            compare(combo().currentText, "plan");
            // A reloaded list never changes the chat's agent (it used to be
            // reset to the server's default or the first agent listed).
            chat.openCodeAgentsList = [{text: "build", value: "build"}, {text: "go", value: "go"}];
            compare(chat.openCodeAgent, "plan");
            compare(combo().currentText, "plan (not on server)");
            chat.openCodeAgentsList = [];
            compare(combo().currentText, "plan");
        }

        function test_picked_agent_sticks_to_its_chat() {
            cfg.perChatModelSettings = true;
            open("a");
            combo().activated(2);       // "go"
            compare(session("a").openCodeAgent, "go");
            compare(cfg.openCodeAgent, "build", "the main agent (other chats) is untouched");
            compare(chat.effectiveConfig("a").agent, "go", "the chat sends with the picked agent");
            compare(combo().currentText, "go");
            open("b");
            compare(chat.openCodeAgent, "build");
            compare(combo().currentText, "build");
            open("a");
            compare(chat.openCodeAgent, "go", "still the chat's agent after switching back");
            compare(combo().currentText, "go");
        }

        function test_picked_agent_without_own_settings_is_the_main_one() {
            open("b");
            combo().activated(1);       // "plan"
            compare(cfg.openCodeAgent, "plan");
            verify(session("b").openCodeAgent === undefined);
            compare(chat.effectiveConfig("b").agent, "plan");
            compare(combo().currentText, "plan");
        }

        function test_list_is_reloaded_for_the_chats_folder() {
            var before = chat.agentFetches;
            open("b");
            compare(chat.agentFetches, before, "the list is for this folder already");
            open("c");
            compare(chat.openCodeWorkspaceCwd, "/work/c");
            compare(chat.agentFetches, before + 1, "another folder: its own agents");
            chat.openCodeAgentsDirectory = "/work/c";
            open("c");
            compare(chat.agentFetches, before + 1);
        }

        function test_failed_load_keeps_the_list_and_answers() {
            var answered = false;
            openCode.fetchAgents(function() { answered = true; });
            tryVerify(function() { return answered; }, 5000);
            compare(chat.openCodeAgentsList, agents, "an unreachable server keeps the list there was");
            compare(chat.openCodeAgent, "build");
            verify(!chat.fetchingAgentsInProgress);
        }

        function test_picked_folder_goes_where_the_chat_takes_it_from() {
            open("c");
            openCode.chooseWorkspace("/work/new-c");
            compare(session("c").openCodeWorkspaceCwd, "/work/new-c");
            compare(cfg.openCodeWorkspaceCwd, "/work/main");
            compare(chat.openCodeWorkspaceCwd, "/work/new-c");
            open("b");
            openCode.chooseWorkspace("/work/other");
            compare(cfg.openCodeWorkspaceCwd, "/work/other");
            compare(chat.openCodeWorkspaceCwd, "/work/other");
        }

        // The delay the backend reopens a lost event stream with.
        function test_later_runs_once_after_the_delay() {
            var runs = 0;
            openCode.later(function() { runs++; }, 30);
            compare(runs, 0);
            tryVerify(function() { return runs === 1; }, 2000);
            wait(80);
            compare(runs, 1);
        }

        function test_screenshot() {
            chat.openCodeMode = true;
            cfg.perChatModelSettings = true;
            open("a");
            wait(50);
            screenshot(root, "opencode-agents-bar");
        }
    }
}
