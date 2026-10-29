// Editing, retrying or regenerating while a reply streams and a message is queued: one request
// runs, the replaced one is aborted, the queued message stays and goes after the new reply. The
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
        property int saves: 0
        property var errors: []
        property var streamBuffer: Chat.StreamBuffer { target: chat; maxChars: 2000000 }
        // No pictures in these replies (chat/ImageStore.qml is tested in tst_image_store.qml).
        property var imageStore: QtObject {
            function hasImages(message) { return false; }
            function takeInlineImages(sessionId, reply) { return reply; }
            function addFromReply() {}
        }
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
        function clearCurrentOpenCodeSessionIfNeeded() {}
        function messagesDropped(id, before) {}
        function sendMessageByIndex(i) { sender.sendMessageByIndex(i); }
        function validateProviderConfig(p, c) { return ""; }
        property bool userScrolledUp: false
        property int editingMessageIndex: -1
        property string editingDraft: ""
        property int queueCounter: 0
        function processNextQueuedMessage() { sender.processNextQueuedMessage(); }
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
        function doDirectRequest(c, s, g) { sent++; direct.sendDirectRequest(c, s, g, {}); }
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

    HarnessTestCase {
        id: tc
        name: "EditWhileQueued"

        function init() {
            root.xhrs = [];
            chat.messages = [{"id": "u1", "role": "user", "content": "First", "at": 1}];
            chat.loading = false;
            chat.activeXhr = null;
            chat.currentStreamIndex = -1;
            chat.currentStreamText = "";
            chat.errors = [];
            chat.sent = 0;
        }

        function roles() { return chat.messages.map(function(m) { return m.role; }).join(","); }

        // A reply is streaming (not finished) and "Second" waits in the queue.
        function streamingWithQueue() {
            chat.loading = true;
            var generation = sender.beginRequest("s1");
            direct.sendDirectRequest(root.cfg, "s1", generation, {});
            root.xhrs[0].status = 200;
            root.xhrs[0].responseText = root.textStream("Partial")[0];
            root.xhrs[0].readyState = 3;
            root.xhrs[0].onreadystatechange();
            chat.messages = chat.messages.concat([{"id": "q1", "role": "queued", "content": "Second", "at": 2}]);
            compare(root.xhrs.length, 1);
            verify(chat.loading);
        }

        function checkOneLive() {
            compare(root.xhrs.length, 2, "one new request, not two");
            verify(root.xhrs[0].aborted, "the replaced request was really aborted");
            verify(!root.xhrs[1].aborted);
            compare(roles(), "user,queued");
            verify(root.xhrs[1].sent.messages.map(function(m) { return m.content; }).join("|").indexOf("Second") < 0, "the queued message is not in the new request");
            // The new reply finishes; only now the queued message is sent.
            root.xhrs[1].play(200, root.textStream("Fresh"));
            compare(root.xhrs.length, 3);
            verify(root.xhrs[2].sent.messages.map(function(m) { return m.content; }).join("|").indexOf("Second") >= 0);
            verify(!root.xhrs[2].aborted);
            compare(roles().split(",").slice(0, 3).join(","), "user,assistant,user");
        }

        function test_regenerate_keeps_one_request_and_the_queue_goes_after() {
            streamingWithQueue();
            edits.regenerateResponse(1);
            checkOneLive();
        }

        function test_editing_the_prompt_keeps_one_request() {
            streamingWithQueue();
            chat.editingMessageIndex = 0;
            chat.editingDraft = "First, edited";
            edits.saveEditedMessage();
            checkOneLive();
            compare(chat.messages[0].content, "First, edited");
        }

        function test_retry_after_an_error_keeps_one_request() {
            streamingWithQueue();
            chat.messages = [chat.messages[0], {"role": "error", "content": "boom"}, chat.messages[2]];
            edits.retryFailedMessage(1);
            checkOneLive();
        }
    }
}
