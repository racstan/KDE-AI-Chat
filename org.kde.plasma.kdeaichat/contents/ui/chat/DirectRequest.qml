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
import "ImageExtract.js" as ImageExtract
import "Personality.js" as Personality

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

    // Memories are not here: they go with the message being answered
    // (chat/Memory.qml withMemories), so this stays the same from message to message.
    function buildEffectiveSystemPrompt(sessionId) {
        var enabled = chat.getSessionProperty(sessionId, "chatSystemPromptEnabled", true) !== false;
        if (!enabled)
            return "";
        var parts = [];
        if (chat.plasmoid.configuration.enableSystemPrompt !== false && chat.compiledSystemPrompt)
            parts.push(chat.compiledSystemPrompt);
        // The chat's project: its instructions come after the main ones, before the chat's own.
        var projectBlock = chat.projects ? chat.projects.instructionsBlock(sessionId) : "";
        if (projectBlock)
            parts.push(projectBlock);
        var chatPrompt = String(chat.getSessionProperty(sessionId, "chatSystemPrompt", "") || "").trim();
        if (chatPrompt)
            parts.push("--- Chat-specific instructions ---\n" + chatPrompt + "\n--- End chat-specific instructions ---");
        var responseLength = Number(chat.getSessionProperty(sessionId, "responseLength", 0)) || 0;
        var instructions = ["", "Keep the response short and focused, around 256 output tokens unless the task requires more.", "Give a balanced response, around 1024 output tokens at most.", "Give a detailed response, around 4096 output tokens at most.", "Give a comprehensive response, up to roughly 8192 output tokens when useful."];
        if (responseLength > 0 && responseLength < instructions.length)
            parts.push("Response length preference: " + instructions[responseLength]);
        return parts.join("\n\n");
    }

    // Direct mode: the Personality block (Settings → Personality) first, then
    // everything above. OpenCode and Pi add the same block themselves
    // (OpenCodeMode.qml, PiMode.qml). A chat can turn it off (personalityOff),
    // independently of its own instructions.
    function directSystemPrompt(sessionId) {
        var rest = direct.buildEffectiveSystemPrompt(sessionId);
        var off = chat.getSessionProperty(sessionId, "personalityOff", false) === true;
        var block = off ? "" : Personality.block(chat.plasmoid.configuration);
        return block && rest ? block + "\n\n" + rest : (block || rest);
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
        if (idx >= 0 && chat.sessions[idx].messagesUnloaded)
            chat.messageLoader.ensure(sessionId);
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
            var extras = rm.role === "user" && ((rm.attachments && rm.attachments.length > 0) || (rm.quotes && rm.quotes.length > 0));
            if (rm.role === "assistant" && rm.toolRounds && rm.toolRounds.length > 0) {
                messages = messages.concat(DirectTools.historyMessages(apiType, rm, withTools));
                plain = plain.concat(DirectTools.historyMessages(apiType, rm, false));
                continue;
            }
            // A reply that is only a picture goes back as a short note, never as an empty message.
            var said = rm.content || (rm.role === "assistant" && (rm.images || []).length > 0 ? "[image]" : "");
            var item = {"role": rm.role, "content": extras ? MessageContent.build(rm.content, chat.messageLoader ? chat.messageLoader.resolve(rm.attachments) : rm.attachments, apiType, rm.quotes) : said};
            messages.push(item);
            plain.push(item);
        }
        direct.addMemories(sessionId, messages);
        return {"system": direct.directSystemPrompt(sessionId), "messages": messages, "plain": asText ? plain : null};
    }

    // The memories for this request go at the start of the last user message
    // (text, or the first text part of one with pictures). `plain` shares the item.
    function addMemories(sessionId, messages) {
        for (var i = messages.length - 1; i >= 0; i--) {
            if (messages[i].role !== "user")
                continue;
            var content = messages[i].content;
            if (typeof content === "string") {
                messages[i].content = chat.memory ? chat.memory.withMemories(sessionId, content) : content;
            } else if (Array.isArray(content)) {
                var parts = content.slice();
                for (var k = 0; k < parts.length; k++) {
                    if (parts[k] && parts[k].type === "text") {
                        parts[k] = Object.assign({}, parts[k], {"text": chat.memory ? chat.memory.withMemories(sessionId, parts[k].text || "") : parts[k].text});
                        break;
                    }
                }
                messages[i].content = parts;
            }
            return;
        }
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
            "images": ImageExtract,
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
