// OpenCode mode: sends a chat's prompt to an `opencode serve` (starting a
// local one if needed) through backends/OpenCodeBackend.js, and answers
// permission and question cards. `chat` is the widget root (main.qml).
import QtQuick
import "../backends/DirectBackend.js" as DirectBackend
import "../backends/OpenCodeBackend.js" as OpenCodeBackend

QtObject {
    id: mode

    property var chat: null

    // Where a chat's OpenCode requests go.
    function openCodeTarget(sessionId) {
        return {"baseUrl": chat.openCodeBaseUrl(), "xhrFactory": function() { return new XMLHttpRequest(); },
                "directory": String(chat.getSessionProperty(sessionId, "openCodeWorkspaceCwd", chat.openCodeWorkspaceCwd || "") || "").trim()};
    }

    // OpenCode prompt parts for a user message (text, plus images as files).
    function openCodeParts(message) {
        if (!message.attachments || message.attachments.length === 0)
            return [{"type": "text", "text": message.content || ""}];
        var payload = chat.buildMessageContent(message.content || "", message.attachments, "openai");
        if (typeof payload === "string")
            return [{"type": "text", "text": payload}];
        var parts = [];
        for (var i = 0; i < payload.length; i++) {
            if (payload[i].type === "text")
                parts.push({"type": "text", "text": payload[i].text});
            else if (payload[i].type === "image_url" && payload[i].image_url && payload[i].image_url.url)
                parts.push({"type": "file", "mime": payload[i].image_url.url.split(";")[0].split(":")[1] || "image/jpeg", "url": payload[i].image_url.url});
        }
        return parts;
    }

    // Makes sure an OpenCode server answers at the configured URL; starts one
    // (via the helper) when the URL is local and nothing is running.
    // done(ok, message).
    function ensureOpenCodeServer(baseUrl, directory, done) {
        var xhr = new XMLHttpRequest();
        var finished = false;
        function finish(ok, message) { if (!finished) { finished = true; done(ok, message); } }
        function notRunning() {
            var match = /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\]):(\d+)/i.exec(baseUrl);
            if (!match) {
                finish(false, "OpenCode isn't reachable at " + baseUrl + ".");
                return;
            }
            chat.store.runHelper("opencode_server_start", {"port": Number(match[2]), "directory": directory}, function(stdout) {
                var result = {};
                try { result = JSON.parse(stdout); } catch (e) { result = {}; }
                if (result.status === "started" || result.status === "already-running")
                    finish(true, "");
                else
                    finish(false, "OpenCode isn't running at " + baseUrl + " and couldn't be started: " + (result.message || "unknown error") + ".");
            });
        }
        try {
            xhr.open("GET", baseUrl + "/global/health", true);
            xhr.timeout = 1500;
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status >= 200 && xhr.status < 300) finish(true, "");
                else notRunning();
            };
            xhr.ontimeout = notRunning;
            xhr.send();
        } catch (e) {
            notRunning();
        }
    }

    function send(sessionId, generation) {
        var target = mode.openCodeTarget(sessionId);
        chat.loading = true;
        mode.ensureOpenCodeServer(target.baseUrl, target.directory, function(ok, message) {
            if (!chat.requestIsCurrent(sessionId, generation))
                return;
            if (!ok) {
                chat.applyBackendEvent({"type": "error", "message": message}, "OpenCode");
                chat.applyBackendEvent({"type": "done", "reason": "error"}, "OpenCode");
                return;
            }
            mode.sendOpenCodePrompt(sessionId, generation, target);
        });
    }

    function sendOpenCodePrompt(sessionId, generation, target) {
        var source = chat.sessionMessages(sessionId);
        var providerId = String(chat.getSessionProperty(sessionId, "openCodeProvider", chat.plasmoid.configuration.openCodeProvider || "") || "").trim();
        var modelId = String(chat.getSessionProperty(sessionId, "openCodeModel", chat.plasmoid.configuration.openCodeModel || "") || "").trim();
        var label = providerId && modelId ? providerId + "/" + modelId : "OpenCode";
        chat.currentStreamUsage = ({});
        chat.loading = true;
        chat.activeXhr = OpenCodeBackend.send({
            "baseUrl": target.baseUrl,
            "directory": target.directory,
            "sessionId": chat.currentOpenCodeSessionId(sessionId),
            "title": chat.currentSessionTitle || "KDE AI Chat",
            "body": OpenCodeBackend.promptBody({
                "parts": mode.openCodeParts(source[source.length - 1] || {}),
                "providerId": providerId,
                "modelId": modelId,
                "agent": String(chat.getSessionProperty(sessionId, "openCodeAgent", chat.openCodeAgent || "") || "").trim(),
                "useAgentModel": chat.getSessionProperty(sessionId, "openCodeUseAgentModel", chat.openCodeUseAgentModel) !== false,
                "system": chat.buildEffectiveSystemPrompt(sessionId)
            }),
            "xhrFactory": target.xhrFactory,
            "parserFactory": DirectBackend.createSseParser,
            "onEvent": function(event) {
                if (event.type === "session")
                    chat.setCurrentOpenCodeSessionId(event.id, sessionId);
                else if (chat.requestIsCurrent(sessionId, generation))
                    chat.applyBackendEvent(event, label, {"directory": target.directory});
            }
        });
    }

    function respondToPermission(permissionId, approved, always) {
        var index = chat.findRequestMessage("permission_request", "permissionId", permissionId);
        if (index < 0)
            return;
        var target = mode.openCodeTarget(chat.currentSessionId);
        target.directory = chat.messages[index].openCodeDirectory || target.directory;
        chat.updateMessageAt(index, function(msg) { msg.status = "answering..."; });
        OpenCodeBackend.replyPermission(target, permissionId, !approved ? "reject" : always ? "always" : "once", function(ok, status) {
            chat.updateMessageAt(chat.findRequestMessage("permission_request", "permissionId", permissionId), function(msg) {
                msg.status = ok ? (approved ? "allowed" : "denied") : "pending";
            });
            if (!ok)
                chat.pushErrorMessage("OpenCode didn't accept the permission answer (HTTP " + status + ").");
            chat.saveCurrentSessionState(true);
        });
    }

    // answerValue: one string, or one array of labels per question.
    function respondToQuestion(questionId, answerValue, isReject) {
        var index = chat.findRequestMessage("question_request", "questionId", questionId);
        if (index < 0)
            return;
        var target = mode.openCodeTarget(chat.currentSessionId);
        target.directory = chat.messages[index].openCodeDirectory || target.directory;
        var answers = isReject ? null : (Array.isArray(answerValue) ? answerValue : [[String(answerValue || "")]]);
        chat.updateMessageAt(index, function(msg) { msg.status = isReject ? "dismissing..." : "answering..."; });
        OpenCodeBackend.replyQuestion(target, questionId, answers, function(ok, status) {
            chat.updateMessageAt(chat.findRequestMessage("question_request", "questionId", questionId), function(msg) {
                msg.status = ok ? (isReject ? "dismissed" : "answered") : "pending";
                if (ok && !isReject) msg.submittedAnswer = answerValue;
            });
            if (!ok)
                chat.pushErrorMessage("OpenCode didn't accept the answer (HTTP " + status + ").");
            chat.saveCurrentSessionState(true);
        });
    }
}
