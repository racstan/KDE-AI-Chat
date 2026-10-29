// Direct mode: runs the tools the model calls besides ask_user. Tools come from
// `toolProviders` (MCP servers, skills, workspace tools plug in there), each call goes
// to the runner registered for the tool's source, after the user's approval when the
// tool needs it (a permission card, the same one OpenCode and Pi use). A call has a
// time limit and its result is cut to 32 kB. chat/DirectToolRounds.qml hands calls
// over and answers permission cards through here. `chat` is the widget root (main.qml).
//
//   registerRunner(source, function(call, entry, done) {...})
//       source: "mcp:<server>" (exact) or the kind before the colon ("mcp", "skill", "workspace").
//       call {id, name (the tool's real name), args}; entry: the tool (DirectTools.toolRegistry());
//       done(output, isError) once, any time before the limit.
//   toolProviders: [{source, tools: function(sessionId, cb) {...}}]; cb([{name, description, schema, source, risk, ...}]).
//       Asked before the first round of every request, in parallel; one that is too slow is left out.
// With no providers nothing changes: ask_user is the only tool.
import QtQuick
import "../backends/DirectTools.js" as DirectTools
import "DirectToolRunner.js" as RunnerLogic

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified
QtObject {
    id: runner

    property var chat: null
    property var toolProviders: []
    // Seconds a tool may take (an entry can set its own timeoutMs) and how long providers may take to list their tools.
    property int timeoutMs: 60000
    property int providerTimeoutMs: 2000

    // The approval the model is waiting on: {permissionId, bubbleId, callId, key, canAlways, ctx, entry, call, fn, done}.
    property var pending: null

    readonly property string deniedText: "The user denied this tool call."
    property var _runners: ({})
    property var _approvals: null    // the remembered keys, once loaded
    property var _active: ({})       // running calls: id -> cancel()
    property int _counter: 0
    property Component _timerComponent: Component { Timer {} }

    function registerRunner(source, fn) {
        var map = Object.assign({}, runner._runners);
        map[String(source)] = fn;
        runner._runners = map;
    }

    function unregisterRunner(source) {
        var map = Object.assign({}, runner._runners);
        delete map[String(source)];
        runner._runners = map;
    }

    // Adds a provider, replacing an earlier one with the same source.
    function registerProvider(provider) {
        runner.toolProviders = runner.toolProviders.filter(function(p) { return p.source !== provider.source; }).concat([provider]);
    }

    function hasPending() {
        return runner.pending !== null;
    }

    function later(fn, ms) {
        var timer = runner._timerComponent.createObject(runner, {"interval": ms});
        timer.triggered.connect(function() { timer.destroy(); fn(); });
        timer.start();
        return timer;
    }

    function _isIncognito(sessionId) {
        return runner.chat && runner.chat.incognito ? runner.chat.incognito.isIncognito(sessionId) : String(sessionId).indexOf("s-incognito-") === 0;
    }

    // --- Collecting tools ----------------------------------------------------

    // cb(entries) with the tools of every provider, in provider order. Right away (before this returns) when
    // there are no providers; else when all have answered or after providerTimeoutMs, whichever is first.
    function collectTools(sessionId, cb) {
        var providers = runner.toolProviders || [];
        if (providers.length === 0) {
            cb([]);
            return;
        }
        var results = [], remaining = providers.length, finished = false, timer = null;
        function finish() {
            if (finished)
                return;
            finished = true;
            if (timer) {
                timer.stop();
                timer.destroy();
            }
            var all = [];
            results.forEach(function(list) { all = all.concat(list || []); });
            cb(all);
        }
        providers.forEach(function(provider, i) {
            var answered = false;
            function answer(list) {
                if (answered || finished)
                    return;
                answered = true;
                results[i] = (Array.isArray(list) ? list : []).map(function(entry) { return Object.assign({"source": provider.source}, entry); });
                if (--remaining === 0)
                    finish();
            }
            try {
                provider.tools(sessionId, answer);
            } catch (e) {
                console.warn("KDE AI Chat: tool provider failed:", e);
                answer([]);
            }
        });
        if (!finished)
            timer = runner.later(finish, runner.providerTimeoutMs);
    }

    // --- Running a call ------------------------------------------------------

    // A call of a tool other than ask_user. ctx: the request (chat/DirectRequest.qml, with toolRegistry),
    // call: {id, name (as sent), args}; done(output, isError).
    function run(ctx, call, bubbleId, done) {
        var entry = DirectTools.lookupTool(ctx.toolRegistry, call.name);
        if (!entry) {
            const known = ctx.toolRegistry ? ctx.toolRegistry.list.map(function(t) { return t.name; }) : [];
            done("Unknown tool: " + call.name + ". " + (known.length === 0 ? "Only ask_user is available." : "Available tools: ask_user, " + known.join(", ") + "."), true);
            return;
        }
        var fn = runner._runners[entry.source] || runner._runners[entry.kind];
        if (!fn) {
            done("The tool " + call.name + " can't run right now: nothing is set up to run it.", true);
            return;
        }
        var key = RunnerLogic.approvalKey(entry);
        if (entry.risk !== "change" && entry.kind !== "mcp") {
            runner._start(ctx, entry, call, fn, done);
            return;
        }
        runner._withApprovals(ctx, function() {
            if (!RunnerLogic.needsApproval(entry, runner._approvals))
                runner._start(ctx, entry, call, fn, done);
            else
                runner._ask(ctx, entry, call, fn, bubbleId, key, done);
        });
    }

    // The remembered keys are read once (they only change through this widget's answers).
    function _withApprovals(ctx, then) {
        if (runner._approvals !== null || !runner.chat || !runner.chat.store || !runner.chat.store.runHelper) {
            if (runner._approvals === null)
                runner._approvals = [];
            then();
            return;
        }
        runner.chat.store.runHelper("tool_approvals_list", {}, function(stdout, exitCode) {
            runner._approvals = runner._keysFrom(stdout, exitCode) || [];
            if (runner.chat.requestIsCurrent(ctx.sessionId, ctx.generation))
                then();
        });
    }

    function _keysFrom(stdout, exitCode) {
        if (exitCode !== 0)
            return null;
        try {
            const keys = JSON.parse(stdout).keys;
            return Array.isArray(keys) ? keys.map(String) : null;
        } catch (e) {
            return null;
        }
    }

    // Shows the permission card and waits for respondToPermission().
    function _ask(ctx, entry, call, fn, bubbleId, key, done) {
        var chat = runner.chat;
        // The card is its own message below the reply; what the model writes after it starts a new reply.
        chat.resetProviderStreamingState();
        var permissionId = "tool-" + Date.now() + "-" + (++runner._counter) + "-" + call.id;
        var canAlways = key !== "" && !runner._isIncognito(ctx.sessionId);
        runner.pending = {"permissionId": permissionId, "bubbleId": bubbleId, "callId": call.id, "key": key, "canAlways": canAlways,
                          "ctx": ctx, "entry": entry, "call": call, "fn": fn, "done": done};
        chat.applyBackendEvent({"type": "permission_request", "id": permissionId, "permission": entry.name, "patterns": RunnerLogic.argsLines(call.args)},
                               ctx.model, {"harness": "direct", "name": ctx.model, "canAlways": canAlways});
    }

    // Allow once, Always or Deny on the card (or the notification).
    function respondToPermission(permissionId, approved, always) {
        var p = runner.pending;
        if (!p || p.permissionId !== permissionId) {
            // Left over from an earlier run (the widget was restarted): nothing is waiting for it.
            runner._resolveCard(permissionId, false);
            return;
        }
        runner.pending = null;
        runner._resolveCard(permissionId, approved);
        if (!approved) {
            p.done(runner.deniedText, true);
            return;
        }
        if (always === true && p.canAlways)
            runner._remember(p.key);
        runner._start(p.ctx, p.entry, p.call, p.fn, p.done);
    }

    // The request is stopped or the user wrote something else: nothing runs, and a waiting approval is closed.
    // Returns the approval that was waiting ({bubbleId, callId, ...}) or null.
    function cancelPending() {
        Object.keys(runner._active).forEach(function(id) { runner._active[id](); });
        runner._active = ({});
        var p = runner.pending;
        if (!p)
            return null;
        runner.pending = null;
        runner._resolveCard(p.permissionId, false);
        return p;
    }

    function _resolveCard(permissionId, approved) {
        var chat = runner.chat;
        var index = chat.findRequestMessage("permission_request", "permissionId", permissionId);
        if (index >= 0 && chat.messages[index].status !== "pending")
            return;
        chat.applyBackendEvent({"type": "permission_resolved", "id": permissionId, "reply": approved ? "once" : "reject"}, "");
        chat.saveCurrentSessionState(true);
    }

    function _remember(key) {
        var chat = runner.chat;
        if ((runner._approvals || []).indexOf(key) >= 0)
            return;
        runner._approvals = (runner._approvals || []).concat([key]);
        if (!chat.store || !chat.store.runHelper)
            return;
        chat.store.runHelper("tool_approvals_add", {"key": key}, function(stdout, exitCode) {
            var keys = runner._keysFrom(stdout, exitCode);
            if (keys !== null) {
                runner._approvals = keys;
                return;
            }
            runner._approvals = (runner._approvals || []).filter(function(k) { return k !== key; });
            chat.pushErrorMessage(i18n("Couldn't remember that approval. The tool was allowed this once."));
        });
    }

    // Runs the tool with a time limit; its result is cut. A stopped request drops a late answer.
    function _start(ctx, entry, call, fn, done) {
        var id = "run-" + (++runner._counter);
        var finished = false, timer = null;
        function stop() {
            finished = true;
            if (timer) {
                timer.stop();
                timer.destroy();
            }
            delete runner._active[id];
        }
        function finish(output, isError) {
            if (finished)
                return;
            stop();
            done(RunnerLogic.cutResult(output), isError === true);
        }
        runner._active[id] = stop;
        var limit = entry.timeoutMs > 0 ? entry.timeoutMs : runner.timeoutMs;
        timer = runner.later(function() {
            finish("The tool " + entry.name + " did not answer within " + Math.round(limit / 1000) + " seconds.", true);
        }, limit);
        try {
            fn({"id": call.id, "name": entry.realName, "args": call.args}, entry, finish);
        } catch (e) {
            finish("The tool " + entry.name + " failed: " + e, true);
        }
    }
}
