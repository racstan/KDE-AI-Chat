// Keyboard: Ctrl+N/H/I/L, Esc, Ctrl+Shift+R/C, Ctrl+PgUp/PgDown, Ctrl+, Up in an empty input, "/" for templates.
import QtQuick
import QtQuick.Window
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat/ShortcutList.js" as ShortcutList
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

    SignalSpy {
        id: infoSpy
        target: shortcuts
        signalName: "chatInfoRequested"
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
            chat.sessions = [{value: "a", title: "A"}, {value: "b", title: "B"}, {value: "old", title: "Old", archived: true}, {value: "c", title: "C"}];
            chat.currentSessionId = "a";
            infoSpy.clear();
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

        function test_12_ctrl_i_asks_for_the_info_panel() {
            keyClick(Qt.Key_I, Qt.ControlModifier);
            compare(infoSpy.count, 1);
        }

        function test_13_ctrl_l_focuses_the_input() {
            composer.input.focus = false;
            chat.composerRef = composer;
            keyClick(Qt.Key_L, Qt.ControlModifier);
            tryVerify(() => composer.input.activeFocus, 1000);
        }

        function test_14_regenerate_the_last_reply() {
            keyClick(Qt.Key_R, Qt.ControlModifier | Qt.ShiftModifier);
            compare(calls("regenerate").length, 1);
            compare(calls("regenerate")[0].args[0], 3, "the last reply");
            chat.loading = true;
            keyClick(Qt.Key_R, Qt.ControlModifier | Qt.ShiftModifier);
            compare(calls("regenerate").length, 1, "not while one is being written");
        }

        function test_15_copy_the_last_reply() {
            keyClick(Qt.Key_C, Qt.ControlModifier | Qt.ShiftModifier);
            compare(calls("copy").length, 1);
            compare(calls("copy")[0].args[0], "Last reply");
            chat.messages = [];
            keyClick(Qt.Key_C, Qt.ControlModifier | Qt.ShiftModifier);
            compare(calls("copy").length, 1, "nothing to copy");
        }

        function test_16_ctrl_pgdown_and_pgup_switch_chats_skipping_archived() {
            keyClick(Qt.Key_PageDown, Qt.ControlModifier);
            compare(chat.currentSessionId, "b");
            keyClick(Qt.Key_PageDown, Qt.ControlModifier);
            compare(chat.currentSessionId, "c", "the archived chat is skipped");
            keyClick(Qt.Key_PageDown, Qt.ControlModifier);
            compare(chat.currentSessionId, "a", "wraps around");
            keyClick(Qt.Key_PageUp, Qt.ControlModifier);
            compare(chat.currentSessionId, "c");
        }

        function test_17_ctrl_comma_opens_the_settings() {
            keyClick(Qt.Key_Comma, Qt.ControlModifier);
            compare(calls("openSettings").length, 1);
        }

        function test_18_text_editing_keys_still_edit_the_input() {
            keyClick("a");
            keyClick("b");
            keyClick("c");
            keyClick(Qt.Key_A, Qt.ControlModifier);
            keyClick(Qt.Key_C, Qt.ControlModifier);
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_V, Qt.ControlModifier);
            keyClick(Qt.Key_V, Qt.ControlModifier);
            compare(composer.input.text.indexOf("abc") === 0, true);
            compare(calls("copy").length, 0, "Ctrl+C is not Copy last reply");
            compare(calls("regenerate").length, 0);
            keyClick(Qt.Key_Z, Qt.ControlModifier);
            keyClick(Qt.Key_A, Qt.ControlModifier);
            keyClick(Qt.Key_X, Qt.ControlModifier);
            compare(composer.input.text, "", "select all + cut");
            keyClick("q");
            keyClick("r");
            keyClick(Qt.Key_Left, Qt.ControlModifier);
            keyClick("x");
            compare(composer.input.text, "xqr", "Ctrl+Left moves by word");
            compare(chat.currentSessionId, "a");
            compare(infoSpy.count, 0);
        }

        function test_19_the_list_has_unique_keys_and_ids() {
            var seen = {};
            ShortcutList.shortcuts.forEach(function(s) {
                verify(!seen[s.keys], "duplicate " + s.keys);
                seen[s.keys] = true;
                verify(!/^Ctrl\+(C|V|X|Z|A|Y)$/.test(s.keys), s.keys + " clashes with text editing");
            });
            compare(ShortcutList.shortcuts.length, 10);
        }
    }
}
