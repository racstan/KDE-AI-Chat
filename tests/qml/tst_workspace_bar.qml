// The workspace row under the header (chat/WorkspaceBar.qml), in every mode:
// "No workspace" by default, pick and clear, the default for new chats, the
// attach dialog starting in the workspace, and what each mode sends when a
// chat has none. Also: resizing the popup across widths must not make the
// layouts rearrange recursively ("Detected recursive rearrange").
import QtQuick
import QtQuick.Layouts
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 300

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    QtObject {
        id: cfg
        property bool useOpenCode: false
        property bool usePi: false
        property bool perChatModelSettings: false
        property string perChatPriority: "chat"
        property string provider: "openai"
        property string openCodeAgent: "build"
        property string openCodeWorkspaceCwd: ""
        property string openCodeProvider: "opencode"
        property string openCodeModel: "zen-x"
        property string piProvider: "ollama"
        property string piModel: "qwen"
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

    Chat.OpenCodeMode { id: openCode; chat: chat }
    Chat.PiMode { id: pi; chat: chat }

    Chat.AttachDialog {
        id: attach
        chat: chat
    }

    ColumnLayout {
        anchors.fill: parent

        Chat.WorkspaceBar {
            id: bar
            chat: chat
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }

    HarnessTestCase {
        name: "WorkspaceBar"

        function init() {
            cfg.openCodeWorkspaceCwd = "";
            chat.sessions = [
                {value: "p", text: "Direct", source: "provider", messages: []},
                {value: "o", text: "OpenCode", source: "opencode", messages: []},
                {value: "x", text: "Pi", source: "pi", messages: []}
            ];
            chat.calls = [];
            root.width = 520;
            open("p");
        }

        function open(id) {
            chat.currentSessionId = id;
            sync.apply(chat.sessions[chat.sessionIndexById(id)]);
        }

        function session(id) { return chat.sessions[chat.sessionIndexById(id)]; }
        function label() { return findChild(bar, "workspaceLabel"); }
        function button() { return findChild(bar, "workspaceButton"); }
        function clearButton() { return findChild(bar, "workspaceClear"); }

        function agentCombo() {
            for (var i = 0; i < bar.children.length; i++) {
                if (bar.children[i].textRole === "text")
                    return bar.children[i];
            }
            return null;
        }

        function test_resize_does_not_loop() {
            open("o");
            chat.openCodeWorkspaceCwd = "/home/user/some/rather/long/project-folder-name";
            chat.openCodeAgentsList = [{text: "build", value: "build"}, {text: "plan", value: "plan"}];
            failOnWarning(/recursive rearrange/);
            for (var w = 700; w >= 180; w -= 13) {
                root.width = w;
                wait(10);
            }
            for (w = 180; w <= 700; w += 17) {
                root.width = w;
                wait(10);
            }
            verify(bar.visible);
            verify(bar.width <= root.width);
        }

        function test_picker_shows_in_every_mode_agent_controls_only_in_opencode() {
            for (const m of [["p", false], ["o", true], ["x", false]]) {
                open(m[0]);
                verify(bar.visible, m[0]);
                verify(button().visible, m[0]);
                verify(label().visible, m[0]);
                compare(agentCombo().visible, m[1], "agent selector in " + m[0]);
            }
        }

        function test_no_workspace_by_default() {
            for (const id of ["p", "o", "x"]) {
                open(id);
                compare(label().text.indexOf("No workspace"), 0, id);
                verify(!clearButton().visible, id);
            }
        }

        function test_a_chat_with_no_folder_never_falls_back_to_the_main_setting() {
            cfg.openCodeWorkspaceCwd = "/work/default";
            open("p");
            compare(chat.openCodeWorkspaceCwd, "");
            compare(label().text, "No workspace");
        }

        function test_pick_and_clear() {
            open("p");
            bar.choose("/home/me/project");
            compare(session("p").openCodeWorkspaceCwd, "/home/me/project");
            compare(chat.openCodeWorkspaceCwd, "/home/me/project");
            compare(label().text, "project");
            verify(clearButton().visible);
            // Another chat is not affected.
            open("x");
            compare(label().text, "No workspace");
            open("p");
            compare(label().text, "project");
            mouseClick(clearButton());
            compare(session("p").openCodeWorkspaceCwd, "");
            compare(label().text, "No workspace");
            verify(!clearButton().visible);
        }

        function test_new_chats_get_the_default_setting() {
            compare(sync.newChatWorkspace(), "");
            cfg.openCodeWorkspaceCwd = "  /work/default ";
            compare(sync.newChatWorkspace(), "/work/default");
            // A chat created with it opens in that workspace; an old chat keeps its own.
            chat.sessions = [{value: "n", text: "New", source: "provider", messages: [], openCodeWorkspaceCwd: sync.newChatWorkspace()}].concat(chat.sessions);
            open("n");
            compare(label().text, "default");
            cfg.openCodeWorkspaceCwd = "/work/other";
            open("n");
            compare(chat.openCodeWorkspaceCwd, "/work/default");
        }

        function test_attach_dialog_starts_in_the_workspace() {
            open("p");
            var usual = String(attach.currentFolder);
            attach.prepare();
            compare(String(attach.currentFolder), usual, "no workspace: the dialog's usual folder");
            bar.choose("/tmp/my_project");
            attach.prepare();
            compare(String(attach.currentFolder), "file:///tmp/my_project");
        }

        function test_opencode_sends_no_directory_without_a_workspace() {
            open("o");
            compare(openCode.openCodeTarget("o").directory, "");
            bar.choose("/work/oc");
            compare(openCode.openCodeTarget("o").directory, "/work/oc");
            bar.choose("");
            compare(openCode.openCodeTarget("o").directory, "");
        }

        function test_pi_sends_no_directory_without_a_workspace() {
            open("x");
            compare(pi.promptBody("x", {content: "hi"}).directory, "");
            bar.choose("/work/pi");
            compare(pi.promptBody("x", {content: "hi"}).directory, "/work/pi");
        }

        function test_screenshots() {
            root.width = 560;
            open("p");
            wait(50);
            screenshot(bar, "workspace-bar-direct-none");
            bar.choose("/home/me/projects/notes");
            wait(50);
            screenshot(bar, "workspace-bar-direct");
            open("o");
            chat.openCodeAgentsList = [{text: "build", value: "build"}, {text: "plan", value: "plan"}];
            bar.choose("/home/me/projects/app");
            wait(50);
            screenshot(bar, "workspace-bar-opencode");
        }
    }
}
