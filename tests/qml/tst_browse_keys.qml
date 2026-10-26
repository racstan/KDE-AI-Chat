// Up/Down move through the messages whenever the message list has focus:
// after clicking a message's text or an empty part of the chat, as well as
// from an empty input (tst_shortcuts.qml covers that one).
import QtQuick
import QtQuick.Window
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 420

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
        height: 300
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
        chat: chat
    }

    HarnessTestCase {
        name: "BrowseKeys"

        function init() {
            chat.loading = false;
            chat.editingMessageIndex = -1;
            chat.editingDraft = "";
            chat.messages = [{role: "user", content: "First", time: "10:00"}, {role: "assistant", model: "m", content: "Reply", time: "10:00"},
                             {role: "user", content: "Last question", time: "10:01"}, {role: "assistant", model: "m", content: "Last reply", time: "10:01"}];
            view.list.clearSelection();
            chat.userScrolledUp = false;
            chat.chatInputText = "";
            composer.input.text = "";
            chat.focusInput();
            tryVerify(() => composer.input.activeFocus, 1000);
            wait(150); // the focus timer of focusInput()
        }

        // The text item of the message at `row` (a read-only TextEdit).
        function messageText(row) {
            var item = view.list.itemAtIndex(row);
            var found = null;
            function walk(it) {
                if (found || !it)
                    return;
                if (it.readOnly === true && it.selectByMouse === true && String(it.text).indexOf(chat.messages[row].content) >= 0) {
                    found = it;
                    return;
                }
                var kids = it.children || [];
                for (var i = 0; i < kids.length; i++)
                    walk(kids[i]);
            }
            walk(item);
            return found;
        }

        function test_1_after_clicking_a_message_up_selects_the_latest() {
            tryVerify(() => messageText(1) !== null, 2000);
            var text = messageText(1);
            mouseClick(text, 5, text.height / 2);
            verify(!composer.input.activeFocus, "the click took the focus from the input");
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 3, "nothing was selected: Up picks the latest");
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 2);
            keyClick(Qt.Key_Down);
            compare(view.list.selectedIndex, 3);
        }

        function test_2_after_clicking_an_empty_part_of_the_chat_up_and_down_browse() {
            tryVerify(() => view.list.itemAtIndex(0) !== null, 2000);
            // The gap between two messages (list.spacing) is no message.
            var gapY = view.list.itemAtIndex(0).y + view.list.itemAtIndex(0).height + view.list.spacing / 2 - view.list.contentY;
            mouseClick(view.list, view.list.width / 2, gapY);
            tryVerify(() => view.list.activeFocus, 1000, "clicking the chat gives it the focus");
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 3);
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 2);
            var row = view.list.itemAtIndex(2);
            verify(row.y + row.height > view.list.contentY && row.y < view.list.contentY + view.list.height, "scrolled into view");
        }

        function test_3_down_with_nothing_selected_returns_to_the_input() {
            mouseClick(view.list, view.list.width / 2, view.list.height - 2);
            tryVerify(() => view.list.activeFocus, 1000);
            keyClick(Qt.Key_Down);
            compare(view.list.selectedIndex, -1);
            tryVerify(() => composer.input.activeFocus, 1000);
        }

        function test_4_down_past_the_latest_returns_to_the_input() {
            mouseClick(view.list, view.list.width / 2, view.list.height - 2);
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 3);
            keyClick(Qt.Key_Down);
            compare(view.list.selectedIndex, -1);
            tryVerify(() => composer.input.activeFocus, 1000);
        }

        function test_5_text_in_the_input_keeps_up_and_down_for_the_cursor() {
            composer.input.text = "line one\nline two";
            composer.input.cursorPosition = composer.input.text.length;
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, -1);
            verify(composer.input.cursorPosition < 9);
        }

        function test_6_an_edit_in_place_keeps_up_and_down() {
            chat.editingMessageIndex = 2;
            chat.editingDraft = "line one\nline two";
            var editor = null;
            tryVerify(function() {
                editor = findChild(view.list.itemAtIndex(2), "inPlaceEditor");
                return editor !== null && editor.activeFocus;
            }, 2000);
            editor.cursorPosition = 0;
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, -1, "Up at the top of the edit does not browse");
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            compare(view.list.selectedIndex, -1);
            verify(editor.activeFocus);
            chat.editingMessageIndex = -1;
        }

        function test_7_a_click_on_a_message_button_keeps_the_focus_where_the_button_put_it() {
            var copy = null;
            function walk(it) {
                if (copy || !it)
                    return;
                if (it.checkable !== undefined && it.text === "Copy" && it.visible) {
                    copy = it;
                    return;
                }
                var kids = it.children || [];
                for (var i = 0; i < kids.length; i++)
                    walk(kids[i]);
            }
            tryVerify(function() { walk(view.list.itemAtIndex(3)); return copy !== null; }, 2000);
            mouseClick(copy);
            wait(50);
            compare(root.Window.activeFocusItem, copy, "the list did not take the focus from the button");
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 3, "and Up from there browses too");
        }

        function test_8_a_field_in_a_message_keeps_up_and_down() {
            // Like a question card's answer field.
            tryVerify(() => view.list.itemAtIndex(3) !== null, 2000);
            var field = Qt.createQmlObject('import QtQuick; TextInput { width: 100; height: 20; text: "answer" }', view.list.itemAtIndex(3));
            field.forceActiveFocus();
            verify(field.activeFocus);
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Down);
            compare(view.list.selectedIndex, -1);
            verify(field.activeFocus, "still typing the answer");
            field.destroy();
        }
    }
}
