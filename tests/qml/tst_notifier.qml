// Notifier decides when to notify. The real sender (a desktop notification)
// and the sound command are replaced by recorders: nothing leaves the test.
import QtQuick
import QtTest
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 200
    height: 100

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    property var sent: []
    property int sounds: 0

    Chat.Notifier {
        id: notifier
        sender: function(title, text, chatId, isError) { root.sent.push({"title": title, "text": text, "chatId": chatId, "isError": isError}); }
        soundPlayer: function() { root.sounds++; }
    }

    // The widget root, as far as "input needed" reads and calls it.
    QtObject {
        id: fakeChat
        property var plasmoid: QtObject { property var configuration: QtObject { property bool notifyOnInput: true } }
        property string currentSessionId: "c1"
        property var messages: []
        property var answers: []
        function respondToQuestion(id, value, reject) { answers = answers.concat([["question", id, value, reject]]); }
        function respondToPermission(id, approved, always) { answers = answers.concat([["permission", id, approved, always]]); }
    }

    property var inputs: []
    property var closed: []
    Chat.Notifier {
        id: inputNotifier
        chat: fakeChat
        popupOpen: false
        // A stand-in for the desktop notification: close() is recorded.
        inputSender: function(spec) {
            root.inputs.push(spec);
            return {"close": function() { root.closed.push(spec.id); }};
        }
    }

    TestCase {
        name: "Notifier"
        when: windowShown

        function init() {
            root.sent = [];
            root.sounds = 0;
            notifier.popupOpen = false;
            notifier.replyEnabled = true;
            notifier.errorEnabled = true;
            notifier.scheduledEnabled = true;
            notifier.soundEnabled = true;
        }

        function test_reply_notifies_only_when_popup_closed() {
            verify(notifier.replyFinished("c1", "Trip plan", "Here is **the plan**."));
            compare(root.sent.length, 1);
            compare(root.sent[0].title, "Trip plan");
            compare(root.sent[0].text, "Here is the plan.");
            compare(root.sent[0].chatId, "c1");
            compare(root.sent[0].isError, false);
            notifier.popupOpen = true;
            verify(!notifier.replyFinished("c1", "Trip plan", "again"));
            compare(root.sent.length, 1);
        }

        function test_reply_setting_off() {
            notifier.replyEnabled = false;
            verify(!notifier.replyFinished("c1", "T", "x"));
            compare(root.sent.length, 0);
            notifier.errorEnabled = false;
            notifier.replyEnabled = true;
            verify(notifier.replyFinished("c1", "T", "x"), "error setting does not affect replies");
        }

        function test_error_notifies_only_when_popup_closed_and_enabled() {
            verify(notifier.failed("c2", "Debugging", "HTTP 401: bad key"));
            compare(root.sent.length, 1);
            compare(root.sent[0].title, "Debugging: request failed");
            compare(root.sent[0].text, "HTTP 401: bad key");
            compare(root.sent[0].isError, true);
            notifier.popupOpen = true;
            verify(!notifier.failed("c2", "Debugging", "boom"));
            notifier.popupOpen = false;
            notifier.errorEnabled = false;
            verify(!notifier.failed("c2", "Debugging", "boom"));
            compare(root.sent.length, 1);
        }

        function test_scheduled_notifies_even_with_popup_open() {
            notifier.popupOpen = true;
            verify(notifier.scheduledRan("c3", "Morning news", "Summarise the headlines"));
            compare(root.sent.length, 1);
            compare(root.sent[0].title, "Morning news");
            compare(root.sent[0].chatId, "c3");
            notifier.scheduledEnabled = false;
            verify(!notifier.scheduledRan("c3", "Morning news", "x"));
            compare(root.sent.length, 1);
        }

        function test_sound_is_its_own_setting() {
            verify(notifier.playSound());
            compare(root.sounds, 1);
            notifier.soundEnabled = false;
            verify(!notifier.playSound());
            compare(root.sounds, 1);
            notifier.soundEnabled = true;
            notifier.popupOpen = true;
            notifier.replyEnabled = false;
            verify(notifier.playSound(), "sound does not depend on notifications");
        }

        function test_fallback_texts_and_untitled_chat() {
            notifier.replyFinished("c1", "  ", "");
            compare(root.sent[0].title, "KDE AI Chat");
            compare(root.sent[0].text, "The reply is ready.");
        }

        // --- Input needed ---

        readonly property var question: ({role: "question_request", model: "m", status: "pending", questionId: "q1", allowCustom: true,
            questions: [{question: "Which colour?", options: [{label: "Red"}, {label: "Blue"}]}], content: "m is asking"})
        readonly property var permission: ({role: "permission_request", model: "OpenCode", status: "pending", permissionId: "p1", tool: "bash",
            arguments: ["rm -rf build/"], content: "OpenCode asks for permission"})

        function initInput() {
            root.inputs = [];
            root.closed = [];
            fakeChat.answers = [];
            fakeChat.messages = [];
            fakeChat.currentSessionId = "c1";
            inputNotifier.popupOpen = false;
            inputNotifier.openInputs = ({});
            fakeChat.plasmoid.configuration.notifyOnInput = true;
        }

        function test_input_question_has_buttons_and_a_reply_box() {
            initInput();
            verify(inputNotifier.inputNeeded("c1", "Colours", question));
            compare(root.inputs.length, 1);
            var spec = root.inputs[0];
            compare(spec.title, "Colours: input needed");
            verify(spec.text.indexOf("Which colour?") === 0, spec.text);
            verify(spec.text.indexOf("Red") > 0 && spec.text.indexOf("Blue") > 0);
            compare(spec.actions.map(function(a) { return a.label; }).join(","), "Red,Blue");
            compare(spec.typed, true);
            compare(spec.kind, "question");
        }

        function test_input_permission_is_allow_or_deny() {
            initInput();
            verify(inputNotifier.inputNeeded("c1", "Build", permission));
            var spec = root.inputs[0];
            compare(spec.kind, "permission");
            compare(spec.actions.map(function(a) { return a.label; }).join(","), "Allow,Deny");
            compare(spec.typed, false);
            verify(spec.text.indexOf("bash") >= 0 && spec.text.indexOf("rm -rf build/") >= 0, spec.text);
        }

        function test_input_at_most_three_buttons_and_no_typing_when_not_allowed() {
            initInput();
            var q = JSON.parse(JSON.stringify(question));
            q.questions[0].options = [{label: "A"}, {label: "B"}, {label: "C"}, {label: "D"}];
            q.allowCustom = false;
            inputNotifier.inputNeeded("c1", "T", q);
            compare(root.inputs[0].actions.length, 3);
            compare(root.inputs[0].typed, false);
        }

        function test_input_only_when_popup_closed_or_other_chat_and_enabled() {
            initInput();
            inputNotifier.popupOpen = true;
            verify(!inputNotifier.inputNeeded("c1", "T", question), "the open chat shows it itself");
            verify(inputNotifier.inputNeeded("c2", "Other", permission), "another chat than the open one");
            inputNotifier.popupOpen = false;
            fakeChat.plasmoid.configuration.notifyOnInput = false;
            verify(!inputNotifier.inputNeeded("c1", "T", question), "setting off");
            compare(root.inputs.length, 1);
        }

        function test_input_is_sent_once_per_request() {
            initInput();
            verify(inputNotifier.inputNeeded("c1", "T", question));
            verify(!inputNotifier.inputNeeded("c1", "T", question));
            compare(root.inputs.length, 1);
        }

        function test_answers_from_the_notification_answer_the_card() {
            initInput();
            inputNotifier.inputNeeded("c1", "T", question);
            verify(inputNotifier.answerInput(root.inputs[0], root.inputs[0].actions[1].value));
            compare(fakeChat.answers.length, 1);
            compare(fakeChat.answers[0].join("|"), "question|q1|Blue|false");
            inputNotifier.inputNeeded("c1", "T", permission);
            inputNotifier.answerInput(root.inputs[1], false);
            compare(fakeChat.answers[1].join("|"), "permission|p1|false|false");
            inputNotifier.inputNeeded("c1", "T", {role: "question_request", questionId: "q3", questions: [{question: "Name?"}], allowCustom: true});
            inputNotifier.answerInput(root.inputs[2], "Project Dawn");
            compare(fakeChat.answers[2].join("|"), "question|q3|Project Dawn|false");
        }

        function test_an_answer_for_another_chat_opens_that_chat_instead() {
            initInput();
            var opened = [];
            var connection = function(id) { opened.push(id); };
            inputNotifier.openChat.connect(connection);
            inputNotifier.inputNeeded("c2", "Other", question);
            verify(!inputNotifier.answerInput(root.inputs[0], "Red"));
            compare(fakeChat.answers.length, 0);
            compare(opened.join(","), "c2");
            inputNotifier.openChat.disconnect(connection);
        }

        function test_the_notification_closes_when_the_card_is_answered_in_the_widget() {
            initInput();
            fakeChat.messages = [{role: "user"}, question];
            inputNotifier.inputNeeded("c1", "T", question);
            fakeChat.messages = fakeChat.messages.slice();
            compare(root.closed.length, 0, "still pending");
            var answered = JSON.parse(JSON.stringify(question));
            answered.status = "answered";
            fakeChat.messages = [{role: "user"}, answered];
            compare(root.closed.join(","), "q1");
            compare(Object.keys(inputNotifier.openInputs).length, 0);
        }

        function test_preview_strips_markup_and_trims() {
            compare(notifier.preview("# Title\n\n- one\n- two"), "Title one two");
            compare(notifier.preview("See [docs](http://x.y) and `code`"), "See docs and code");
            compare(notifier.preview("a ```js\nlet x\n``` b"), "a b");
            var long = notifier.preview(new Array(100).join("word "), 40);
            verify(long.length <= 40, long);
            verify(long.indexOf("…") === long.length - 1);
        }
    }
}
