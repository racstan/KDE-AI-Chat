// Direct mode: the model asks the user a question with the ask_user tool. The
// real request code (chat/DirectRequest.qml, DirectToolRounds.qml, ReplyEvents.qml,
// SendController.qml, MessageEdits.qml) runs against a fake XMLHttpRequest that
// plays back streamed provider replies, with the real chat/QuestionCard.qml
// answering: tap an option, type an answer, dismiss, stop, or write something else.
import QtQuick
import QtTest
import org.kde.kirigami as Kirigami
import "../../org.kde.plasma.kdeaichat/contents/ui/chat" as Chat

Item {
    id: root
    width: 480
    height: 360

    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }

    property var xhrs: []
    function makeXhr() {
        var x = {"readyState": 0, "status": 0, "responseText": "", "sent": null, "aborted": false,
            "open": function() {}, "setRequestHeader": function() {},
            "send": function(body) { x.sent = JSON.parse(body); },
            "abort": function() { x.aborted = true; },
            "play": function(status, chunks) {
                x.status = status;
                for (var i = 0; i < chunks.length; i++) {
                    x.responseText += chunks[i];
                    x.readyState = 3;
                    x.onreadystatechange();
                }
                x.readyState = 4;
                x.onreadystatechange();
            }};
        root.xhrs.push(x);
        return x;
    }

    function sse(obj) { return "data: " + JSON.stringify(obj) + "\n\n"; }
    function askStream(args, id) {
        var json = JSON.stringify(args);
        var cut = Math.floor(json.length / 2);
        return [sse({"choices": [{"delta": {"content": "I need one detail. "}}]}),
                sse({"choices": [{"delta": {"tool_calls": [{"index": 0, "id": id || "call_1", "type": "function", "function": {"name": "ask_user", "arguments": json.substring(0, cut)}}]}}]}),
                sse({"choices": [{"delta": {"tool_calls": [{"index": 0, "function": {"arguments": json.substring(cut)}}]}}]}),
                sse({"choices": [{"delta": {}, "finish_reason": "tool_calls"}]}), "data: [DONE]\n\n"];
    }
    function textStream(text) {
        return [sse({"choices": [{"delta": {"content": text}}]}), "data: [DONE]\n\n"];
    }

    // The widget root, as far as these modules use it.
    QtObject {
        id: chat
        property var plasmoid: QtObject { property var configuration: ({"contextMessageLimit": -1, "enableSystemPrompt": false, "disableStreaming": false, "requestTimeout": 0}) }
        property var sessions: [{"value": "s1", "messages": []}]
        property string currentSessionId: "s1"
        property string currentSessionTitle: "Pick a thing"
        property var messages: []
        property bool loading: false
        property var activeXhr: null
        property int requestGeneration: 0
        property string activeRequestSessionId: ""
        property string compiledSystemPrompt: ""
        property string currentStreamKey: ""
        property int currentStreamIndex: -1
        property string currentStreamText: ""
        property string currentStreamReasoning: ""
        property string currentStreamExtractedReasoning: ""
        property bool streamingResponse: false
        property var currentStreamUsage: ({})
        property var walletApiKeys: ({})
        property var wallet: QtObject { property bool usable: true }
        property string chatInputText: ""
        property var attachedFiles: []
        property var promptTemplates: []
        property int sent: 0
        property string schedulerResumeSessionId: ""
        property int saves: 0
        property var errors: []
        property var streamBuffer: Chat.StreamBuffer { target: chat; maxChars: 2000000 }
        signal clearChatInput()
        onMessagesChanged: {
            if (chat.currentStreamIndex >= 0)
                chat.currentStreamIndex = indexOfId(chat.currentStreamKey);
        }
        function indexOfId(id) {
            for (var i = 0; i < messages.length; i++)
                if (messages[i].id === id) return i;
            return -1;
        }
        function sessionIndexById(id) { return 0; }
        function switchSession(id) {}
        function getSessionProperty(id, key, fallback) { return fallback; }
        function effectiveConfig(id) { return {"mode": "provider", "variant": "", "direct": {"provider": "p", "model": ""}}; }
        function requestIsCurrent(s, g) { return sender.requestIsCurrent(s, g); }
        function applyBackendEvent(e, m, x) { replies.applyBackendEvent(e, m, x); }
        function updateMessageAt(i, f) { replies.updateMessageAt(i, f); }
        function findRequestMessage(r, f, id) { return replies.findRequestMessage(r, f, id); }
        function resetProviderStreamingState() { replies.resetProviderStreamingState(); }
        function saveCurrentSessionState(t) { saves++; }
        function pushErrorMessage(t) { errors = errors.concat([t]); }
        function triggerNotificationSound() {}
        function maybeGenerateChatTitle() {}
        function processNextQueuedMessage() {}
        function invalidateActiveRequest(p) { sender.invalidateActiveRequest(p); }
        function stopStreaming() { sender.stopStreaming(); }
        function scrollToBottom() {}
        function ensureWalletLoaded() {}
        function attachmentsReadyToSend() { return true; }
        function cleanupTemporaryAttachment(p) {}
        function nameChatFromFirstMessage(t) {}
        property bool openCodeMode: false
        property bool piMode: false
        function applySessionSource(s) {}
        function setCurrentSessionSource() {}
        function getEffectiveProvider(id) { return "p"; }
        function getProviderConfig(p, id) { return root.cfg; }
        function providerDisplayName(id) { return "Provider"; }
        function doDirectRequest(c, s, g) { sent++; }
        function respondToQuestion(id, v, reject) { edits.respondToQuestion(id, v, reject); }
        function questionOptionSelected(id, q, l) { return edits.questionOptionSelected(id, q, l); }
        function toggleQuestionOption(id, q, l, m) { edits.toggleQuestionOption(id, q, l, m); }
        function submitQuestionAnswer(id, q, f) { edits.submitQuestionAnswer(id, q, f); }
    }

    Chat.ReplyEvents {
        id: replies
        chat: chat
        notifierRef: QtObject {
            id: notice
            function replyFinished() {}
            function failed() {}
            property var needed: []
            function inputNeeded(chatId, title, message) { needed = needed.concat([message.role + ":" + message.questionId]); }
            function inputResolved() {}
        }
    }
    Chat.DirectRequest {
        id: direct
        chat: chat
        xhrFactory: root.makeXhr
    }
    Chat.SendController {
        id: sender
        chat: chat
        notifierRef: QtObject { function failed() {} }
        directToolsRef: direct.toolRounds
    }
    Chat.MessageEdits {
        id: edits
        chat: chat
        directToolsRef: direct.toolRounds
    }

    readonly property var cfg: ({"type": "openai-compat", "baseUrl": "https://api.test/v1", "apiKey": "k", "model": "test-model", "headers": {}})

    // The newest question card message.
    readonly property var questionMessage: {
        var list = chat.messages;
        for (var i = list.length - 1; i >= 0; i--)
            if (list[i].role === "question_request") return list[i];
        return ({});
    }

    Chat.QuestionCard {
        id: card
        x: 10
        y: 10
        width: 400
        chat: chat
        message: root.questionMessage
    }

    HarnessTestCase {
        id: tc
        name: "DirectAskUser"

        function init() {
            root.xhrs = [];
            chat.messages = [{"id": "u1", "role": "user", "content": "Help me pick a colour", "at": 1}];
            chat.loading = false;
            chat.currentStreamIndex = -1;
            chat.currentStreamText = "";
            chat.currentStreamReasoning = "";
            chat.errors = [];
            chat.sent = 0;
            chat.plasmoid.configuration.allowAskUser = true;
            notice.needed = [];
            direct.toolRounds.pending = null;
        }

        function start(model) {
            var generation = sender.beginRequest("s1");
            var cfg = Object.assign({}, root.cfg);
            if (model) cfg.model = model;
            direct.sendDirectRequest(cfg, "s1", generation, {});
        }

        function findButton(item, text) {
            if (!item) return null;
            if (item.text === text && item.clicked !== undefined && item.visible) return item;
            var kids = item.children || [];
            for (var i = 0; i < kids.length; i++) {
                var found = findButton(kids[i], text);
                if (found) return found;
            }
            return null;
        }

        function roles() { return chat.messages.map(function(m) { return m.role; }); }

        function askAndWait(args) {
            start();
            compare(root.xhrs.length, 1);
            root.xhrs[0].play(200, root.askStream(args));
            compare(root.questionMessage.status, "pending");
        }

        function test_request_offers_the_tool_and_the_question_card_appears() {
            askAndWait({"question": "Which colour?", "options": ["Red", "Blue"]});
            var tools = root.xhrs[0].sent.tools;
            compare(tools.length, 1);
            compare(tools[0].function.name, "ask_user");
            compare(roles().join(","), "user,assistant,question_request");
            // The call shows as a tool card on the reply, and is kept with it.
            var reply = chat.messages[1];
            compare(reply.content, "I need one detail. ");
            compare(reply.tools["call_1"].name, "ask_user");
            compare(reply.tools["call_1"].status, "running");
            compare(reply.toolRounds[0].calls[0].args.question, "Which colour?");
            // The same card OpenCode and Pi questions use.
            var q = root.questionMessage;
            compare(q.harness, "direct");
            compare(q.questions[0].question, "Which colour?");
            compare(q.questions[0].options.length, 2);
            compare(q.allowCustom, true);
            verify(chat.loading, "the request waits for the answer");
            // With the popup closed this is what sends the "Input needed" notification.
            compare(notice.needed.length, 1);
            verify(notice.needed[0].indexOf("question_request:ask-") === 0);
            verify(findButton(card, "Red"));
            tc.screenshot(root, "direct-ask-user-pending");
        }

        function test_tapping_an_option_answers_and_the_request_continues() {
            askAndWait({"question": "Which colour?", "options": ["Red", "Blue"]});
            mouseClick(findButton(card, "Blue"));
            compare(root.xhrs.length, 2);
            compare(root.questionMessage.status, "answered");
            compare(root.questionMessage.submittedAnswer, "Blue");
            // The next request carries the call and its result in OpenAI format.
            var sent = root.xhrs[1].sent.messages;
            compare(sent.map(function(m) { return m.role; }).join(","), "user,assistant,tool");
            compare(sent[1].tool_calls[0].id, "call_1");
            compare(sent[1].tool_calls[0].function.name, "ask_user");
            compare(sent[2].tool_call_id, "call_1");
            compare(sent[2].content, "Blue");
            root.xhrs[1].play(200, root.textStream("Blue it is."));
            compare(roles().join(","), "user,assistant,question_request,assistant");
            compare(chat.messages[1].tools["call_1"].status, "done");
            compare(chat.messages[1].tools["call_1"].output, "Blue");
            compare(chat.messages[3].content, "Blue it is.");
            verify(!chat.loading);
            // Saved and sent again later, the history is valid: call, result, answer.
            var history = direct.buildDirectRequestParts("s1", "openai", true).messages;
            compare(history.map(function(m) { return m.role; }).join(","), "user,assistant,tool,assistant");
            compare(history[3].content, "Blue it is.");
            // ... and as plain text for a model without tools.
            var plain = direct.buildDirectRequestParts("s1", "openai", false).messages;
            compare(plain.map(function(m) { return m.role; }).join(","), "user,assistant,assistant");
            tc.screenshot(root, "direct-ask-user-answered");
        }

        function test_a_typed_answer_works() {
            askAndWait({"question": "What should I call it?"});
            // The card's text field has no objectName: find it by its placeholder.
            var typed = null;
            var stack = [card];
            while (stack.length > 0 && !typed) {
                var item = stack.pop();
                if (item.placeholderText !== undefined && item.accepted !== undefined) typed = item;
                for (var i = 0; i < (item.children || []).length; i++) stack.push(item.children[i]);
            }
            verify(typed, "typed answer field");
            typed.text = "Project Dawn";
            mouseClick(findChild(card, "submitButton"));
            compare(root.xhrs.length, 2);
            compare(root.xhrs[1].sent.messages[2].content, "Project Dawn");
            compare(root.questionMessage.submittedAnswer, "Project Dawn");
        }

        function test_no_typing_when_the_model_does_not_allow_it() {
            askAndWait({"question": "Pick", "options": ["A", "B"], "allow_typed": false});
            compare(root.questionMessage.allowCustom, false);
        }

        function test_dismiss_tells_the_model_the_user_did_not_answer() {
            askAndWait({"question": "Which colour?", "options": ["Red"]});
            mouseClick(findButton(card, "Dismiss"));
            compare(root.questionMessage.status, "dismissed");
            compare(root.xhrs.length, 2);
            verify(root.xhrs[1].sent.messages[2].content.indexOf("without answering") >= 0);
        }

        function test_stop_ends_the_question_and_keeps_a_valid_history() {
            askAndWait({"question": "Which colour?", "options": ["Red"]});
            chat.stopStreaming();
            compare(root.questionMessage.status, "dismissed");
            verify(!chat.loading);
            compare(root.xhrs.length, 1, "no further request");
            compare(chat.messages[1].tools["call_1"].output, "The user did not answer.");
            var history = direct.buildDirectRequestParts("s1", "openai", true).messages;
            compare(history.map(function(m) { return m.role; }).join(","), "user,assistant,tool");
            // An old answer to the closed question does nothing.
            chat.respondToQuestion(root.questionMessage.questionId, "Red", false);
            compare(root.xhrs.length, 1);
        }

        function test_writing_a_message_instead_of_answering_stops_and_sends_it() {
            askAndWait({"question": "Which colour?", "options": ["Red"]});
            chat.chatInputText = "Never mind, something else";
            sender.sendMessage();
            compare(root.questionMessage.status, "dismissed");
            compare(root.xhrs.length, 1, "the old request is not continued");
            compare(chat.messages[chat.messages.length - 1].role, "user");
            compare(chat.messages[chat.messages.length - 1].content, "Never mind, something else");
            compare(chat.sent, 1);
            compare(chat.messages[1].tools["call_1"].output, "The user did not answer.");
        }

        function test_the_setting_turns_the_tool_off() {
            chat.plasmoid.configuration.allowAskUser = false;
            start();
            verify(!("tools" in root.xhrs[0].sent), "no tools offered");
            root.xhrs[0].play(200, root.textStream("Hello"));
            compare(chat.messages[1].content, "Hello");
        }

        function test_a_model_that_refuses_tools_gets_the_request_again_without_them() {
            start("picky-model");
            root.xhrs[0].play(400, ['{"error":{"message":"tools are not supported by this model"}}']);
            compare(root.xhrs.length, 2);
            verify(!("tools" in root.xhrs[1].sent));
            root.xhrs[1].play(200, root.textStream("Fine without."));
            compare(chat.messages[1].content, "Fine without.");
            compare(chat.errors.length, 0);
            // This model is remembered: the next request leaves tools out from the start.
            chat.messages = chat.messages.concat([{"id": "u2", "role": "user", "content": "again", "at": 2}]);
            root.xhrs = [];
            start("picky-model");
            verify(!("tools" in root.xhrs[0].sent));
        }

        function test_an_unknown_tool_gets_an_error_result_and_the_request_goes_on() {
            start();
            root.xhrs[0].play(200, [
                sse({"choices": [{"delta": {"tool_calls": [{"index": 0, "id": "c1", "function": {"name": "nope", "arguments": "{}"}}]}}]}),
                "data: [DONE]\n\n"]);
            compare(root.xhrs.length, 2);
            verify(root.xhrs[1].sent.messages[2].content.indexOf("Unknown tool") >= 0);
            compare(chat.messages[1].tools["c1"].status, "error");
        }
    }
}
