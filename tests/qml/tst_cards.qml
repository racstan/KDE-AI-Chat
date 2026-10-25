// The permission, question and error cards in the message list: they stay
// inside the list's right edge, the permission card shows the command in
// monospace with Allow as the main choice, the question isn't printed twice,
// and errors are in plain language with Try again / Open settings.
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
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
        name: "Cards"

        readonly property var permission: ({role: "permission_request", model: "OpenCode", status: "pending", canAlways: true, permissionId: "p1",
            tool: "bash", arguments: ["rm -rf build/", "ls -la"], content: "OpenCode asks for permission: **bash**\n\n```\nrm -rf build/\n```"})
        readonly property var question: ({role: "question_request", model: "OpenCode", status: "pending", questionId: "q1", allowCustom: true,
            content: "OpenCode is asking:\n\n**Folders**: Which folders should I keep?",
            questions: [{header: "Folders", question: "Which folders should I keep?", multiple: true,
                         options: [{label: "build/cache"}, {label: "build/docs"}, {label: "None"}]}]})

        function delegateAt(i) {
            var delegate = view.list.itemAtIndex(i);
            verify(delegate, "delegate " + i);
            return delegate;
        }

        function init() {
            chat.calls = [];
            chat.messages = [];
        }

        // The bubble's right edge, in the list's coordinates.
        function rightEdge(index) {
            var bubble = findChild(delegateAt(index), "bubble");
            return bubble.mapToItem(view.list, bubble.width, 0).x;
        }

        function test_1_cards_stay_inside_the_list() {
            chat.messages = [{role: "user", content: "Clean up", time: "10:00"}, permission, question,
                {role: "error", content: "Request to https://x failed (HTTP 429)", time: "10:01"},
                {role: "assistant", model: "m", content: "Done", time: "10:02"}];
            wait(100);
            for (var i = 1; i <= 3; i++)
                verify(rightEdge(i) <= view.list.width, "message " + i + " ends at " + rightEdge(i) + " inside " + view.list.width);
            // And also in a narrow popup.
            root.width = 360;
            wait(100);
            for (i = 1; i <= 3; i++)
                verify(rightEdge(i) <= view.list.width, "message " + i + " ends at " + rightEdge(i) + " inside the narrow list " + view.list.width);
            screenshot(root, "cards-narrow");
            root.width = 520;
        }

        function test_2_permission_shows_the_command_in_monospace_with_allow_as_main_choice() {
            chat.messages = [permission];
            wait(100);
            var d = delegateAt(0);
            var command = findChild(d, "permissionCommand");
            verify(command && command.visible, "the command is shown");
            compare(command.text, "rm -rf build/\nls -la");
            compare(command.fontFamily, Kirigami.Theme.fixedWidthFont.family);
            verify(!findChild(d, "messageBody").visible, "the message text that repeats it is not shown");
            verify(findChild(d, "allowButton").highlighted, "Allow is the main choice");
            verify(!findChild(d, "rejectButton").highlighted);
            verify(!findChild(d, "alwaysAllowButton").highlighted);
            compare(findChild(d, "permissionTool").text, "Wants to use bash");
            mouseClick(findChild(d, "allowButton"));
            compare(chat.calls[0].name, "permission");
            compare(chat.calls[0].args, ["p1", true, false]);
            screenshot(root, "cards-permission");
        }

        function test_3_permission_with_only_text_shows_it_in_monospace() {
            chat.messages = [{role: "permission_request", model: "OpenCode", status: "pending", permissionId: "p2", content: "Run command: rm -rf build/"}];
            wait(100);
            compare(findChild(delegateAt(0), "permissionCommand").text, "Run command: rm -rf build/");
        }

        function test_4_question_is_not_printed_twice() {
            chat.messages = [question];
            wait(100);
            var d = delegateAt(0);
            verify(!findChild(d, "messageBody").visible, "the card shows the question, not the message text");
            var texts = findChildren(d, "questionText");
            compare(texts.length, 1);
            compare(texts[0].text, "Which folders should I keep?");
            compare(findChild(d, "questionHeader").text, "Folders");
            // Header and question the same: shown once.
            chat.messages = [{role: "question_request", model: "OpenCode", status: "pending", questionId: "q2", allowCustom: true,
                content: "x", questions: [{header: "Which one?", question: "Which one?", options: [{label: "A"}]}]}];
            wait(100);
            d = delegateAt(0);
            verify(!findChild(d, "questionHeader").visible);
            compare(findChild(d, "questionText").text, "Which one?");
            screenshot(root, "cards-question");
        }

        function test_5_answered_question_keeps_the_question_and_shows_the_answer() {
            var answered = Object.assign({}, question, {status: "answered", submittedAnswer: "None"});
            chat.messages = [answered];
            wait(100);
            var d = delegateAt(0);
            compare(findChild(d, "questionText").text, "Which folders should I keep?");
        }

        function test_6_error_in_plain_language_with_try_again_and_settings() {
            chat.messages = [{role: "user", content: "Hi", time: "10:00"},
                {role: "error", content: "The provider rejected the API key (HTTP 401). Check the key in Settings. Incorrect API key provided", time: "10:00"}];
            wait(100);
            var d = delegateAt(1);
            var body = findChild(d, "messageBody");
            compare(body.text, "Your API key was rejected. Check the key for this provider in Settings.");
            verify(body.text.indexOf("401") < 0 && body.text.indexOf("\u26a0") < 0);
            var retry = findChild(d, "retryButton");
            var settings = findChild(d, "settingsButton");
            verify(retry.visible && settings.visible);
            compare(retry.text, "Try again");
            compare(settings.text, "Open settings");
            screenshot(root, "cards-error-key");
            mouseClick(settings);
            compare(chat.calls[chat.calls.length - 1].name, "openSettings");
            mouseClick(retry);
            compare(chat.calls[chat.calls.length - 1].name, "retry");
            compare(chat.calls[chat.calls.length - 1].args, [1]);
            // The original text is one click away.
            var details = findChild(d, "detailsButton");
            verify(details.visible);
            verify(!findChild(d, "errorDetail").visible);
            mouseClick(details);
            verify(findChild(d, "errorDetail").visible);
            verify(findChild(d, "errorDetail").text.indexOf("HTTP 401") >= 0);
        }

        function test_7_open_settings_only_where_it_helps() {
            chat.messages = [{role: "error", content: "Request to https://x failed (HTTP 429): slow down", time: "10:00"}];
            wait(100);
            var d = delegateAt(0);
            verify(findChild(d, "retryButton").visible);
            verify(!findChild(d, "settingsButton").visible, "a rate limit isn't fixed in the settings");
            chat.messages = [{role: "error", content: "OpenCode isn't installed (no `opencode` command found).", time: "10:00"}];
            wait(100);
            d = delegateAt(0);
            verify(findChild(d, "settingsButton").visible);
            verify(findChild(d, "messageBody").text.indexOf("isn't installed") > 0);
        }

        function test_8_your_messages_are_plain_and_on_the_right() {
            chat.messages = [{role: "user", content: "Hi there", time: "10:00"}, {role: "assistant", model: "m", content: "Hello", time: "10:00"},
                             {role: "queued", content: "Later", time: "10:01"}];
            wait(100);
            var mine = findChild(delegateAt(0), "bubble");
            var reply = findChild(delegateAt(1), "bubble");
            compare(mine.color.a, 0, "no coloured box");
            compare(mine.border.width, 0, "no edge");
            verify(mine.width < reply.width, "narrower than a reply");
            verify(mine.width <= view.list.width * 0.81, "at most about 80% of the view");
            compare(mine.mapToItem(view.list, mine.width, 0).x, reply.mapToItem(view.list, reply.width, 0).x, "right edge as a reply's right edge: anchored right");
            compare(findChild(delegateAt(0), "messageBody").alignRight, true, "text right-aligned");
            compare(findChild(delegateAt(1), "messageBody").alignRight, false);
            compare(findChild(delegateAt(2), "bubble").color.a, 0);
            // Errors and agent requests keep an edge but no fill.
            chat.messages = [permission, {role: "error", content: "Request to https://x failed (HTTP 500)"}];
            wait(100);
            for (var i = 0; i < 2; i++) {
                var card = findChild(delegateAt(i), "bubble");
                compare(card.color.a, 0);
                compare(card.border.width, 1);
            }
            screenshot(root, "cards-plain-messages");
        }
    }
}
