// Keyboard: Ctrl+N/H/I/L/E, Esc, Ctrl+Shift+R/C, Ctrl+PgUp/PgDown, Ctrl+, Up/Down/PgUp/PgDown to browse messages, "/" for templates.
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
            view.list.clearSelection();
            chat.userScrolledUp = false;
            infoSpy.clear();
            chat.chatInputText = "";
            composer.input.text = "";
            chat.focusInput();
            tryVerify(() => composer.input.activeFocus, 1000);
            wait(150); // the focus timer of focusInput()
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

        function test_5_ctrl_e_edits_the_last_message() {
            keyClick(Qt.Key_E, Qt.ControlModifier);
            compare(chat.editingMessageIndex, 2, "the last message of yours, not the last reply");
            compare(chat.editingDraft, "Last question");
        }

        function test_6_ctrl_e_does_nothing_while_a_reply_runs_or_without_messages() {
            chat.loading = true;
            keyClick(Qt.Key_E, Qt.ControlModifier);
            compare(chat.editingMessageIndex, -1, "not while a reply is being written");
            chat.loading = false;
            chat.messages = [];
            keyClick(Qt.Key_E, Qt.ControlModifier);
            compare(chat.editingMessageIndex, -1, "nothing to edit");
        }

        function test_6a_up_in_an_empty_input_selects_the_latest_message_not_an_edit() {
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 3);
            compare(chat.editingMessageIndex, -1);
            verify(view.list.activeFocus, "the list has focus now");
        }

        function test_6b_up_and_down_walk_the_messages() {
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 2);
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 0, "stops at the first");
            keyClick(Qt.Key_Down);
            compare(view.list.selectedIndex, 1);
            var item = view.list.itemAtIndex(1);
            verify(item && item.selected, "the delegate shows it");
            verify(item.y + item.height > view.list.contentY && item.y < view.list.contentY + view.list.height, "scrolled into view");
        }

        function test_6c_down_past_the_latest_returns_to_the_input() {
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Down);
            compare(view.list.selectedIndex, -1);
            tryVerify(() => composer.input.activeFocus, 1000);
        }

        function test_6d_down_with_nothing_selected_does_nothing() {
            keyClick(Qt.Key_Down);
            compare(view.list.selectedIndex, -1);
            verify(composer.input.activeFocus);
        }

        function test_6e_up_and_down_with_text_move_the_cursor_only() {
            composer.input.text = "line one\nline two";
            composer.input.cursorPosition = composer.input.text.length;
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, -1);
            verify(composer.input.cursorPosition < 9, "cursor moved to the first line");
            keyClick(Qt.Key_Down);
            compare(view.list.selectedIndex, -1);
            verify(composer.input.activeFocus);
        }

        function test_6f_pageup_jumps_to_the_first_and_pagedown_to_the_latest() {
            chat.messages = chat.messages.concat(Array.from({length: 20}, (_, i) => ({role: i % 2 ? "assistant" : "user", model: "m", content: "More " + i, time: "10:02"})));
            tryCompare(view.list, "count", 24);
            keyClick(Qt.Key_PageUp);
            compare(view.list.selectedIndex, 0);
            tryVerify(() => view.list.contentY <= view.list.originY + 1, 1000);
            keyClick(Qt.Key_PageDown);
            compare(view.list.selectedIndex, -1);
            compare(chat.userScrolledUp, false, "follows new messages again");
            tryVerify(() => view.list.atYEnd, 1000);
            tryVerify(() => composer.input.activeFocus, 1000);
        }

        function test_6g_pageup_with_text_jumps_unless_the_input_scrolls() {
            composer.input.text = "short";
            keyClick(Qt.Key_PageUp);
            compare(view.list.selectedIndex, 0, "a short text does not scroll");
            composer.input.forceActiveFocus();
            composer.input.text = Array(40).join("a long line\n");
            tryVerify(() => composer.input.contentHeight > composer.input.height, 1000);
            view.list.clearSelection();
            keyClick(Qt.Key_PageUp);
            compare(view.list.selectedIndex, -1, "a text taller than the box keeps PageUp");
        }

        function test_6h_escape_clears_the_selection_and_focuses_the_input() {
            chat.loading = true;
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 3);
            keyClick(Qt.Key_Escape);
            compare(view.list.selectedIndex, -1);
            compare(calls("stop").length, 0, "the first Esc only clears the selection");
            tryVerify(() => composer.input.activeFocus, 1000);
            chat.loading = false;
        }

        function test_6i_typing_returns_to_the_input_with_that_character() {
            keyClick(Qt.Key_Up);
            keyClick("x");
            compare(view.list.selectedIndex, -1);
            compare(composer.input.text, "x");
            verify(composer.input.activeFocus);
        }

        function test_6j_a_selected_message_shows_its_buttons_and_a_highlight() {
            keyClick(Qt.Key_Up);
            var item = view.list.itemAtIndex(3);
            var actions = findChild(item, "messageActions");
            if (actions)
                tryVerify(() => actions.shown, 1000);
            wait(300);
            screenshot(root.Window.window.contentItem, "shortcuts-browse-selected");
        }

        function test_7_slash_suggests_templates_and_enter_picks_one() {
            verify(!composer.suggestions.visible);
            keyClick("/");
            tryVerify(() => composer.suggestions.visible, 1000);
            compare(composer.suggestions.entries.length, 5, "3 commands, then the 2 templates");
            compare(composer.suggestions.entries[0].kind, "command");
            compare(composer.suggestions.entries[3].kind, "template");
            wait(300);
            screenshot(root.Window.window.contentItem, "shortcuts-templates");
            keyClick("s");
            compare(composer.suggestions.entries.length, 1);
            compare(composer.suggestions.entries[0].name, "summarize");
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
            for (var i = 0; i < 4; i++)
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
            compare(ShortcutList.shortcuts.length, 16);
            ["editLast", "quote", "browseUp", "browseDown", "firstMessage", "latestMessage"].forEach(function(id) {
                verify(ShortcutList.keysFor(id) !== "", id);
            });
            compare(ShortcutList.keysFor("editLast"), "Ctrl+E");
        }
    }
}
