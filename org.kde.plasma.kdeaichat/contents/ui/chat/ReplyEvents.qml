// Applies backend events (DirectBackend.js / OpenCodeBackend.js / PiBackend.js)
// to the open chat: the streamed reply, tool and context parts, permission and
// question cards, token usage, errors and the end of a reply.
// `chat` is the widget root (main.qml).
import QtQuick
import "../backends/AgentEvents.js" as AgentEvents
import "Activity.js" as Activity
import "TimeFormat.js" as TimeFormat

QtObject {
    id: replies

    property var chat: null
    property var notifierRef: null  // chat/Notifier.qml
    property alias partialSave: partial  // saves the reply while it streams
    property var _partial: PartialSave { id: partial; chat: replies.chat }
    // Logs each finished reply and shows the budget alert it raises (chat/SpendingLog.qml).
    property var spendingLog: SpendingLog { chat: replies.chat; notifierRef: replies.notifierRef }

    // When the current stretch of thinking started and last grew (Date.now(); 0 = none).
    property real thinkStart: 0
    property real thinkEnd: 0

    // Adds the thinking so far to the reply's activity list (direct and Pi replies; changes `msg`).
    function closeThinking(msg) {
        if (Array.isArray(msg.activity))
            msg.activity = Activity.closeThinking(msg.activity, chat.currentStreamReasoning, replies.thinkStart, replies.thinkEnd);
        replies.thinkStart = 0;
        replies.thinkEnd = 0;
    }

    function resetProviderStreamingState() {
        chat.streamBuffer.flush();
        if (chat.currentStreamIndex >= 0 && chat.currentStreamIndex < chat.messages.length) {
            var copy = chat.messages.slice();
            var current = copy[chat.currentStreamIndex] = Object.assign({}, copy[chat.currentStreamIndex]);
            if (current && current.role === "assistant") {
                if (chat.currentStreamText)
                    current.content = chat.currentStreamText;
                if (chat.currentStreamReasoning)
                    current.reasoning = chat.currentStreamReasoning;
                replies.closeThinking(current);
                delete current.imageJob;
                if (!current.content && !current.reasoning && !current.tools && !chat.imageStore.hasImages(current))
                    copy.splice(chat.currentStreamIndex, 1);
                chat.messages = copy;
            }
        }
        chat.currentStreamIndex = -1;
        chat.currentStreamText = "";
        chat.currentStreamReasoning = "";
        chat.currentStreamExtractedReasoning = "";
        chat.streamingResponse = false;
    }

    // Starts the reply bubble for the request being streamed, if needed.
    function ensureStreamingMessage(model) {
        if (chat.currentStreamIndex >= 0)
            return;
        var ts = Date.now();
        chat.currentStreamKey = "m-stream-" + ts;
        var reply = {"id": chat.currentStreamKey, "role": "assistant", "content": "", "reasoning": "", "time": TimeFormat.nowTime(ts), "at": ts, "model": model};
        // The thinking and steps in order (Activity.js); OpenCode replies keep their own display.
        if (!chat.openCodeMode)
            reply.activity = [];
        replies.thinkStart = 0;
        replies.thinkEnd = 0;
        chat.messages = chat.messages.concat([reply]);
        chat.currentStreamIndex = chat.messages.length - 1;
        chat.streamingResponse = true;
    }

    // Updates fields of an existing message: update(copyOfMessage).
    function updateMessageAt(index, update) {
        if (index < 0 || index >= chat.messages.length)
            return;
        var msgs = chat.messages.slice();
        var copy = Object.assign({}, msgs[index]);
        update(copy);
        msgs[index] = copy;
        chat.messages = msgs;
    }

    function findRequestMessage(role, idField, id) {
        for (var i = chat.messages.length - 1; i >= 0; i--)
            if (chat.messages[i].role === role && chat.messages[i][idField] === id)
                return i;
        return -1;
    }

    // Applies one backend event (DirectBackend.js / OpenCodeBackend.js / PiBackend.js) to the chat.
    function applyBackendEvent(event, model, extra) {
        if (AgentEvents.isReplyEvent(event.type)) {
            replies.ensureStreamingMessage(model);
            // The thinking so far comes before this step.
            chat.streamBuffer.flush();
            replies.updateMessageAt(chat.currentStreamIndex, function(msg) {
                replies.closeThinking(msg);
                AgentEvents.applyToReply(msg, event);
                if (Array.isArray(msg.activity))
                    msg.activity = Activity.record(msg.activity, event, msg);
            });
        } else if (event.type === "permission_request" || event.type === "question_request") {
            var isPermission = event.type === "permission_request";
            if (replies.findRequestMessage(event.type, isPermission ? "permissionId" : "questionId", event.id) >= 0)
                return;
            var request = isPermission ? AgentEvents.permissionMessage(event, extra, Date.now()) : AgentEvents.questionMessage(event, extra, Date.now());
            chat.messages = chat.messages.concat([request]);
            chat.triggerNotificationSound(false);
            try { replies.notifierRef.inputNeeded(chat.currentSessionId, chat.currentSessionTitle, request); } catch (notifyErr) { console.error("Notification failed:", notifyErr); }
            chat.saveCurrentSessionState(true);
        } else if (event.type === "permission_resolved") {
            replies.updateMessageAt(replies.findRequestMessage("permission_request", "permissionId", event.id), function(msg) {
                msg.status = event.reply === "reject" ? "denied" : "allowed";
            });
        } else if (event.type === "question_resolved") {
            replies.updateMessageAt(replies.findRequestMessage("question_request", "questionId", event.id), function(msg) {
                if (msg.status !== "answered" && msg.status !== "dismissed") msg.status = event.status;
            });
        } else if (event.type === "text_delta" || event.type === "reasoning_delta") {
            replies.ensureStreamingMessage(model);
            if (event.type === "reasoning_delta") {
                replies.thinkEnd = Date.now();
                if (replies.thinkStart === 0)
                    replies.thinkStart = replies.thinkEnd;
            }
            chat.streamBuffer.add(event.type === "text_delta" ? "text" : "reasoning", event.delta);
        } else if (event.type === "images") {
            // Images the model sent: saved as files, then added to this reply.
            replies.ensureStreamingMessage(model);
            chat.imageStore.addFromReply(chat.currentSessionId, chat.currentStreamKey, event.items, Object.assign({"model": model}, event.meta || {}));
        } else if (event.type === "image_job") {
            // An image service is working: the reply shows its progress (chat/ImageJobCard.qml) until the pictures come.
            replies.ensureStreamingMessage(model);
            replies.updateMessageAt(chat.currentStreamIndex, function(msg) { msg.imageJob = event.job; });
        } else if (event.type === "usage") {
            var usage = Object.assign({}, chat.currentStreamUsage);
            if (event.input !== undefined) usage.input = event.input;
            if (event.output !== undefined) usage.output = event.output;
            if (event.cacheRead !== undefined) usage.cacheRead = event.cacheRead;
            if (event.cacheWrite !== undefined) usage.cacheWrite = event.cacheWrite;
            if (event.cost !== undefined) usage.cost = (usage.cost || 0) + event.cost;
            chat.currentStreamUsage = usage;
        } else if (event.type === "error") {
            replies.resetProviderStreamingState();
            chat.pushErrorMessage(event.message);
        } else if (event.type === "done") {
            chat.streamBuffer.flush();
            var completed = event.reason === "complete";
            if (completed && chat.currentStreamIndex >= 0) {
                var msgs = chat.messages.slice();
                var reply = Object.assign({}, msgs[chat.currentStreamIndex]);
                reply.content = chat.currentStreamText || (reply.tools || chat.imageStore.hasImages(reply) ? "" : "(empty response)");
                replies.closeThinking(reply);
                reply.reasoning = chat.currentStreamReasoning;
                delete reply.imageJob;
                reply = chat.imageStore.takeInlineImages(chat.currentSessionId, reply);
                if (chat.currentStreamUsage.input !== undefined || chat.currentStreamUsage.output !== undefined)
                    reply.tokens = {"input": chat.currentStreamUsage.input || 0, "output": chat.currentStreamUsage.output || 0};
                if (reply.tokens && (chat.currentStreamUsage.cacheRead !== undefined || chat.currentStreamUsage.cacheWrite !== undefined))
                    reply.tokens.cache = {"read": chat.currentStreamUsage.cacheRead || 0, "write": chat.currentStreamUsage.cacheWrite || 0};
                if (chat.currentStreamUsage.cost)
                    reply.cost = chat.currentStreamUsage.cost;
                msgs[chat.currentStreamIndex] = reply;
                chat.messages = msgs;
                replies.spendingLog.recordReply(chat.currentStreamUsage, chat.currentSessionId);
            } else if (completed) {
                chat.pushErrorMessage(i18n("The model returned an empty response.")); // qmllint disable unqualified
            }
            chat.currentStreamIndex = -1;
            replies.resetProviderStreamingState();
            chat.loading = false;
            chat.activeXhr = null;
            chat.activeRequestSessionId = "";
            chat.requestGeneration++;
            if (completed) {
                try { chat.triggerNotificationSound(); replies.notifierRef.replyFinished(chat.currentSessionId, chat.currentSessionTitle, reply ? reply.content : ""); } catch (notifyErr) { console.error("Notification failed:", notifyErr); }
            }
            try { chat.saveCurrentSessionState(true); } catch (saveErr) { console.error("Session save failed:", saveErr); }
            if (completed)
                chat.maybeGenerateChatTitle();
            chat.processNextQueuedMessage();
        }
    }
}
