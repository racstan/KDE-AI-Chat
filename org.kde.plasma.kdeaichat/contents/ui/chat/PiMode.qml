// Pi mode: sends a chat's prompt to its own `pi --mode rpc` process through
// the Pi bridge (kdeaichat/pi_bridge_server.py, started via the helper) and
// answers Pi's dialogs. `chat` is the widget root (main.qml).
import QtQuick
import "../backends/DirectBackend.js" as DirectBackend
import "../backends/PiBackend.js" as PiBackend

QtObject {
    id: mode

    property var chat: null
    // {baseUrl, token} of the running bridge, once known.
    property var bridge: null

    function target() {
        return {"baseUrl": mode.bridge.baseUrl, "token": mode.bridge.token, "xhrFactory": function() { return new XMLHttpRequest(); }};
    }

    // Starts the bridge if needed; done(ok, message). fresh: ask again even if known.
    function withBridge(fresh, done) {
        if (mode.bridge && !fresh) {
            done(true, "");
            return;
        }
        chat.store.runHelper("pi_bridge_start", {}, function(stdout) {
            var result = {};
            try { result = JSON.parse(stdout); } catch (e) { result = {}; }
            if (result.port && result.token) {
                mode.bridge = {"baseUrl": "http://127.0.0.1:" + result.port, "token": result.token};
                done(true, "");
            } else {
                mode.bridge = null;
                done(false, "Pi: " + (result.message || "the Pi bridge couldn't be started."));
            }
        });
    }

    // The prompt body for a user message: text, plus images as base64.
    function promptBody(sessionId, message) {
        var eff = chat.effectiveConfig(sessionId);
        var text = String(message.content || "");
        var images = [];
        if (message.attachments && message.attachments.length > 0) {
            var payload = chat.buildMessageContent(text, message.attachments, "openai");
            if (typeof payload === "string") {
                text = payload;
            } else {
                var parts = [];
                for (var i = 0; i < payload.length; i++) {
                    var url = payload[i].type === "image_url" && payload[i].image_url ? String(payload[i].image_url.url || "") : "";
                    var match = /^data:([^;,]+);base64,(.*)$/.exec(url);
                    if (payload[i].type === "text") parts.push(payload[i].text);
                    else if (match) images.push({"mimeType": match[1], "data": match[2]});
                }
                text = parts.join("\n");
            }
        }
        return {
            // The chat's working folder (shared with OpenCode mode, hence the key).
            "directory": String(chat.getSessionProperty(sessionId, "openCodeWorkspaceCwd", chat.openCodeWorkspaceCwd) || "").trim(),
            // Provider, model and thinking: the main settings or the chat's own (EffectiveConfig.js).
            "provider": eff.provider,
            "model": eff.model,
            "thinking": eff.thinking,
            "message": text,
            "images": images
        };
    }

    function send(sessionId, generation) {
        chat.loading = true;
        chat.currentStreamUsage = ({});
        mode.withBridge(false, function(ok, message) {
            if (!chat.requestIsCurrent(sessionId, generation))
                return;
            if (!ok) {
                chat.applyBackendEvent({"type": "error", "message": message}, "Pi");
                chat.applyBackendEvent({"type": "done", "reason": "error"}, "Pi");
                return;
            }
            mode.sendPrompt(sessionId, generation, true);
        });
    }

    // canRetry: if the bridge turns out to be gone (it exits when idle),
    // start it again and resend once.
    function sendPrompt(sessionId, generation, canRetry) {
        var source = chat.sessionMessages(sessionId);
        var body = mode.promptBody(sessionId, source[source.length - 1] || {});
        var label = body.model ? "Pi · " + body.model : "Pi";
        var retrying = false;
        var progressed = false;
        var options = mode.target();
        options.chatId = sessionId;
        options.body = body;
        options.parserFactory = DirectBackend.createSseParser;
        options.onEvent = function(event) {
            if (retrying || !chat.requestIsCurrent(sessionId, generation))
                return;
            if (event.type === "error" && canRetry && !progressed && /bridge/.test(event.message)) {
                retrying = true;
                mode.withBridge(true, function(ok, message) {
                    if (!chat.requestIsCurrent(sessionId, generation))
                        return;
                    if (ok) {
                        mode.sendPrompt(sessionId, generation, false);
                    } else {
                        chat.applyBackendEvent({"type": "error", "message": message}, label);
                        chat.applyBackendEvent({"type": "done", "reason": "error"}, label);
                    }
                });
                return;
            }
            if (event.type !== "start")
                progressed = true;
            chat.applyBackendEvent(event, label, {"harness": "pi", "chatId": sessionId});
        };
        chat.activeXhr = PiBackend.send(options);
    }

    function reply(role, idField, requestId, response, doneStatus) {
        var index = chat.findRequestMessage(role, idField, requestId);
        if (index < 0 || !mode.bridge)
            return;
        var chatId = chat.messages[index].harnessChatId || chat.currentSessionId;
        chat.updateMessageAt(index, function(msg) { msg.status = "answering..."; });
        PiBackend.replyDialog(mode.target(), chatId, requestId, response, function(ok, status) {
            chat.updateMessageAt(chat.findRequestMessage(role, idField, requestId), function(msg) {
                msg.status = ok ? doneStatus : "pending";
                if (ok && response.value !== undefined) msg.submittedAnswer = response.value;
            });
            if (!ok)
                chat.pushErrorMessage("Pi didn't accept the answer (HTTP " + status + ").");
            chat.saveCurrentSessionState(true);
        });
    }

    function respondToPermission(permissionId, approved) {
        mode.reply("permission_request", "permissionId", permissionId, {"confirmed": approved}, approved ? "allowed" : "denied");
    }

    // answerValue: one string, or one array of labels per question (Pi asks one).
    function respondToQuestion(questionId, answerValue, isReject) {
        if (isReject) {
            mode.reply("question_request", "questionId", questionId, {"cancelled": true}, "dismissed");
            return;
        }
        var value = Array.isArray(answerValue) ? answerValue[0] : answerValue;
        if (Array.isArray(value)) value = value[0];
        mode.reply("question_request", "questionId", questionId, {"value": String(value || "")}, "answered");
    }
}
