// Direct mode: what happens when the model asks for tools (ask_user and the bridge tools of
// chat/ToolBridge.qml, each after the user allows it on a permission card). Shows each call as a
// tool card on the reply, runs it (ask_user shows a question card and waits for
// the answer), keeps the calls with the reply so the chat can be sent again, and
// asks chat/DirectRequest.qml for the next round with the results.
// `chat` is the widget root (main.qml).
import QtQuick
import "../backends/AgentEvents.js" as AgentEvents
import "../backends/DirectTools.js" as DirectTools

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified
QtObject {
    id: rounds

    property var chat: null
    property var request: null   // chat/DirectRequest.qml: sendRound(ctx), finishRequest(ctx)

    property var bridge: null    // chat/ToolBridge.qml: tools, call(name, args, callback)

    // What the model is waiting on: a question {kind: "question", questionId, bubbleId, callId, done(output)}
    // or a permission {kind: "permission", permissionId, bubbleId, callId, call, done(output, isError)}.
    property var pending: null

    function hasPendingQuestion() {
        return rounds.pending !== null;
    }

    function _indexOfId(id) {
        for (var i = chat.messages.length - 1; i >= 0; i--)
            if (chat.messages[i].id === id)
                return i;
        return -1;
    }

    // Puts a call's outcome on its tool card (the reply is found by id: a question may have split the reply).
    function _setResult(bubbleId, callId, output, isError) {
        chat.updateMessageAt(rounds._indexOfId(bubbleId), function(msg) {
            AgentEvents.applyToReply(msg, {"type": "tool_end", "callId": callId, "output": output, "isError": isError});
        });
    }

    // A round of tool calls from the model: ctx is the request (DirectRequest.sendRound), ev the "tool_calls" event.
    function run(ctx, ev) {
        ctx.round++;
        if (ctx.round > DirectTools.MAX_ROUNDS) {
            chat.applyBackendEvent({"type": "text_delta", "delta": (chat.currentStreamText !== "" ? "\n\n" : "") + i18n("Stopped: the AI asked for too many tools in a row.")}, ctx.model);
            request.finishRequest(ctx);
            return;
        }
        chat.streamBuffer.flush();
        var calls = ev.calls;
        for (var i = 0; i < calls.length; i++)
            chat.applyBackendEvent({"type": "tool_start", "callId": calls[i].id, "name": calls[i].name, "input": calls[i].args}, ctx.model);
        var bubbleId = chat.currentStreamKey;
        var roundText = ctx.roundText;
        chat.updateMessageAt(rounds._indexOfId(bubbleId), function(msg) {
            msg.toolRounds = (msg.toolRounds || []).concat([{"text": roundText, "calls": calls}]);
        });
        chat.saveCurrentSessionState(true);
        var results = [];
        function next(n) {
            if (n >= calls.length) {
                rounds._continue(ctx, calls, ev.thinking || [], results, roundText);
                return;
            }
            rounds._execute(ctx, calls[n], bubbleId, function(output, isError) {
                if (!chat.requestIsCurrent(ctx.sessionId, ctx.generation))
                    return;
                results.push({"id": calls[n].id, "output": output, "isError": isError});
                rounds._setResult(bubbleId, calls[n].id, output, isError);
                next(n + 1);
            });
        }
        next(0);
    }

    // The results are in: the next round of the request carries the calls and their results.
    function _continue(ctx, calls, thinking, results, roundText) {
        if (!chat.requestIsCurrent(ctx.sessionId, ctx.generation))
            return;
        ctx.messages = ctx.messages.concat([DirectTools.assistantMessage(ctx.apiType, roundText, calls, thinking)],
                                           DirectTools.resultMessages(ctx.apiType, results));
        ctx.plain = null;
        chat.streamBuffer.flush();
        ctx.sepPending = chat.currentStreamText !== "";
        chat.saveCurrentSessionState(true);
        request.sendRound(ctx);
    }

    function _execute(ctx, call, bubbleId, done) {
        if (call.name !== DirectTools.ASK_USER) {
            if (rounds._isBridgeTool(call.name))
                rounds._useBridgeTool(ctx, call, bubbleId, done);
            else
                done("Unknown tool: " + call.name + ". Available: " + rounds._availableTools().join(", ") + ".", true);
            return;
        }
        var q = DirectTools.askUserQuestion(call.args);
        if (q.question === "") {
            done("The question was empty. Call ask_user again with a question.", true);
            return;
        }
        // The question is its own card below the reply; what the model writes after the answer starts a new reply.
        chat.resetProviderStreamingState();
        var questionId = "ask-" + Date.now() + "-" + call.id;
        rounds.pending = {"kind": "question", "questionId": questionId, "bubbleId": bubbleId, "callId": call.id, "model": ctx.model, "done": done};
        chat.applyBackendEvent({"type": "question_request", "id": questionId, "questions": [{
            "header": "", "question": q.question, "multiple": false, "custom": q.allowTyped,
            "options": q.options.map(function(label) { return {"label": label, "description": ""}; })}]},
            ctx.model, {"harness": "direct", "name": ctx.model});
        // DEV_AUTO_ANSWER (scripts/dev-run.sh replaces this line in its staged copy only)
    }

    // An answer from the question card or the notification: one string, or one array of labels per question.
    function respondToQuestion(questionId, answerValue, isReject) {
        var p = rounds.pending;
        if (!p || p.kind !== "question" || p.questionId !== questionId) {
            // Left over from an earlier run (the widget was restarted): nothing is waiting for it.
            rounds._finishQuestion(questionId, "dismissed", "");
            return;
        }
        var text = isReject ? "" : rounds._answerText(answerValue);
        if (!isReject && text === "")
            return;
        rounds.pending = null;
        rounds._finishQuestion(questionId, isReject ? "dismissed" : "answered", text);
        p.done(isReject ? i18n("The user closed the question without answering.") : text, false);
    }

    // The request is stopped or the user wrote something else: the question or permission is not answered.
    function cancelPending() {
        var p = rounds.pending;
        if (!p)
            return;
        rounds.pending = null;
        if (p.kind === "permission")
            rounds._finishPermission(p.permissionId, "denied");
        else
            rounds._finishQuestion(p.questionId, "dismissed", "");
        rounds._setResult(p.bubbleId, p.callId, "The user did not answer.", false);
    }

    // --- Tools of the tool bridge (MCP servers, web_search, fetch_url) -----------

    function _isBridgeTool(name) {
        var list = rounds.bridge ? rounds.bridge.tools : [];
        for (var i = 0; i < list.length; i++)
            if (list[i].name === name)
                return true;
        return false;
    }

    // Names for the "Unknown tool" error.
    function _availableTools() {
        var names = chat.plasmoid.configuration.allowAskUser !== false ? [DirectTools.ASK_USER] : [];
        var list = rounds.bridge ? rounds.bridge.tools : [];
        for (var i = 0; i < list.length && names.length < 30; i++)
            names.push(list[i].name);
        return names;
    }

    function _alwaysAllowed() {
        try {
            var list = JSON.parse(String(chat.plasmoid.configuration.toolsAlwaysAllowed || "[]"));
            return Array.isArray(list) ? list : [];
        } catch (e) {
            return [];
        }
    }

    function _allowAlways(name) {
        var list = rounds._alwaysAllowed();
        if (list.indexOf(name) < 0)
            chat.plasmoid.configuration.toolsAlwaysAllowed = JSON.stringify(list.concat([name]));
    }

    function _runTool(call, done) {
        rounds.bridge.call(call.name, call.args, done);
    }

    // A tool the user allowed always runs at once; any other shows a permission card and waits.
    function _useBridgeTool(ctx, call, bubbleId, done) {
        if (rounds._alwaysAllowed().indexOf(call.name) >= 0) {
            rounds._runTool(call, done);
            return;
        }
        // The card is its own message below the reply, like a question.
        chat.resetProviderStreamingState();
        var described = DirectTools.describeCall(call.name, call.args);
        var permissionId = "direct-" + Date.now() + "-" + call.id;
        rounds.pending = {"kind": "permission", "permissionId": permissionId, "bubbleId": bubbleId, "callId": call.id, "call": call, "done": done};
        // A short call is one line, so the notification can show it whole and offer Allow / Deny.
        chat.applyBackendEvent({"type": "permission_request", "id": permissionId, "permission": described.tool, "patterns": [described.short || described.arguments]},
                               ctx.model, {"harness": "direct", "name": ctx.model});
    }

    // An answer from the permission card or the notification. always: allow this tool from now on.
    function respondToPermission(permissionId, approved, always) {
        var p = rounds.pending;
        if (!p || p.kind !== "permission" || p.permissionId !== permissionId) {
            // Left over from an earlier run (the widget was restarted): nothing is waiting for it.
            rounds._finishPermission(permissionId, "denied");
            return;
        }
        rounds.pending = null;
        rounds._finishPermission(permissionId, approved ? "allowed" : "denied");
        if (!approved) {
            p.done("The user rejected this tool call.", true);
            return;
        }
        if (always === true)
            rounds._allowAlways(p.call.name);
        rounds._runTool(p.call, p.done);
    }

    function _finishPermission(permissionId, status) {
        chat.updateMessageAt(chat.findRequestMessage("permission_request", "permissionId", permissionId), function(msg) {
            msg.status = status;
        });
        chat.saveCurrentSessionState(true);
    }

    function _finishQuestion(questionId, status, text) {
        chat.updateMessageAt(chat.findRequestMessage("question_request", "questionId", questionId), function(msg) {
            msg.status = status;
            if (status === "answered")
                msg.submittedAnswer = text;
        });
        chat.applyBackendEvent({"type": "question_resolved", "id": questionId, "status": status}, "");
        chat.saveCurrentSessionState(true);
    }

    function _answerText(value) {
        var parts = [];
        (Array.isArray(value) ? value : [value]).forEach(function(item) {
            (Array.isArray(item) ? item : [item]).forEach(function(label) {
                if (String(label || "").trim() !== "") parts.push(String(label).trim());
            });
        });
        return parts.join(", ");
    }
}
