// OpenCode mode: sends a chat's prompt to an `opencode serve` (starting a
// local one if needed) through backends/OpenCodeBackend.js, answers
// permission and question cards, loads the agent list, and syncs a chat from
// its OpenCode session. `chat` is the widget root (main.qml).
import QtQuick
import "../backends/AgentEvents.js" as AgentEvents
import "../backends/DirectBackend.js" as DirectBackend
import "../backends/OpenCodeAgents.js" as OpenCodeAgents
import "../backends/OpenCodeBackend.js" as OpenCodeBackend
import "../backends/OpenCodeCatalog.js" as OpenCodeCatalog
import "../backends/OpenCodeEvents.js" as OpenCodeEvents
import "../backends/OpenCodeHistory.js" as OpenCodeHistory
import "../Variants.js" as Variants
import "EffectiveConfig.js" as EffectiveConfig
import "Personality.js" as Personality

QtObject {
    id: mode

    property var chat: null
    property int _agentsRequest: 0
    property var _agentWaiters: []
    property Component _timer: Component { Timer {} }

    // Runs fn after ms (the backend's reconnect delay).
    function later(fn, ms) {
        var timer = mode._timer.createObject(mode, {"interval": ms});
        timer.triggered.connect(function() { timer.destroy(); fn(); });
        timer.start();
    }

    function _openSession() {
        return chat.sessions[chat.sessionIndexById(chat.currentSessionId)] || null;
    }

    // Where a chat's OpenCode requests go.
    function openCodeTarget(sessionId) {
        return {"baseUrl": chat.openCodeBaseUrl(), "xhrFactory": function() { return new XMLHttpRequest(); },
                // The chat's own folder, else its project's (chat/Projects.js).
                "directory": chat.projects ? chat.projects.workspaceFor(sessionId).path
                    : String(chat.getSessionProperty(sessionId, "openCodeWorkspaceCwd", chat.openCodeWorkspaceCwd || "") || "").trim()};
    }

    // OpenCode prompt parts for a user message (text, plus images as files).
    function openCodeParts(message) {
        var hasQuotes = !!message.quotes && message.quotes.length > 0;
        if ((!message.attachments || message.attachments.length === 0) && !hasQuotes)
            return [{"type": "text", "text": message.content || ""}];
        var payload = chat.buildMessageContent(message.content || "", message.attachments || [], "openai", message.quotes);
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
        chat.modeNotice = "";
        mode.ensureOpenCodeServer(target.baseUrl, target.directory, function(ok, message) {
            if (!chat.requestIsCurrent(sessionId, generation))
                return;
            if (!ok) {
                // The chat stays an OpenCode chat; it never falls back to another mode.
                var text = EffectiveConfig.unavailableText("opencode", message);
                chat.modeNotice = text;
                chat.applyBackendEvent({"type": "error", "message": text}, "OpenCode");
                chat.applyBackendEvent({"type": "done", "reason": "error"}, "OpenCode");
                return;
            }
            if (chat.openCodeAgentsList.length === 0)
                mode.fetchAgents();
            // A variant is only sent when the server offers it for the model, so
            // the catalogue is needed once per session when a variant is set.
            if (chat.effectiveConfig(sessionId).variant !== "" && Object.keys(chat.openCodeVariants).length === 0)
                mode.fetchCatalog(function() {
                    if (chat.requestIsCurrent(sessionId, generation))
                        mode.sendOpenCodePrompt(sessionId, generation, target);
                });
            else
                mode.sendOpenCodePrompt(sessionId, generation, target);
        });
    }

    // The variants OpenCode offers for a model, as Variants.js entries.
    function variantsOf(providerId, modelId) {
        return Variants.fromOpenCodeNames(chat.openCodeVariants[providerId + "/" + modelId]);
    }

    // What to send for the chat's variant: {variant: name}, or {} when none is
    // chosen or the server does not offer that name for the model (or its list
    // is not loaded).
    function variantSend(eff) {
        return Variants.sendFor(mode.variantsOf(eff.provider, eff.model), eff.variant);
    }

    // Loads the providers, their models and each model's variant NAMES from the
    // server (/config/providers, else /provider) into the widget's lists. Every
    // refresh is a snapshot: a failed one leaves the lists empty rather than
    // stale. The response carries the user's API keys: only OpenCodeCatalog's
    // reduced result is kept, and the response itself is never stored or logged.
    function fetchCatalog(callback) {
        chat.openCodeProvidersList = [];
        chat.openCodeModelsList = [];
        chat.openCodeVariants = ({});
        var baseUrl = chat.openCodeBaseUrl();
        if (!baseUrl) {
            if (callback) callback();
            return;
        }
        var endpoints = [baseUrl + "/config/providers", baseUrl + "/provider"];
        var endpointIndex = 0;
        function requestNext() {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", endpoints[endpointIndex], true);
            xhr.timeout = 2000;
            var requestFinished = false;
            var finish = function(success) {
                if (requestFinished) return;
                requestFinished = true;
                if (success || endpointIndex >= endpoints.length - 1) {
                    if (callback) callback();
                    return;
                }
                endpointIndex++;
                requestNext();
            };
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE) return;
                if (xhr.status >= 200 && xhr.status < 300) {
                    try {
                        if (xhr.responseText.length > 2000000)
                            throw new Error("provider response is too large");
                        var catalog = OpenCodeCatalog.parse(JSON.parse(xhr.responseText));
                        chat.openCodeProvidersList = catalog.providers;
                        chat.openCodeModelsList = catalog.models;
                        chat.openCodeVariants = catalog.variants;
                        finish(catalog.providers.length > 0);
                        return;
                    } catch (e) {}
                }
                finish(false);
            };
            xhr.ontimeout = function() { finish(false); };
            xhr.onerror = function() { finish(false); };
            try { xhr.send(); } catch (e) { finish(false); }
        }
        requestNext();
    }

    // The system text sent with each prompt: Settings → Personality first
    // (unless this chat turned it off), as in direct chats, then the rest.
    function systemFor(sessionId) {
        var personality = chat.getSessionProperty(sessionId, "personalityOff", false) === true ? "" : Personality.block(chat.plasmoid.configuration);
        return [personality, chat.buildEffectiveSystemPrompt(sessionId)].filter(function(t) { return t; }).join("\n\n");
    }

    function sendOpenCodePrompt(sessionId, generation, target) {
        var source = chat.sessionMessages(sessionId);
        var eff = chat.effectiveConfig(sessionId);
        var providerId = eff.provider;
        var modelId = eff.model;
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
                "agent": eff.agent,
                "variantSend": mode.variantSend(eff),
                "useAgentModel": chat.getSessionProperty(sessionId, "openCodeUseAgentModel", chat.openCodeUseAgentModel) !== false,
                "system": mode.systemFor(sessionId)
            }),
            "xhrFactory": target.xhrFactory,
            "parserFactory": DirectBackend.createSseParser,
            "mapperFactory": OpenCodeEvents.createEventMapper,
            "later": function(fn, ms) { mode.later(fn, ms); },
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

    // Loads the agents that can run the open chat, for its workspace folder
    // (OpenCode also lists the folder's own agents). A failed load keeps the
    // list there was; a newer load replaces an older one still running.
    function fetchAgents(callback) {
        if (callback)
            mode._agentWaiters = mode._agentWaiters.concat([callback]);
        var request = ++mode._agentsRequest;
        var directory = String(chat.openCodeWorkspaceCwd || "").trim();
        var baseUrl = chat.openCodeBaseUrl();
        function finish(list) {
            if (request !== mode._agentsRequest)
                return;
            if (list !== null) {
                chat.openCodeAgentsList = list;
                chat.openCodeAgentsDirectory = directory;
            }
            var waiters = mode._agentWaiters;
            mode._agentWaiters = [];
            for (var i = 0; i < waiters.length; i++)
                waiters[i]();
        }
        if (!baseUrl) {
            finish(null);
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            var list = null;
            if (xhr.status >= 200 && xhr.status < 300 && xhr.responseText.length < 2000000) {
                try { list = OpenCodeAgents.normalize(JSON.parse(xhr.responseText)); } catch (e) { list = null; }
            }
            finish(list);
        };
        xhr.ontimeout = function() { finish(null); };
        try {
            xhr.open("GET", OpenCodeBackend.url(baseUrl, "/agent", directory), true);
            xhr.timeout = 5000;
            xhr.send();
        } catch (e) {
            finish(null);
        }
    }

    // The agent picked above the chat: stored where the open chat takes its
    // agent from (its own settings or the main ones), so it is the one used.
    function chooseAgent(value) {
        if (EffectiveConfig.agentOwner(chat.plasmoid.configuration, mode._openSession()) === "chat")
            chat.setSessionProperty(chat.currentSessionId, "openCodeAgent", value);
        else
            chat.plasmoid.configuration.openCodeAgent = value;
        chat.applySessionSource(mode._openSession());
    }


    // Replaces the open chat's messages with its OpenCode session's history.
    function syncHistory() {
        var sessionId = chat.currentSessionId;
        var remoteId = chat.currentOpenCodeSessionId(sessionId);
        if (!remoteId)
            return;
        var target = mode.openCodeTarget(sessionId);
        var generation = chat.beginRequest(sessionId);
        var xhr = new XMLHttpRequest();
        chat.loading = true;
        chat.activeXhr = xhr;
        function end(error) {
            chat.loading = false;
            chat.activeXhr = null;
            chat.activeRequestSessionId = "";
            chat.requestGeneration++;
            if (error)
                chat.pushErrorMessage("Sync failed: " + error);
        }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || !chat.requestIsCurrent(sessionId, generation))
                return;
            if (xhr.status < 200 || xhr.status >= 300) {
                end(xhr.status === 0 ? "could not reach OpenCode at " + target.baseUrl + "." : "OpenCode returned HTTP " + xhr.status + ".");
                return;
            }
            var history = null;
            try { history = xhr.responseText.length > 10000000 ? null : JSON.parse(xhr.responseText); } catch (e) { history = null; }
            if (!Array.isArray(history)) {
                end("OpenCode's answer couldn't be read.");
                return;
            }
            end("");
            var messages = OpenCodeHistory.toMessages(history.slice(-500), {
                "createEventMapper": OpenCodeEvents.createEventMapper, "applyToReply": AgentEvents.applyToReply,
                "formatTime": function(ms) { return chat.nowTime(ms); }, "sessionId": remoteId, "maxChars": chat.maxMessageChars, "now": Date.now()});
            if (messages.length === 0)
                return;
            chat.messages = messages;
            chat.saveCurrentSessionState(true);
            chat.scrollToBottom();
        };
        try {
            xhr.open("GET", OpenCodeBackend.url(target.baseUrl, "/session/" + encodeURIComponent(remoteId) + "/message", target.directory), true);
            xhr.send();
        } catch (e) {
            end("invalid OpenCode endpoint.");
        }
    }
}
