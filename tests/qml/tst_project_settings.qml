// A project's settings reach its chats: instructions in the system prompt
// (direct, OpenCode) and for Pi, the working folder for OpenCode and Pi, the
// model for direct chats. The Chat info panel says what comes from the
// project, and a chat's mode never changes because of one.
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui" as Ui
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 760
    height: 700

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat {
        id: chat
        plasmoid: ({configuration: config})
        // What DirectRequest and the agent modes read besides FakeChat's API.
        property string compiledSystemPrompt: "Main instructions."
        function buildEffectiveSystemPrompt(id) { return direct.buildEffectiveSystemPrompt(id); }
        function buildMessageContent(text) { return text; }
    }

    // An object, as plasmoid.configuration is (chat/ModeSync.qml listens to it).
    QtObject {
        id: config
        property string provider: "openai"
        property bool perChatModelSettings: false
        property bool enableSystemPrompt: true
        property string providersJson: JSON.stringify([
            {id: "openai", name: "OpenAI", type: "openai-compat", baseUrl: "", model: "gpt-4o"},
            {id: "nvidia", name: "NVIDIA NIM", type: "openai-compat", baseUrl: "", model: "nemotron"}
        ])
    }

    Chat.DirectRequest { id: direct; chat: chat }
    Chat.PiMode { id: pi; chat: chat }
    Chat.OpenCodeMode { id: openCode; chat: chat }
    Chat.ModeSync { id: sync; chat: chat }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    Chat.WorkspaceBar {
        id: bar
        chat: chat
        width: 400
    }

    Ui.ChatSettingsDialog {
        id: dialog
        rootRef: chat
        hostItem: root
    }

    HarnessTestCase {
        name: "ProjectSettings"

        function init() {
            dialog.close();
            chat.plasmoid = {configuration: config};
            chat.projects.list = [{id: "p-work", name: "Work", color: "#1cdc9a", instructions: "Answer in French.",
                                   folder: "/srv/work", provider: "nvidia", model: "nvidia/nemotron-3.5-bolt-e4b"}];
            chat.currentSessionId = "a";
            chat.currentSessionTitle = "Report";
            chat.messages = [];
            chat.sessions = [
                {value: "a", text: "Report", source: "provider", projectId: "p-work", chatSystemPrompt: "Be brief."},
                {value: "o", text: "Agent", source: "opencode", projectId: "p-work"},
                {value: "p", text: "Pi chat", source: "pi", projectId: "p-work"},
                {value: "own", text: "Own folder", source: "pi", projectId: "p-work", openCodeWorkspaceCwd: "/home/me/own"},
                {value: "none", text: "Loose", source: "provider"}
            ];
        }

        function test_instructions_go_between_the_main_and_the_chats_own() {
            var prompt = direct.buildEffectiveSystemPrompt("a");
            verify(prompt.indexOf("Main instructions.") === 0, prompt);
            verify(prompt.indexOf("--- Project instructions (Work) ---\nAnswer in French.") > 0, prompt);
            verify(prompt.indexOf("Answer in French.") < prompt.indexOf("Be brief."), "the chat's own come last");
            compare(direct.buildEffectiveSystemPrompt("none"), "Main instructions.", "no project: unchanged");
            // OpenCode sends the same system prompt; Pi gets the project's and the chat's own.
            verify(direct.buildEffectiveSystemPrompt("o").indexOf("Answer in French.") > 0);
            var body = pi.promptBody("p", {content: "hi"});
            compare(body.instructions, "--- Project instructions (Work) ---\nAnswer in French.\n--- End project instructions ---");
        }

        function test_opencode_and_pi_run_in_the_project_folder() {
            compare(openCode.openCodeTarget("o").directory, "/srv/work");
            compare(pi.promptBody("p", {content: "hi"}).directory, "/srv/work");
            compare(pi.promptBody("own", {content: "hi"}).directory, "/home/me/own", "the chat's own folder wins");
            chat.modeSync = sync;
            chat.currentSessionId = "p";
            sync.applyOpenChat();
            compare(chat.openCodeWorkspaceCwd, "/srv/work");
            compare(chat.piMode, true, "still a Pi chat");
            chat.currentSessionId = "a";
            sync.applyOpenChat();
            compare(chat.piMode, false);
            compare(chat.openCodeMode, false, "a direct chat stays direct");
            chat.modeSync = null;
        }

        function test_direct_chats_use_the_project_model() {
            var eff = chat.effectiveConfig("a");
            compare(eff.mode, "provider");
            compare(eff.provider, "nvidia");
            compare(eff.model, "nvidia/nemotron-3.5-bolt-e4b");
            compare(eff.source, "project");
            compare(chat.effectiveConfig("o").mode, "opencode", "a project never changes the mode");
            compare(chat.effectiveConfig("none").provider, "openai");
        }

        function test_workspace_bar_names_the_project_and_its_folder() {
            chat.currentSessionId = "p";
            chat.openCodeWorkspaceCwd = "/srv/work";
            var label = findChild(bar, "workspaceProject");
            verify(label.visible);
            compare(label.text, "Work (folder from the project)");
            verify(!findChild(bar, "workspaceClear").visible, "the project's folder is changed in the project");
            chat.currentSessionId = "own";
            chat.openCodeWorkspaceCwd = "/home/me/own";
            compare(label.text, "Work");
            verify(findChild(bar, "workspaceClear").visible);
            chat.currentSessionId = "none";
            chat.openCodeWorkspaceCwd = "";
            verify(!label.visible);
            chat.currentSessionId = "a";
        }

        function test_chat_info_says_what_comes_from_the_project() {
            dialog.openForSession("a");
            tryVerify(() => dialog.visible);
            var source = findChild(dialog, "effectiveSource");
            compare(source.text, "From the project “Work”");
            compare(findChild(dialog, "effectiveLine").text, "Direct · NVIDIA NIM · nvidia/nemotron-3.5-bolt-e4b");
            var name = findChild(dialog, "projectName");
            verify(name.visible);
            compare(name.text, "In the project “Work”");
            compare(findChild(dialog, "projectInstructionsLine").text, "Instructions: the project's, then this chat's own");
            compare(findChild(dialog, "projectFolderLine").text, "Working folder: /srv/work (from the project)");
            screenshot(root, "chat-info-project");
            // A chat in no project shows none of it.
            chat.currentSessionId = "none";
            dialog.openForSession("none");
            tryVerify(() => !findChild(dialog, "projectName").visible);
            compare(findChild(dialog, "effectiveSource").text, "From main settings");
        }
    }
}
