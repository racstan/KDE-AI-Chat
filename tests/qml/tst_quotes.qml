// Quoting a message (Discord-style): the Quote button and Ctrl+Q add a
// removable chip above the message box (Composer.qml, QuoteChips.qml), the sent
// message shows the quote above its text and clicking it jumps to the original
// (QuoteBlock.qml, ChatView.jumpToMessage). What the AI gets is tested in
// tst_quote_send.qml and tests/js/message_content.test.js.
import QtQuick
import QtQuick.Window
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat
import "../../org.kde.plasma.kdeaichat/contents/ui/chat/ChatExport.js" as ChatExport

Item {
    id: root
    width: 520
    height: 560

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
        height: 380
        chat: chat
    }

    Chat.Composer {
        id: composer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        chat: chat
    }

    HarnessTestCase {
        name: "Quotes"

        readonly property var conversation: [
            {role: "user", content: "How do I copy a folder with spaces in its name?", time: "10:00"},
            {role: "assistant", model: "m", content: "Use rsync:\n\nrsync -a \"$SRC\"/ \"$DEST\"/\n\nIt keeps the names intact.", time: "10:00"},
            {role: "error", content: "Rate limit reached", time: "10:01"},
            {role: "user", content: "And in zsh?", time: "10:02"},
            {role: "assistant", model: "m", content: "Same command, zsh has no extra rules.", time: "10:02"}
        ]

        function actionsOf(index) {
            var delegate = view.list.itemAtIndex(index);
            verify(delegate, "delegate " + index);
            var actions = findChild(delegate, "messageActions");
            verify(actions, "actions of " + index);
            return actions;
        }
        function quoteButton(index) {
            var actions = actionsOf(index);
            tryCompare(actions, "built", actions.buttonCount, 3000);
            return findChild(actions, "quoteButton");
        }
        // Over the message, so its buttons show (a hidden item gets no clicks).
        function hover(index) {
            var delegate = view.list.itemAtIndex(index);
            mouseMove(delegate, delegate.width / 2, delegate.height / 2);
            tryCompare(actionsOf(index), "opacity", 1, 2000);
        }
        function chipTexts() {
            return findChildren(composer.quoteChips, "quoteChipText").map(function(l) { return l.text; });
        }
        function windowShot(name) {
            var path = screensDir + name + ".png";
            var saved = false;
            verify(root.Window.contentItem.grabToImage(function(result) { saved = result.saveToFile(path); }));
            tryVerify(function() { return saved; }, 5000);
        }

        function init() {
            chat.calls = [];
            chat.loading = false;
            chat.currentSessionId = "a";
            chat.chatInputText = "";
            chat.messages = conversation.map(function(m) { return Object.assign({}, m); });
            composer.takeQuotes();
            composer.input.text = "";
            view.list.clearSelection();
            mouseMove(root, 5, 5);
            wait(50);
        }

        // --- The button ---

        function test_1_every_user_and_assistant_message_has_a_quote_button_and_errors_do_not() {
            for (var i = 0; i < 5; i++) {
                var button = quoteButton(i);
                if (i === 2)
                    verify(!button, "no quote button on an error");
                else
                    verify(button && button.enabled, "quote button on message " + i);
            }
            compare(quoteButton(0).text, "Quote");
            compare(quoteButton(0).icon.name, "format-text-blockquote");
        }

        function test_2_quoting_adds_a_chip_with_speaker_and_first_line_and_focuses_the_box() {
            verify(!composer.quoteChips.visible, "no chips, no row");
            hover(1);
            mouseClick(quoteButton(1));
            tryCompare(composer.quoteChips, "visible", true);
            compare(chipTexts(), ["Assistant · Use rsync:"]);
            compare(composer.quoteChips.quotes[0].role, "assistant");
            verify(composer.quoteChips.quotes[0].id !== "", "the message's id, to jump back to");
            tryVerify(function() { return composer.input.activeFocus; }, 1000, "focus goes to the box");
            windowShot("quote-chip-above-box");
        }

        function test_3_several_quotes_keep_their_order_and_the_same_one_is_not_added_twice() {
            composer.addQuote(chat.messages[3]);
            composer.addQuote(chat.messages[1]);
            composer.addQuote(chat.messages[3]);
            compare(chipTexts(), ["You · And in zsh?", "Assistant · Use rsync:"]);
            composer.addQuote(chat.messages[2]);
            compare(chipTexts().length, 2, "an error cannot be quoted");
        }

        function test_4_a_chip_is_removable() {
            composer.addQuote(chat.messages[0]);
            composer.addQuote(chat.messages[1]);
            var remove = findChildren(composer.quoteChips, "quoteChipRemove");
            compare(remove.length, 2);
            wait(100);  // the chips row has settled in the layout
            mouseClick(remove[0]);
            tryVerify(function() { return composer.quoteChips.quotes.length === 1; }, 2000);
            compare(chipTexts(), ["Assistant · Use rsync:"]);
            wait(100);
            mouseClick(findChildren(composer.quoteChips, "quoteChipRemove")[0]);
            tryCompare(composer.quoteChips, "visible", false);
        }

        function test_5_a_long_first_line_is_cut_in_the_chip() {
            chat.messages = [{role: "user", content: "word ".repeat(200), time: "10:00"}];
            wait(50);
            composer.addQuote(chat.messages[0]);
            var label = findChild(composer.quoteChips, "quoteChipText");
            verify(label.truncated, "elided");
            verify(label.width < composer.width);
        }

        function test_6_taking_the_quotes_hands_them_over_once_and_clears_the_chips() {
            composer.addQuote(chat.messages[0]);
            composer.addQuote(chat.messages[1]);
            var taken = composer.takeQuotes();
            compare(taken.length, 2);
            compare(taken[0].role, "user");
            compare(taken[1].text, chat.messages[1].content);
            compare(composer.takeQuotes().length, 0);
            tryCompare(composer.quoteChips, "visible", false);
        }

        function test_7_the_quotes_belong_to_their_chat() {
            composer.addQuote(chat.messages[0]);
            compare(composer.quoteChips.quotes.length, 1);
            chat.currentSessionId = "b";
            compare(composer.quoteChips.quotes.length, 0, "another chat: no quotes");
        }

        // --- The key ---

        function test_8_ctrl_q_quotes_the_picked_message() {
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 4);
            keyClick(Qt.Key_Q, Qt.ControlModifier);
            compare(chipTexts(), ["Assistant · Same command, zsh has no extra rules."]);
            compare(view.list.selectedIndex, -1, "the pick is cleared: the box has the focus");
            tryVerify(function() { return composer.input.activeFocus; }, 1000);
            wait(250);  // focusInput() also refocuses after 120 ms, which would clear a pick made meanwhile
            // Another one, picked with the arrows.
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 3);
            keyClick(Qt.Key_Q, Qt.ControlModifier);
            compare(chipTexts(), ["Assistant · Same command, zsh has no extra rules.", "You · And in zsh?"]);
        }

        function test_9_ctrl_q_needs_a_picked_quotable_message_and_a_plain_q_still_types() {
            keyClick(Qt.Key_Q, Qt.ControlModifier);
            compare(chipTexts().length, 0, "nothing picked: nothing quoted");
            keyClick(Qt.Key_Up);
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 3);
            keyClick(Qt.Key_Up);
            compare(view.list.selectedIndex, 2, "the error");
            keyClick(Qt.Key_Q, Qt.ControlModifier);
            compare(chipTexts().length, 0, "an error is not quoted");
            compare(view.list.selectedIndex, 2, "and the pick stays");
            keyClick("q");
            compare(composer.input.text, "q", "a plain q is typing");
            compare(chipTexts().length, 0);
        }

        function test_10_ctrl_q_is_in_the_shortcut_list() {
            var text = Qt.createQmlObject('import QtQuick; import "../../org.kde.plasma.kdeaichat/contents/ui/chat/ShortcutList.js" as S; QtObject { property string keys: S.keysFor("quote") }', root, "k.qml");
            compare(text.keys, "Ctrl+Q");
        }

        // --- The quote on a sent message ---

        function sentMessages() {
            var id = chat.messages[1].id;
            verify(id, "the model gave the assistant message an id");
            return [
                chat.messages[0], chat.messages[1],
                {role: "user", content: "Why does it keep the names intact?", time: "10:03",
                 quotes: [{id: id, role: "assistant", text: chat.messages[1].content}, {id: "gone-1", role: "user", text: "A message that was deleted"}]}
            ];
        }

        function test_11_a_message_with_quotes_shows_them_above_its_text() {
            chat.messages = sentMessages();
            wait(100);
            var delegate = view.list.itemAtIndex(2);
            var block = findChild(delegate, "quoteBlock");
            verify(block, "the quote block");
            var quotes = findChildren(block, "quote");
            compare(quotes.length, 2);
            compare(findChildren(quotes[0], "quoteSpeaker")[0].text, "Assistant");
            verify(findChildren(quotes[0], "quoteText")[0].text.indexOf("Use rsync:") === 0);
            compare(findChildren(quotes[1], "quoteSpeaker")[0].text, "You");
            var body = findChild(delegate, "messageBody");
            verify(body.mapToItem(delegate, 0, 0).y > quotes[1].mapToItem(delegate, 0, 0).y, "the text is below the quotes");
            compare(body.text, "Why does it keep the names intact?", "only the text is the message");
            var plain = view.list.itemAtIndex(0);
            verify(!findChild(plain, "quoteBlock"), "no quotes, no block");
            windowShot("quote-block-in-message");
        }

        function test_12_clicking_a_quote_jumps_to_and_picks_the_original() {
            var list = [];
            for (var i = 0; i < 30; i++)
                list.push({role: i % 2 ? "assistant" : "user", model: "m", content: "Filler message " + i + "\n\nwith a second paragraph", time: "10:00"});
            chat.messages = list;
            wait(50);
            var target = chat.messages[3];
            chat.messages = chat.messages.concat([{role: "user", content: "Back to that", time: "10:05", quotes: [{id: target.id, role: "assistant", text: target.content}]}]);
            view.list.jumpLatest();
            wait(100);
            view.list.positionViewAtEnd();
            var last = view.list.itemAtIndex(30);
            tryVerify(function() { return !!(last = view.list.itemAtIndex(30)); }, 2000);
            var area = findChild(last, "quoteArea");
            verify(area, "quote area");
            compare(view.list.selectedIndex, -1);
            mouseMove(area, 5, 5);
            mouseClick(area, 5, 5);
            compare(view.list.selectedIndex, 3, "the original is picked (highlighted)");
            tryVerify(function() { return view.list.itemAtIndex(3) !== null; }, 2000, "and scrolled into view");
            var shown = view.list.itemAtIndex(3);
            var y = shown.mapToItem(view, 0, 0).y;
            verify(y >= -1 && y + shown.height <= view.height + 1, "fully visible: " + y);
        }

        function test_13_a_quote_of_a_deleted_message_does_nothing_and_says_so() {
            chat.messages = sentMessages();
            wait(100);
            view.list.select(0);
            var block = findChild(view.list.itemAtIndex(2), "quoteBlock");
            var gone = findChildren(block, "quoteArea")[1];
            mouseMove(gone, 4, 4);
            mouseClick(gone, 4, 4);
            compare(view.list.selectedIndex, 0, "nothing to jump to: the pick is as it was");
            compare(findChildren(block, "quote")[1].original, false);
            verify(!view.list.jumpToMessage("gone-1"));
            verify(!view.list.jumpToMessage(""));
        }

        // --- Export ---

        function test_14_the_export_has_block_quotes() {
            chat.messages = sentMessages();
            var md = ChatExport.build("markdown", {title: "Q", messages: chat.messages, exportedAt: 0});
            verify(md.indexOf("> **Assistant:** Use rsync:\n>\n> rsync -a") >= 0, md);
            verify(md.indexOf("> **You:** A message that was deleted\n\nWhy does it keep the names intact?") >= 0, md);
        }
    }
}
