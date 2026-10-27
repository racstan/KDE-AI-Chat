// The look, layout and behaviour options (chat/ChatPrefs.qml) in the chat:
// with the defaults nothing differs from the plain Plasma look and the old
// behaviour; each option takes effect when set and goes away when reset.
// Laid out as FullRepresentationContent.qml does (an AccentArea around the
// header, the folder bar and the body). Screenshots: build/qml-screens/prefs-*.png.
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtTest
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 900
    height: 640

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(one, many, n) { return (n === 1 ? one : many).replace("%1", n); }

    FakeChat { id: chat }

    Chat.ChatNavigation { id: nav; chat: chat }

    // What the input's font is without any option.
    PC3.TextArea { id: referenceInput; visible: false }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    Chat.AccentArea {
        id: area
        anchors.fill: parent
        accent: chat.prefs.accent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            Chat.ChatHeader { id: header; chat: chat; historyFull: body.historyFull }
            Chat.WorkspaceBar { id: bar; chat: chat; historyFull: body.historyFull }
            Chat.ChatBody {
                id: body
                chat: chat
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }
    }

    HarnessTestCase {
        id: testCase
        name: "ChatPrefs"

        readonly property var sample: [
            {role: "user", content: "Can you show me a loop in Python?", time: "14:30", at: new Date(2026, 9, 25, 14, 30).getTime()},
            {role: "assistant", model: "openrouter/auto", content: "Here is one:\n\n```python\nfor i in range(3):\n    print(i)\n```\n\nIt prints **0, 1 and 2**.", time: "14:31", at: new Date(2026, 9, 25, 14, 31).getTime()}
        ]

        function configure(values) {
            chat.plasmoid = {"configuration": values};
            wait(80);
        }
        function init() {
            root.width = 900;
            configure({});
            chat.openCodeMode = false;
            chat.historyOnlyMode = false;
            chat.loading = false;
            chat.userScrolledUp = false;
            chat.calls = [];
            chat.chatInputText = "";
            chat.sessions = [{value: "a", text: "Trip planning", count: 2}, {value: "b", text: "Python loops", count: 2}];
            chat.messages = sample;
            wait(150);
        }
        function cleanup() {
            chat.messages = [];
            wait(50);
        }
        function messageText() { return findChild(body.chatView, "messageText"); }
        function bubbles() { return findChildren(body.chatView, "bubble"); }
        function list() { return body.chatView.list; }
        function sameColor(a, b) {
            a = Qt.lighter(a, 1);
            b = Qt.lighter(b, 1);
            return Math.abs(a.r - b.r) < 0.01 && Math.abs(a.g - b.g) < 0.01 && Math.abs(a.b - b.b) < 0.01 && Math.abs(a.a - b.a) < 0.01;
        }

        function test_1_the_defaults_change_nothing() {
            var p = chat.prefs;
            compare(p.fontFactor, 1);
            compare(p.densityFactor, 1);
            compare(p.bubbles, false);
            compare(p.codeTheme, null);
            compare(p.accent, "");
            compare(p.sendKey, "enter");
            compare(p.formatTime(Date.now()), "", "the time stays as the message has it");
            // Fonts: the theme's, unscaled.
            var text = messageText();
            verify(text !== null);
            compare(text.font.pointSize, Kirigami.Theme.defaultFont.pointSize);
            compare(text.font.family, Kirigami.Theme.defaultFont.family);
            compare(body.composerItem.input.font.pointSize, referenceInput.font.pointSize);
            // Spacing and no boxes.
            compare(list().spacing, Kirigami.Units.largeSpacing);
            var all = bubbles();
            verify(all.length >= 2);
            for (var i = 0; i < all.length; i++)
                compare(all[i].color.a, 0, "no fill");
            // Code in the Plasma colours.
            var code = findChild(body.chatView, "codeBlock");
            verify(code !== null);
            verify(sameColor(code.color, Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)));
            // The theme isn't touched: same accent as outside the area.
            verify(area.Kirigami.Theme.inherit);
            verify(sameColor(text.selectionColor, root.Kirigami.Theme.highlightColor));
            // Every button, the folder bar, the history on the left.
            ["historyButton", "pinButton", "settingsButton", "newChatButton", "infoButton", "moreButton"].forEach(function(name) {
                verify(findChild(header, name).visible, name);
            });
            verify(bar.visible);
            chat.historyOnlyMode = true;
            wait(600);
            verify(body.historyPane.mapToItem(root, 0, 0).x < body.chatView.mapToItem(root, 0, 0).x, "history on the left");
            screenshot(root, "prefs-defaults");
            chat.historyOnlyMode = false;
            wait(400);
            // Enter sends.
            chat.focusInput();
            tryVerify(() => body.composerItem.input.activeFocus);
            keyClick("h");
            keyClick("i");
            keyClick(Qt.Key_Return);
            compare(chat.calls.filter(function(c) { return c.name === "send"; }).length, 1);
        }

        function test_2_ctrl_enter_sends_and_enter_adds_a_line() {
            configure({"sendKey": "ctrlEnter"});
            chat.messages = [];
            wait(50);
            var input = body.composerItem.input;
            chat.focusInput();
            tryVerify(() => input.activeFocus);
            keyClick("a");
            keyClick(Qt.Key_Return);
            keyClick("b");
            compare(chat.calls.length, 0, "Enter did not send");
            compare(input.text, "a\nb");
            keyClick(Qt.Key_Return, Qt.ShiftModifier);
            compare(chat.calls.length, 0, "Shift+Enter neither");
            keyClick(Qt.Key_Return, Qt.ControlModifier);
            compare(chat.calls.length, 1);
            compare(chat.calls[0].name, "send");
            compare(chat.calls[0].args[0], "a\nb\n");
            var hint = findChildren(body.composerItem, "").filter(function(item) { return item.isNewChat !== undefined; })[0];
            verify(hint && hint.text.indexOf("Ctrl+Enter sends") === 0, hint ? hint.text : "no status row");
        }

        function test_3_history_on_the_right() {
            configure({"historySide": "right"});
            chat.historyOnlyMode = true;
            wait(600);
            var pane = body.historyPane.mapToItem(root, 0, 0).x;
            var view = body.chatView.mapToItem(root, 0, 0).x;
            verify(pane > view, "history right of the chat: " + pane + " > " + view);
            verify(body.historyPane.mapToItem(root, body.historyPane.width, 0).x <= root.width, "inside the popup");
            screenshot(root, "prefs-history-right");
        }

        function test_4_text_size_applies_to_messages_code_and_input() {
            configure({"chatFontScale": 150});
            var text = messageText();
            var base = Kirigami.Theme.defaultFont;
            if (base.pixelSize > 0)
                compare(text.font.pixelSize, Math.round(base.pixelSize * 1.5));
            else
                fuzzyCompare(text.font.pointSize, base.pointSize * 1.5, 0.01);
            verify(body.composerItem.input.font.pointSize > referenceInput.font.pointSize || body.composerItem.input.font.pixelSize > referenceInput.font.pixelSize, "the input too");
            screenshot(root, "prefs-font-150");
            configure({});
            compare(messageText().font.pointSize, base.pointSize, "back to the theme's size");
            compare(body.composerItem.input.font.pointSize, referenceInput.font.pointSize);
        }

        function test_5_accent_colour_and_bubbles() {
            configure({"accentColor": "#e91e63", "chatStyle": "bubbles"});
            verify(!area.Kirigami.Theme.inherit);
            verify(sameColor(messageText().selectionColor, "#e91e63"), "selections take the accent");
            var all = bubbles();
            var mine = all.filter(function(b) { return b.Layout.alignment === Qt.AlignRight; })[0];
            var theirs = all.filter(function(b) { return b.Layout.alignment !== Qt.AlignRight; })[0];
            verify(mine.color.a > 0 && mine.color.r > mine.color.g, "your bubble is tinted with the accent");
            verify(theirs.color.a > 0, "the AI's bubble is filled");
            screenshot(root, "prefs-accent-bubbles");
            configure({});
            verify(area.Kirigami.Theme.inherit);
            verify(sameColor(messageText().selectionColor, root.Kirigami.Theme.highlightColor), "back to the Plasma accent");
            compare(bubbles()[0].color.a, 0);
        }

        function test_6_density() {
            configure({"chatDensity": "compact"});
            compare(list().spacing, Math.round(Kirigami.Units.largeSpacing * 0.5));
            screenshot(root, "prefs-compact");
            configure({"chatDensity": "roomy"});
            compare(list().spacing, Math.round(Kirigami.Units.largeSpacing * 1.5));
            configure({});
            compare(list().spacing, Kirigami.Units.largeSpacing);
        }

        function test_7_code_colours() {
            configure({"codeTheme": "dark"});
            var code = findChild(body.chatView, "codeBlock");
            verify(sameColor(code.color, "#1e1e1e"));
            screenshot(root, "prefs-code-dark");
            configure({"codeTheme": "nonsense"});
            verify(findChild(body.chatView, "codeBlock").color.a < 0.2, "an unknown theme falls back to the Plasma colours");
        }

        function test_8_header_buttons_can_be_hidden() {
            configure({"headerShowHistory": false, "headerShowPin": false, "headerShowSettings": false,
                       "headerShowNewChat": false, "headerShowInfo": false});
            ["historyButton", "pinButton", "settingsButton", "newChatButton", "infoButton"].forEach(function(name) {
                verify(!findChild(header, name).visible, name);
            });
            verify(findChild(header, "moreButton").visible, "More always stays");
            // In a narrow popup the history's "Back to chat" stays.
            root.width = 480;
            chat.historyOnlyMode = true;
            wait(100);
            verify(body.historyFull);
            verify(findChild(header, "historyButton").visible, "the way back from the history");
            chat.historyOnlyMode = false;
            wait(100);
            screenshot(root, "prefs-header-minimal-narrow");
        }

        function test_9_folder_bar_can_be_hidden_but_not_in_opencode() {
            configure({"showWorkspaceBar": false});
            verify(!bar.visible);
            chat.openCodeMode = true;
            verify(bar.visible, "OpenCode chats keep the agent profile");
            chat.openCodeMode = false;
            configure({});
            verify(bar.visible);
        }

        function test_10_follow_new_content_off() {
            var many = [];
            for (var i = 0; i < 30; i++)
                many.push({role: i % 2 ? "assistant" : "user", content: "Message " + i + "\nwith a second line", time: "14:30"});
            chat.messages = many;
            wait(100);
            chat.scrollToBottom(true);
            wait(100);
            verify(list().atYEnd);
            configure({"autoScroll": false});
            var lastBefore = list().itemAtIndex(29);
            var yBefore = lastBefore.mapToItem(list(), 0, 0).y;
            chat.loading = true;
            chat.messages = many.concat([{role: "assistant", content: "A long answer\n\n\n\n\n\nthat grows\n\n\n\nand grows", time: "14:31"}]);
            wait(200);
            fuzzyCompare(list().itemAtIndex(29).mapToItem(list(), 0, 0).y, yBefore, 1, "the last message didn't move");
            verify(!list().atYEnd, "the view stayed where it was");
            verify(chat.userScrolledUp, "\"New messages\" shows");
            // With the default it follows.
            chat.loading = false;
            configure({});
            chat.scrollToBottom(true);
            chat.loading = true;
            chat.messages = chat.messages.concat([{role: "assistant", content: "More\n\n\n\n\n\ntext", time: "14:32"}]);
            wait(200);
            verify(list().atYEnd, "follows by default");
            chat.loading = false;
        }

        function test_11_new_chat_each_time_it_opens() {
            chat.expanded = false;
            chat.expanded = true;
            wait(50);
            compare(chat.calls.filter(function(c) { return c.name === "create"; }).length, 0, "not by default");
            configure({"newChatOnOpen": true});
            chat.expanded = false;
            chat.expanded = true;
            wait(50);
            compare(chat.calls.filter(function(c) { return c.name === "create"; }).length, 1, "a new chat");
            chat.messages = [];
            chat.expanded = false;
            chat.expanded = true;
            wait(50);
            compare(chat.calls.filter(function(c) { return c.name === "create"; }).length, 1, "an empty chat is reused");
            chat.messages = sample;
            chat.loading = true;
            chat.expanded = false;
            chat.expanded = true;
            wait(50);
            compare(chat.calls.filter(function(c) { return c.name === "create"; }).length, 1, "not while a reply is written");
            chat.loading = false;
        }

        function test_12_ask_before_deleting_a_chat() {
            chat.historyOnlyMode = true;
            wait(600);
            var history = body.sessionList;
            verify(history !== null);
            history.removeChat(chat.sessions[1]);
            compare(chat.calls.filter(function(c) { return c.name === "deleteSession"; }).length, 1, "deleted at once by default");
            chat.sessions = [{value: "a", text: "Trip planning", count: 2}, {value: "b", text: "Python loops", count: 2}];
            chat.calls = [];
            configure({"confirmDeleteChat": true});
            var popup = chat.prefs.deleteChat("b", "Python loops", history);
            verify(popup !== null);
            tryVerify(() => popup.opened);
            compare(chat.calls.length, 0, "only asked");
            verify(findChild(popup.contentItem, "chatDeleteText").text.indexOf("Python loops") >= 0);
            screenshot(root.Window.window.contentItem, "prefs-delete-confirm");
            mouseClick(findChild(popup.contentItem, "chatDeleteCancel"));
            wait(100);
            compare(chat.calls.length, 0, "cancelled");
            popup = history.removeChat(chat.sessions[1]);
            verify(popup !== null, "the history asks too");
            tryVerify(() => popup.opened);
            popup.accept();
            compare(chat.calls.filter(function(c) { return c.name === "deleteSession"; }).length, 1);
            compare(chat.calls.filter(function(c) { return c.name === "deleteSession"; })[0].args[0], "b");
        }

        function test_13_time_format() {
            var message = sample[0];
            compare(nav.formatMessageTime(message, 0), "14:30", "as the message has it");
            configure({"timeFormat": "12h"});
            compare(nav.formatMessageTime(message, 0), "2:30 PM");
            configure({"timeFormat": "system"});
            var shown = nav.formatMessageTime(message, 0);
            compare(shown, new Date(message.at).toLocaleTimeString(Qt.locale(), Locale.ShortFormat));
            compare(nav.formatMessageTime({time: "09:05"}, 0), "09:05", "a message without a timestamp keeps its time");
            configure({});
            compare(nav.formatMessageTime(message, 0), "14:30");
        }

        function test_14_narrow_with_options() {
            root.width = 480;
            configure({"chatStyle": "bubbles", "chatFontScale": 120, "chatDensity": "roomy", "codeTheme": "solarizedDark", "accentColor": "#2e7d32"});
            wait(200);
            screenshot(root, "prefs-narrow-options");
        }
    }
}
