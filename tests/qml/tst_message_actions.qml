// The buttons under a message: hidden until the message is hovered or has
// keyboard focus, never on a streaming message, nothing moves when they
// appear, and regenerating asks first when later messages would be dropped.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 520
    height: 640

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
        name: "MessageActions"

        readonly property var conversation: [
            {role: "user", content: "First question", time: "10:00"},
            {role: "assistant", model: "m", content: "First answer", time: "10:00", tokens: {input: 30, output: 212}},
            {role: "user", content: "Second question", time: "10:01"},
            {role: "assistant", model: "m", content: "Second answer", time: "10:01"}
        ]

        function actionsOf(index) {
            var delegate = view.list.itemAtIndex(index);
            verify(delegate, "delegate " + index);
            var actions = findChild(delegate, "messageActions");
            verify(actions, "actions of " + index);
            return actions;
        }

        function init() {
            chat.calls = [];
            chat.currentStreamIndex = -1;
            chat.currentStreamText = "";
            chat.loading = false;
            chat.editingMessageIndex = -1;
            chat.messages = conversation;
            wait(50);
            // Pointer away from every message.
            mouseMove(root, 5, 5);
            // The buttons are built after the first frame.
            for (var i = 0; i < 4; i++)
                tryCompare(actionsOf(i), "built", actionsOf(i).buttonCount, 3000);
        }

        function test_1_hidden_until_hovered() {
            var actions = actionsOf(1);
            var delegate = view.list.itemAtIndex(1);
            tryCompare(actions, "opacity", 0);
            var before = delegate.height;
            // Over the first message instead: still hidden.
            var other = view.list.itemAtIndex(0);
            mouseMove(other, other.width / 2, other.height / 2);
            wait(50);
            compare(actions.opacity, 0);
            mouseMove(delegate, delegate.width / 2, delegate.height / 2);
            tryCompare(actions, "opacity", 1, 2000);
            screenshot(root, "message-actions-hovered");
            compare(delegate.height, before, "the message doesn't grow when its buttons appear");
            mouseMove(other, other.width / 2, other.height / 2);
            tryCompare(actions, "opacity", 0, 2000);
            compare(delegate.height, before, "nor when they go");
        }

        function test_2_keyboard_focus_shows_them() {
            var actions = actionsOf(3);
            compare(actions.opacity, 0);
            var button = actions.children[0].item;
            verify(button, "first button built");
            button.forceActiveFocus();
            tryVerify(() => button.activeFocus);
            tryCompare(actions, "opacity", 1, 2000);
            verify(actions.focusWithin);
            actionsOf(0).children[0].item.forceActiveFocus();
            tryCompare(actions, "opacity", 0, 2000);
        }

        function test_3_never_on_a_streaming_message() {
            chat.messages = conversation.concat([{role: "user", content: "Third"}, {role: "assistant", content: "", model: "m"}]);
            chat.currentStreamIndex = 5;
            chat.loading = true;
            wait(50);
            var actions = actionsOf(5);
            var delegate = view.list.itemAtIndex(5);
            mouseMove(delegate, delegate.width / 2, delegate.height / 2);
            wait(150);
            compare(actions.opacity, 0, "hidden while streaming even under the pointer");
            verify(!actions.enabled, "and not clickable");
            chat.currentStreamIndex = -1;
            chat.loading = false;
            mouseMove(root, 5, 5);
            mouseMove(delegate, delegate.width / 2, delegate.height / 2 + 1);
            tryCompare(actions, "opacity", 1, 2000);
        }

        function test_4_regenerate_asks_when_later_messages_would_go() {
            var actions = actionsOf(1);
            compare(actions.laterMessages, 2);
            actions.regenerate("");
            var confirm = null;
            tryVerify(() => (confirm = findChild(QQC2.Overlay.overlay, "regenerateConfirmButton")) !== null, 2000);
            compare(chat.calls.length, 0, "nothing is dropped before the answer");
            screenshot(root, "message-actions-regenerate-confirm");
            mouseClick(confirm);
            compare(chat.calls.length, 1);
            compare(chat.calls[0].name, "regenerate");
            compare(chat.calls[0].args, [1, ""]);
        }

        function test_5_regenerate_the_last_reply_needs_no_question() {
            var actions = actionsOf(3);
            compare(actions.laterMessages, 0);
            actions.regenerate("shorter");
            compare(chat.calls.length, 1);
            compare(chat.calls[0].args, [3, "shorter"]);
        }

        function shownTexts(actions) {
            var texts = [];
            for (var i = 0; i < actions.children.length; i++) {
                var item = actions.children[i].item;
                if (item && actions.children[i].visible)
                    texts.push(item.text);
            }
            return texts;
        }

        function test_6a_an_image_only_reply_offers_only_delete() {
            // Its pictures carry their own enlarge/copy/save/regenerate buttons.
            var withPicture = conversation.slice();
            withPicture[3] = {role: "assistant", model: "AI Horde · Deliberate", content: "", time: "10:01",
                              images: [{path: "images/a/1.png", service: "horde", prompt: "sun"}]};
            chat.messages = withPicture;
            wait(50);
            tryCompare(actionsOf(3), "built", actionsOf(3).buttonCount, 3000);
            verify(actionsOf(3).imageOnly);
            compare(shownTexts(actionsOf(3)), ["Delete"]);
            // A reply with text and pictures keeps every button.
            verify(!actionsOf(1).imageOnly);
            verify(shownTexts(actionsOf(1)).indexOf("Copy") >= 0);
            verify(shownTexts(actionsOf(1)).indexOf("Regenerate") >= 0);
        }

        function test_6_icon_buttons_have_names() {
            var actions = actionsOf(1);
            for (var i = 0; i < actions.children.length; i++) {
                var item = actions.children[i].item;
                if (item)
                    verify(item.Accessible.name !== "", "button " + i + " has an accessible name");
            }
        }

        function test_7_your_own_message_has_the_same_buttons_and_edits_in_place() {
            var delegate = view.list.itemAtIndex(0);
            var actions = actionsOf(0);
            mouseMove(delegate, delegate.width / 2, delegate.height / 2);
            tryCompare(actions, "opacity", 1, 2000);
            var edit = actions.children[0].item;
            compare(edit.text, "Edit");
            mouseClick(edit);
            compare(chat.editingMessageIndex, 0);
            compare(chat.editingDraft, "First question");
            wait(100);
            // The text box replaces the text, and Save / Cancel the buttons.
            verify(!findChild(delegate, "messageBody").visible);
            var area = null;
            (function walk(item) {
                if (!area && item.hasOwnProperty("selectByMouse") && item.hasOwnProperty("placeholderText") && item.visible) area = item;
                for (var i = 0; i < item.children.length; i++) walk(item.children[i]);
            })(delegate);
            verify(area, "an edit box");
            compare(area.text, "First question");
            screenshot(root, "message-actions-editing");
        }

        function test_8_usage_line_is_left_and_shows_with_the_buttons() {
            var delegate = view.list.itemAtIndex(1);
            var actions = actionsOf(1);
            var usage = findChild(delegate, "usageLine");
            verify(usage, "usage line");
            compare(usage.text, "30 in · 212 out");
            tryCompare(usage, "opacity", 0, 2000);
            var before = delegate.height;
            var leftEdge = usage.mapToItem(delegate, 0, 0).x;
            mouseMove(delegate, delegate.width / 2, delegate.height / 2);
            tryCompare(usage, "opacity", 0.55, 2000);
            compare(delegate.height, before, "nothing moves");
            compare(usage.mapToItem(delegate, 0, 0).x, leftEdge);
            verify(usage.mapToItem(delegate, 0, 0).x >= actions.mapToItem(delegate, actions.width, 0).x, "right after the buttons");
            verify(usage.x + usage.width < delegate.width / 2, "on the left");
            // Your own messages have none.
            verify(!findChild(view.list.itemAtIndex(0), "usageLine").visible);
        }

        function test_9_your_buttons_are_at_the_right() {
            var delegate = view.list.itemAtIndex(0);
            var mineActions = actionsOf(0);
            var replyActions = actionsOf(1);
            verify(mineActions.mapToItem(delegate, mineActions.width, 0).x > delegate.width - 40, "right-aligned");
            verify(replyActions.mapToItem(delegate, 0, 0).x < 40, "a reply's are at the left");
        }

        function buttonNamed(actions, name) {
            for (var i = 0; i < actions.children.length; i++) {
                var item = actions.children[i].item;
                if (item && item.text === name)
                    return item;
            }
            return null;
        }

        function test_9_resend_is_on_your_messages_only() {
            verify(buttonNamed(actionsOf(0), "Resend"), "user message has Resend");
            verify(buttonNamed(actionsOf(2), "Resend"), "so does the second one");
            verify(!buttonNamed(actionsOf(1), "Resend"), "a reply doesn't");
            verify(buttonNamed(actionsOf(1), "Regenerate"), "it has Regenerate");
            verify(!buttonNamed(actionsOf(0), "Regenerate"), "a user message doesn't");
            var delegate = view.list.itemAtIndex(2);
            mouseMove(delegate, delegate.width / 2, delegate.height / 2);
            tryCompare(actionsOf(2), "opacity", 1, 2000);
            screenshot(root, "message-actions-resend");
        }

        function test_a_resend_asks_when_later_messages_would_go() {
            var actions = actionsOf(0);
            compare(actions.laterMessages, 3);
            mouseClick(buttonNamed(actions, "Resend"));
            var confirm = null;
            tryVerify(() => (confirm = findChild(QQC2.Overlay.overlay, "regenerateConfirmButton")) !== null, 2000);
            compare(confirm.text, "Resend");
            compare(chat.calls.length, 0, "nothing is dropped before the answer");
            screenshot(root, "message-actions-resend-confirm");
            mouseClick(confirm);
            compare(chat.calls.length, 1);
            compare(chat.calls[0].name, "regenerate");
            compare(chat.calls[0].args, [0, ""]);
        }

        function test_b_resend_of_the_last_message_needs_no_question() {
            chat.messages = conversation.slice(0, 3);
            wait(50);
            var actions = actionsOf(2);
            compare(actions.laterMessages, 0);
            actions.regenerate("");
            compare(chat.calls.length, 1);
            compare(chat.calls[0].args, [2, ""]);
        }

        function test_c_resend_is_disabled_while_replying() {
            tryCompare(actionsOf(0), "built", actionsOf(0).buttonCount, 3000);
            var button = buttonNamed(actionsOf(0), "Resend");
            verify(button.enabled);
            chat.currentStreamIndex = 3;
            chat.loading = true;
            tryVerify(() => !button.enabled, 2000);
            chat.currentStreamIndex = -1;
            chat.loading = false;
        }
    }
}
