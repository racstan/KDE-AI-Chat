// Keyboard: Ctrl+N, Ctrl+H, Esc, Up in an empty input, "/" for templates.
import QtQuick
import QtQuick.Window
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
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 200
        chat: chat
    }

    Chat.Composer {
        id: composer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        chat: chat
    }

    Chat.ChatShortcuts {
        id: shortcuts
        chat: chat
    }

    HarnessTestCase {
        name: "Shortcuts"

        readonly property var templates: [{name: "fix", prompt: "Fix this code:"}, {name: "summarize", prompt: "Summarise the following:"}]

        function calls(name) {
            return chat.calls.filter(function(c) { return c.name === name; });
        }

        function init() {
            chat.calls = [];
            chat.loading = false;
            chat.historyOnlyMode = false;
            chat.editingMessageIndex = -1;
            chat.editingDraft = "";
            chat.messages = [{role: "user", content: "First", time: "10:00"}, {role: "assistant", model: "m", content: "Reply", time: "10:00"},
                             {role: "user", content: "Last question", time: "10:01"}, {role: "assistant", model: "m", content: "Last reply", time: "10:01"}];
            chat.promptTemplates = templates;
            chat.chatInputText = "";
            composer.input.text = "";
            chat.focusInput();
            tryVerify(() => composer.input.activeFocus, 1000);
        }

        function test_1_ctrl_n_starts_a_new_chat() {
            keyClick(Qt.Key_N, Qt.ControlModifier);
            compare(calls("create").length, 1);
            compare(calls("create")[0].args[0], true, "and opens it");
        }

        function test_2_ctrl_h_shows_and_hides_the_history() {
            keyClick(Qt.Key_H, Qt.ControlModifier);
            compare(chat.historyOnlyMode, true);
            keyClick(Qt.Key_H, Qt.ControlModifier);
            compare(chat.historyOnlyMode, false);
        }

        function test_3_escape_stops_a_reply_only_while_one_is_written() {
            keyClick(Qt.Key_Escape);
            compare(calls("stop").length, 0, "nothing to stop");
            chat.loading = true;
            keyClick(Qt.Key_Escape);
            compare(calls("stop").length, 1);
        }

        function test_4_escape_cancels_an_edit() {
            chat.editingMessageIndex = 2;
            chat.editingDraft = "half edited";
            keyClick(Qt.Key_Escape);
            compare(chat.editingMessageIndex, -1);
            compare(chat.editingDraft, "");
            compare(calls("stop").length, 0);
        }

        function test_5_up_in_an_empty_input_edits_the_last_message() {
            keyClick(Qt.Key_Up);
            compare(chat.editingMessageIndex, 2, "the last message of yours, not the last reply");
            compare(chat.editingDraft, "Last question");
        }

        function test_6_up_does_nothing_with_text_in_the_input_or_a_reply_running() {
            keyClick("h");
            keyClick("i");
            keyClick(Qt.Key_Up);
            compare(chat.editingMessageIndex, -1, "with text typed, Up moves the cursor");
            composer.input.text = "";
            chat.loading = true;
            keyClick(Qt.Key_Up);
            compare(chat.editingMessageIndex, -1, "not while a reply is being written");
            chat.loading = false;
            chat.messages = [];
            keyClick(Qt.Key_Up);
            compare(chat.editingMessageIndex, -1, "nothing to edit");
        }

        function test_7_slash_suggests_templates_and_enter_picks_one() {
            verify(!composer.suggestions.visible);
            keyClick("/");
            tryVerify(() => composer.suggestions.visible, 1000);
            compare(composer.suggestions.templates.length, 2);
            wait(300);
            screenshot(root.Window.window.contentItem, "shortcuts-templates");
            keyClick("s");
            compare(composer.suggestions.templates.length, 1);
            compare(composer.suggestions.templates[0].name, "summarize");
            keyClick(Qt.Key_Return);
            compare(composer.input.text, "/summarize ", "the name is completed, nothing is sent");
            compare(calls("send").length, 0);
            tryVerify(() => !composer.suggestions.visible, 1000);
        }

        function test_8_arrows_move_in_the_list() {
            keyClick("/");
            tryVerify(() => composer.suggestions.visible, 1000);
            compare(composer.suggestions.current, 0);
            keyClick(Qt.Key_Down);
            compare(composer.suggestions.current, 1);
            keyClick(Qt.Key_Up);
            compare(composer.suggestions.current, 0);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Tab);
            compare(composer.input.text, "/summarize ");
        }

        function test_9_escape_hides_the_list_until_the_text_changes() {
            keyClick("/");
            tryVerify(() => composer.suggestions.visible, 1000);
            keyClick(Qt.Key_Escape);
            tryVerify(() => !composer.suggestions.visible, 1000);
            compare(composer.input.text, "/");
            keyClick("f");
            tryVerify(() => composer.suggestions.visible, 1000);
        }

        function test_10_slash_in_the_middle_suggests_nothing() {
            keyClick("a");
            keyClick("/");
            wait(50);
            verify(!composer.suggestions.active);
            composer.input.text = "";
            keyClick("/");
            keyClick("f");
            keyClick("i");
            keyClick("x");
            keyClick(" ");
            wait(50);
            verify(!composer.suggestions.active, "once the name is complete");
            tryVerify(() => !composer.suggestions.visible, 1000);
        }

        function test_11_enter_sends_when_no_list_is_open() {
            keyClick("o");
            keyClick("k");
            keyClick(Qt.Key_Return);
            compare(calls("send").length, 1);
        }
    }
}
