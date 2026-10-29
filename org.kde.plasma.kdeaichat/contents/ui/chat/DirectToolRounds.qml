// Direct mode: what happens when the model asks for tools. Shows each call as a
// tool card on the reply, runs it (ask_user shows a question card and waits for
// the answer; any other tool goes to chat/DirectToolRunner.qml), keeps the calls with the reply so the chat can be sent again, and
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
    // Runs the tools besides ask_user, with approval (chat/DirectToolRunner.qml).
    readonly property var runner: DirectToolRunner { chat: rounds.chat }

    // The question the model is waiting on: {questionId, bubbleId, callId, done(output)}.
    property var pending: null

    // The model is waiting on the user: a question, or an approval to run a tool.
    function hasPendingQuestion() {
        return rounds.pending !== null || rounds.runner.hasPending();
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
        if (ctx.round > (ctx.maxRounds || DirectTools.MAX_ROUNDS)) {
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
            rounds.runner.run(ctx, call, bubbleId, done);
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
        rounds.pending = {"questionId": questionId, "bubbleId": bubbleId, "callId": call.id, "model": ctx.model, "done": done};
        chat.applyBackendEvent({"type": "question_request", "id": questionId, "questions": [{
            "header": "", "question": q.question, "multiple": false, "custom": q.allowTyped,
            "options": q.options.map(function(label) { return {"label": label, "description": ""}; })}]},
            ctx.model, {"harness": "direct", "name": ctx.model});
        // DEV_AUTO_ANSWER (scripts/dev-run.sh replaces this line in its staged copy only)
    }

    // An answer from the question card or the notification: one string, or one array of labels per question.
    function respondToQuestion(questionId, answerValue, isReject) {
        var p = rounds.pending;
        if (!p || p.questionId !== questionId) {
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

    // The request is stopped or the user wrote something else: the question is not answered.
    function cancelPending() {
        var approval = rounds.runner.cancelPending();
        if (approval)
            rounds._setResult(approval.bubbleId, approval.callId, "The user stopped the request before approving this tool call.", false);
        var p = rounds.pending;
        if (!p)
            return;
        rounds.pending = null;
        rounds._finishQuestion(p.questionId, "dismissed", "");
        rounds._setResult(p.bubbleId, p.callId, "The user did not answer.", false);
    }

    // Allow, Always allow or Deny on a tool's permission card (chat/MessageEdits.qml routes direct-mode cards here).
    function respondToPermission(permissionId, approved, always) {
        rounds.runner.respondToPermission(permissionId, approved, always);
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
