// Settings → Personality in the chat: your name and the AI's name and avatar
// in the message headers (nothing set = the old look), the block at the start
// of a direct request only (not OpenCode, not Pi), and a chat's own switch
// to turn it off in its Chat info settings.
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui" as Ui
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 520

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    readonly property string picture: decodeURIComponent(String(Qt.resolvedUrl("../fixtures/avatar.png")).replace(/^file:\/\//, ""))
    readonly property var nobody: ({userName: "", userAvatar: "", userAbout: "", userTone: "", userLanguage: "", userNotes: "",
                                   aiName: "", aiPersonality: "", aiPersonalityCustom: "", aiAvatar: ""})

    function configWith(extra) {
        return {configuration: Object.assign({provider: "openai", enableSystemPrompt: true, perChatModelSettings: false,
            providersJson: JSON.stringify([{id: "openai", name: "OpenAI", type: "openai-compat", baseUrl: "", model: "gpt-4o"}])},
            nobody, extra || {})};
    }

    FakeChat {
        id: chat
        property string compiledSystemPrompt: "Main instructions."
        function buildEffectiveSystemPrompt(id) { return direct.buildEffectiveSystemPrompt(id); }
        function sessionMessages() { return [{role: "user", content: "Who am I?"}]; }
        // What OpenCodeMode.sendOpenCodePrompt touches.
        property var currentStreamUsage: ({})
        property var activeXhr: null
        property bool openCodeUseAgentModel: true
        function requestIsCurrent() { return false; }
        function applyBackendEvent() {}
        function setCurrentOpenCodeSessionId() {}
    }

    Chat.DirectRequest { id: direct; chat: chat }
    Chat.PiMode { id: pi; chat: chat }
    Chat.OpenCodeMode { id: openCode; chat: chat }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    Chat.ChatView {
        id: view
        anchors.fill: parent
        chat: chat
    }

    Ui.ChatSettingsDialog {
        id: dialog
        rootRef: chat
        hostItem: root
    }

    HarnessTestCase {
        name: "Personality"

        readonly property var conversation: [
            {role: "user", content: "Who are you?", time: "10:00"},
            {role: "assistant", model: "nemotron-3.5", content: "I'm your assistant.", time: "10:01"},
            {role: "user", content: "And who am I?", time: "10:02"},
            {role: "queued", content: "Later", time: "10:03"}]

        function init() {
            dialog.close();
            chat.calls = [];
            chat.currentSessionId = "a";
            chat.plasmoid = root.configWith({});
            chat.sessions = [{value: "a", text: "Names", source: "provider"}, {value: "o", text: "Agent", source: "opencode"},
                             {value: "p", text: "Pi", source: "pi"}];
            chat.messages = [];
            wait(10);
        }

        function header(i, name) {
            var delegate = view.list.itemAtIndex(i);
            verify(delegate, "delegate " + i);
            return findChild(delegate, name);
        }

        function test_1_nothing_set_looks_as_before() {
            chat.messages = conversation;
            wait(100);
            compare(header(0, "senderName").text, "You");
            compare(header(1, "senderName").text, "nemotron-3.5");
            verify(!header(1, "senderModel").visible, "the model is the name: not twice");
            verify(!header(1, "senderAvatar").visible, "no avatar");
            compare(header(3, "senderName").text, "You · queued");
        }

        function test_2_names_and_icon_avatar() {
            chat.plasmoid = root.configWith({userName: "Rachit", aiName: "Nova", aiAvatar: "face-smile"});
            chat.messages = conversation;
            wait(100);
            compare(header(0, "senderName").text, "Rachit");
            compare(header(1, "senderName").text, "Nova");
            verify(header(1, "senderModel").visible, "the model stays, small");
            compare(header(1, "senderModel").text, "nemotron-3.5");
            verify(header(1, "senderAvatar").visible);
            compare(String(header(1, "senderAvatar").source), "face-smile");
            verify(!header(0, "senderAvatar").visible, "no avatar of yours chosen: your messages show none");
            compare(header(3, "senderName").text, "Rachit · queued");
            screenshot(root, "personality-chat-icon");
        }

        function test_3_image_avatar_and_a_bad_one() {
            chat.plasmoid = root.configWith({aiName: "Nova", aiAvatar: root.picture});
            chat.messages = conversation;
            wait(150);
            verify(header(1, "senderAvatar").visible, "the picture shows");
            compare(String(header(1, "senderAvatar").source), "file://" + root.picture);
            screenshot(root, "personality-chat-image");
            chat.plasmoid = root.configWith({aiName: "Nova", aiAvatar: "/home/me/notes.txt"});
            wait(50);
            verify(!header(1, "senderAvatar").visible, "not an image file: no avatar");
            compare(header(1, "senderName").text, "Nova");
        }

        function test_3b_your_avatar_shows_on_your_messages() {
            chat.plasmoid = root.configWith({userName: "Rachit", userAvatar: "face-glasses", aiName: "Nova", aiAvatar: "face-smile"});
            chat.messages = conversation;
            wait(100);
            verify(header(0, "senderAvatar").visible, "your first message");
            compare(String(header(0, "senderAvatar").source), "face-glasses");
            verify(header(2, "senderAvatar").visible);
            verify(header(3, "senderAvatar").visible, "a queued message too");
            compare(String(header(1, "senderAvatar").source), "face-smile", "the AI keeps its own");
            screenshot(root, "personality-chat-user-icon");

            chat.plasmoid = root.configWith({userAvatar: root.picture});
            wait(150);
            compare(String(header(0, "senderAvatar").source), "file://" + root.picture);
            compare(header(0, "senderName").text, "You", "the name is unchanged");
            verify(!header(1, "senderAvatar").visible, "the AI has none");
            screenshot(root, "personality-chat-user-image");

            chat.plasmoid = root.configWith({userAvatar: "/home/me/notes.txt"});
            wait(50);
            verify(!header(0, "senderAvatar").visible, "not an image file: no avatar");
        }

        function test_4_direct_gets_the_block_first_opencode_and_pi_do_not() {
            compare(direct.buildDirectRequestParts("a", "openai").system, "Main instructions.", "nothing set: unchanged");
            chat.plasmoid = root.configWith({userName: "Rachit", aiName: "Nova", aiPersonality: "witty"});
            var system = direct.buildDirectRequestParts("a", "openai").system;
            verify(system.indexOf("## About the user\nName: Rachit\n\n## Your persona\nYour name is Nova.") === 0, system);
            verify(system.indexOf("\n\nMain instructions.") > 0, "the extra instructions come after it");
            // OpenCode sends buildEffectiveSystemPrompt; Pi its own instructions.
            compare(chat.buildEffectiveSystemPrompt("o"), "Main instructions.");
            var sent = [];
            var fakeXhr = function() {
                var x = {readyState: 0, status: 0, responseText: "", setRequestHeader: function() {}, abort: function() {}};
                x.open = function(method, url) { x.url = url; };
                x.send = function(body) { sent.push(String(body || "")); };
                return x;
            };
            openCode.sendOpenCodePrompt("o", 0, {"baseUrl": "http://127.0.0.1:1", "directory": "", "xhrFactory": fakeXhr});
            verify(sent.length > 0, "OpenCode sent a request");
            verify(sent.join("\n").indexOf("Rachit") < 0 && sent.join("\n").indexOf("Nova") < 0, sent.join("\n"));
            compare(pi.promptBody("p", {content: "hi"}).instructions, "");
            // The chat's own instructions off: personality stays (its own switch).
            chat.setSessionProperty("a", "chatSystemPromptEnabled", false);
            verify(direct.buildDirectRequestParts("a", "openai").system.indexOf("Your name is Nova.") > 0);
            chat.setSessionProperty("a", "chatSystemPromptEnabled", true);
            chat.setSessionProperty("a", "personalityOff", true);
            compare(direct.buildDirectRequestParts("a", "openai").system, "Main instructions.", "off for this chat");
        }

        function test_5_a_chat_turns_it_off_in_its_settings() {
            chat.plasmoid = root.configWith({aiName: "Nova"});
            dialog.toggleForSession("a");
            verify(dialog.visible);
            wait(50);
            var check = findChild(dialog, "personalityCheck");
            verify(check !== null, "the switch is in the chat's settings");
            verify(check.visible, "shown for a direct chat");
            verify(check.checked, "on by default");
            dialog._save();
            var o = chat.calls[chat.calls.length - 1].args[1];
            verify(!("personalityOff" in o), "nothing saved while it stays on: " + JSON.stringify(o));
            dialog.toggleForSession("a");
            wait(50);
            check = findChild(dialog, "personalityCheck");
            check.click();
            compare(dialog.draft.personalityOn, false);
            verify(dialog.draft.dirty);
            dialog._save();
            o = chat.calls[chat.calls.length - 1].args[1];
            compare(o.personalityOff, true);
            compare(chat.getSessionProperty("a", "personalityOff", false), true);
            compare(direct.buildDirectRequestParts("a", "openai").system, "Main instructions.");
            // Opening again shows it off; turning it on saves false.
            dialog.toggleForSession("a");
            wait(50);
            check = findChild(dialog, "personalityCheck");
            verify(!check.checked);
            check.click();
            dialog._save();
            compare(chat.calls[chat.calls.length - 1].args[1].personalityOff, false);
            verify(direct.buildDirectRequestParts("a", "openai").system.indexOf("## Your persona\nYour name is Nova.") === 0);
            // Agent chats don't show it.
            chat.currentSessionId = "o";
            dialog.toggleForSession("o");
            wait(50);
            verify(!findChild(dialog, "personalityCheck").visible, "not for OpenCode");
            dialog.close();
        }
    }
}
