// Direct mode: builds a provider request (key from KWallet, system prompt,
// context window, attachments, tools) and sends it through backends/DirectBackend.js.
// Its events go to chat.applyBackendEvent; when the model calls a tool,
// chat/DirectToolRounds.qml runs it and the request goes on with the result.
// `chat` is the widget root (main.qml).
import QtQuick
import "../ProviderService.js" as ProviderService
import "../Security.js" as Sec
import "../backends/DirectBackend.js" as DirectBackend
import "../backends/DirectStream.js" as DirectStream
import "../backends/DirectTools.js" as DirectTools
import "MessageContent.js" as MessageContent

QtObject {
    id: direct

    property var chat: null
    property var directVariantRef: null  // chat/DirectVariant.qml
    // Replaces XMLHttpRequest in tests.
    property var xhrFactory: null
    readonly property var toolRounds: DirectToolRounds { chat: direct.chat; request: direct }

    function getProviderConfig(provider, sessionId) {
        var providerId = provider || chat.getEffectiveProvider(sessionId || chat.currentSessionId);
        var cfg = ProviderService.getProviderConfig(providerId, chat.plasmoid.configuration);
        cfg.baseUrl = Sec.validateHttpUrl(cfg.baseUrl);
        // Keys come from KWallet. A plaintext value left by an older version is
        // only used while KWallet is unavailable, until it can be migrated.
        var walletKey = String(chat.walletApiKeys[providerId] || "").trim();
        cfg.apiKey = walletKey || (chat.wallet.usable ? "" : String(cfg.apiKey || "").trim());
        var eff = chat.effectiveConfig(sessionId || chat.currentSessionId).direct;
        if (eff.model && eff.provider === providerId)
            cfg.model = eff.model;
        return cfg;
    }

    function buildEffectiveSystemPrompt(sessionId) {
        var enabled = chat.getSessionProperty(sessionId, "chatSystemPromptEnabled", true) !== false;
        if (!enabled)
            return "";
        var parts = [];
        if (chat.plasmoid.configuration.enableSystemPrompt !== false && chat.compiledSystemPrompt)
            parts.push(chat.compiledSystemPrompt);
        var chatPrompt = String(chat.getSessionProperty(sessionId, "chatSystemPrompt", "") || "").trim();
        if (chatPrompt)
            parts.push("--- Chat-specific instructions ---\n" + chatPrompt + "\n--- End chat-specific instructions ---");
        var responseLength = Number(chat.getSessionProperty(sessionId, "responseLength", 0)) || 0;
        var instructions = ["", "Keep the response short and focused, around 256 output tokens unless the task requires more.", "Give a balanced response, around 1024 output tokens at most.", "Give a detailed response, around 4096 output tokens at most.", "Give a comprehensive response, up to roughly 8192 output tokens when useful."];
        if (responseLength > 0 && responseLength < instructions.length)
            parts.push("Response length preference: " + instructions[responseLength]);
        return parts.join("\n\n");
    }

    function responseMaxTokens(sessionId, defaultValue) {
        var selected = Number(chat.getSessionProperty(sessionId, "responseLength", 0)) || 0;
        var limits = [defaultValue || 0, 512, 1024, 4096, 8192];
        return selected >= 0 && selected < limits.length ? limits[selected] : (defaultValue || 0);
    }

    function limitContextMessages(messageRoles) {
        var list = Array.isArray(messageRoles) ? messageRoles.slice() : [];
        var configured = Number(chat.plasmoid.configuration.contextMessageLimit);
        var maxMessages = configured >= 0 ? Math.min(100, configured + 1) : 100;
        if (list.length > maxMessages)
            list = list.slice(list.length - maxMessages);
        var totalChars = 0;
        var firstKept = list.length;
        for (var i = list.length - 1; i >= 0; i--) {
            var size = 0;
            try { size = JSON.stringify(list[i]).length; } catch (e) { size = String(list[i].content || "").length; }
            if (totalChars + size > 6000000 && firstKept < list.length)
                break;
            totalChars += size;
            firstKept = i;
        }
        return list.slice(firstKept);
    }

    // The messages of `sessionId` (not necessarily the chat on screen).
    function sessionMessages(sessionId) {
        if (sessionId === chat.currentSessionId)
            return chat.messages;
        var idx = chat.sessionIndexById(sessionId);
        return idx >= 0 ? (chat.sessions[idx].messages || []) : [];
    }

    // System prompt and conversation for a direct API request. withTools: replies that used
    // tools go back as tool calls and results; otherwise as text. `plain` is the conversation
    // as text, for a model that refuses tools (null when nothing used tools).
    function buildDirectRequestParts(sessionId, apiType, withTools) {
        var source = direct.sessionMessages(sessionId);
        var conversation = [];
        for (var i = 0; i < source.length; i++) {
            if (source[i].role === "user" || source[i].role === "assistant")
                conversation.push(source[i]);
        }
        conversation = direct.limitContextMessages(conversation);
        var asText = DirectTools.hasToolRounds(conversation);
        var messages = [], plain = [];
        for (var j = 0; j < conversation.length; j++) {
            var rm = conversation[j];
            var hasAttachments = rm.role === "user" && rm.attachments && rm.attachments.length > 0;
            if (rm.role === "assistant" && rm.toolRounds && rm.toolRounds.length > 0) {
                messages = messages.concat(DirectTools.historyMessages(apiType, rm, withTools));
                plain = plain.concat(DirectTools.historyMessages(apiType, rm, false));
                continue;
            }
            var item = {"role": rm.role, "content": hasAttachments ? MessageContent.build(rm.content, rm.attachments, apiType) : rm.content};
            messages.push(item);
            plain.push(item);
        }
        return {"system": direct.buildEffectiveSystemPrompt(sessionId), "messages": messages, "plain": asText ? plain : null};
    }

    // Sends a direct API request and applies its events to the chat.
    function doDirectRequest(cfg, sessionId, generation) {
        chat.loading = true;
        // The chat's variant (reasoning level), if it has one and the model still offers it.
        direct.directVariantRef.resolve(sessionId, cfg, function(variantSend) {
            if (chat.requestIsCurrent(sessionId, generation))
                direct.sendDirectRequest(cfg, sessionId, generation, variantSend);
        });
    }

    function sendDirectRequest(cfg, sessionId, generation, variantSend) {
        var apiType = cfg.type === "anthropic" ? "anthropic" : "openai";
        var tools = DirectTools.toolDefinitions(apiType, {"askUser": chat.plasmoid.configuration.allowAskUser !== false});
        var withTools = tools.length > 0 && !DirectBackend.rejectsTools({"baseUrl": cfg.baseUrl, "model": cfg.model || ""});
        var parts = direct.buildDirectRequestParts(sessionId, apiType, withTools);
        chat.currentStreamUsage = ({});
        chat.loading = true;
        direct.sendRound({"cfg": cfg, "sessionId": sessionId, "generation": generation, "variantSend": variantSend,
                          "apiType": apiType, "model": cfg.model || "", "system": parts.system, "messages": parts.messages,
                          "plain": parts.plain, "tools": tools, "round": 0, "roundText": "", "sepPending": false});
    }

    // Sends one request of a reply: the first, or the next after the tools the model called.
    function sendRound(ctx) {
        var collector = ctx.tools.length > 0 ? DirectTools.createCollector(ctx.apiType) : null;
        var toolCalls = null;
        ctx.roundText = "";
        chat.loading = true;
        chat.activeXhr = DirectBackend.send({
            "type": ctx.apiType,
            "baseUrl": ctx.cfg.baseUrl,
            "apiKey": ctx.cfg.apiKey,
            "model": ctx.model,
            "headers": ctx.cfg.headers,
            "system": ctx.system,
            "messages": ctx.messages,
            "plainMessages": ctx.plain,
            "tools": ctx.tools,
            "collector": collector,
            "maxTokens": direct.responseMaxTokens(ctx.sessionId, DirectBackend.DEFAULT_MAX_TOKENS),
            "variantSend": ctx.variantSend,
            "stream": chat.plasmoid.configuration.disableStreaming !== true,
            "timeoutMs": chat.plasmoid.configuration.requestTimeout > 0 ? chat.plasmoid.configuration.requestTimeout * 1000 : 0,
            "xhrFactory": direct.xhrFactory || function() { return new XMLHttpRequest(); },
            "thinkFactory": DirectStream.createThinkSplitter,
            "onEvent": function(event) {
                if (!chat.requestIsCurrent(ctx.sessionId, ctx.generation))
                    return;
                if (event.type === "tool_calls") {
                    toolCalls = event;
                    return;
                }
                if (event.type === "done" && event.reason === "complete" && toolCalls) {
                    direct.toolRounds.run(ctx, toolCalls);
                    return;
                }
                if (event.type === "text_delta") {
                    ctx.roundText += event.delta;
                    // A reply that goes on after a tool call continues on a new paragraph.
                    if (ctx.sepPending) {
                        ctx.sepPending = false;
                        event = {"type": "text_delta", "delta": "\n\n" + event.delta};
                    }
                }
                chat.applyBackendEvent(event, ctx.model);
            }
        });
    }

    // Ends the reply without asking the model again.
    function finishRequest(ctx) {
        chat.applyBackendEvent({"type": "done", "reason": "complete"}, ctx.model);
    }
}
