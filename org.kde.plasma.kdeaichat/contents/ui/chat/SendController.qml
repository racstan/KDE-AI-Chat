// Sending: takes the composer's text, queues it while a reply is running,
// checks the chat can be sent, and starts the request in the chat's mode
// (direct, OpenCode or Pi). Also tracks which request is current, so a reply
// never writes into another chat. `chat` is the widget root (main.qml).
import QtQuick
import "../ProviderService.js" as ProviderService
import "PromptTemplates.js" as PromptTemplates
import "TimeFormat.js" as TimeFormat

QtObject {
    id: sender

    property var chat: null
    property var notifierRef: null   // chat/Notifier.qml
    property var openCodeRef: null   // chat/OpenCodeMode.qml
    property var piAgentRef: null    // chat/PiMode.qml
    property var directToolsRef: null  // chat/DirectToolRounds.qml
    property var imageJobsRef: chat && chat.imageStore ? chat.imageStore.jobs : null   // chat/ImageJobs.qml

    function requestIsCurrent(sessionId, generation) {
        return !!sessionId && chat.currentSessionId === sessionId
            && chat.activeRequestSessionId === sessionId
            && chat.requestGeneration === generation;
    }

    function invalidateActiveRequest(processQueue) {
        if (sender.directToolsRef)
            sender.directToolsRef.cancelPending();
        chat.requestGeneration++;
        chat.activeRequestSessionId = "";
        if (chat.activeXhr) {
            try { chat.activeXhr.abort(); } catch (e) {}
            chat.activeXhr = null;
        }
        chat.resetProviderStreamingState();
        chat.loading = false;
        if (processQueue)
            sender.processNextQueuedMessage();
    }

    function beginRequest(sessionId) {
        chat.requestGeneration++;
        chat.activeRequestSessionId = sessionId;
        return chat.requestGeneration;
    }

    function pushErrorMessage(text) {
        var ts = Date.now();
        chat.messages = chat.messages.concat([{
            "role": "error",
            "content": text,
            "time": TimeFormat.nowTime(ts),
            "at": ts,
            "model": ""
        }]);
        chat.scrollToBottom();
        chat.saveCurrentSessionState(true);
        sender.notifierRef.failed(chat.currentSessionId, chat.currentSessionTitle, text);
    }

    // quotes: the messages quoted with this one ([{id, role, text}], MessageContent.js);
    // kept on the message, and put in front of its text in every request.
    function appendUserMessage(text, role, attachments, quotes) {
        var ts = Date.now();
        var message = {
            "role": role || "user",
            "content": text,
            "time": TimeFormat.nowTime(ts),
            "at": ts,
            "model": "",
            "queueId": role === "queued" ? (++chat.queueCounter) : 0,
            "attachments": attachments || []
        };
        if (quotes && quotes.length > 0)
            message.quotes = quotes;
        // After /memories: this message goes with all the chat's memories (chat/Memory.qml).
        if (chat.memory && chat.memory.takeAllNext(chat.currentSessionId))
            message.memoriesAll = true;
        chat.messages = chat.messages.concat([message]);
        if ((role || "user") === "user")
            chat.nameChatFromFirstMessage(text);
        chat.saveCurrentSessionState(true);
    }

    function validateCurrentSendTarget() {
        if (chat.openCodeMode)
            return sender.validateOpenCodeConfig(chat.currentSessionId);
        if (chat.piMode)
            return "";

        var provider = chat.getEffectiveProvider ? chat.getEffectiveProvider(chat.currentSessionId) : (chat.plasmoid.configuration.provider || "openai");
        var providerCfg = chat.getProviderConfig(provider, chat.currentSessionId);
        return sender.validateProviderConfig(provider, providerCfg);
    }

    function validateOpenCodeConfig(sessionId) {
        var missing = [];
        if (!chat.openCodeBaseUrl())
            missing.push("a valid OpenCode HTTP(S) URL");
        var eff = chat.effectiveConfig(sessionId);
        var provider = eff.provider, model = eff.model, agent = eff.agent;
        if (!provider && !agent)
            missing.push("OpenCode provider or agent");
        if (!model && !agent)
            missing.push("OpenCode model or agent");
        if (missing.length > 0)
            return "Cannot send yet. Configure: " + missing.join(", ") + ".";
        return "";
    }

    function validateProviderConfig(providerId, cfg) {
        if (!cfg)
            return "Provider configuration missing.";

        var name = chat.providerDisplayName(providerId);
        if (cfg.found === false)
            return "The provider \"" + name + "\" isn't set up any more. Add it in Widget Settings → General → Providers, or pick another provider in this chat's settings.";
        // An image service makes pictures from the message: it needs no model or URL, only to be switched on.
        if (cfg.type === "image")
            return sender.imageJobsRef.validate(providerId, cfg);
        var missing = [];
        if (!providerId)
            missing.push("provider");

        if (!cfg.baseUrl && cfg.type !== "anthropic")
            missing.push("base URL");

        if (!cfg.model)
            missing.push("model");

        if (cfg.type === "anthropic" && !cfg.apiKey)
            missing.push("API key");

        if (cfg.type !== "anthropic" && !cfg.allowEmptyKey && !cfg.apiKey)
            missing.push("API key");

        if (missing.length > 0)
            return "Cannot send message with " + name + ". Missing: " + missing.join(", ") + ". Please open Widget Settings (Configure KDE AI Chat) to set your API key or model."
                + (missing.indexOf("API key") !== -1 && !chat.wallet.usable && chat.wallet.status !== "unknown" ? " " + chat.wallet.statusMessage() : "");

        return "";
    }

    function sendMessage() {
        chat.ensureWalletLoaded();
        try {
            var text = (chat.chatInputText || "").trim();
            var attachments = chat.attachedFiles || [];

            text = PromptTemplates.expand(text, chat.promptTemplates);

            if (text.length > 200000) {
                sender.pushErrorMessage("Message is too large. Keep messages under 200,000 characters.");
                return;
            }
            if (text === "" && attachments.length === 0)
                return ;
            if (!chat.attachmentsReadyToSend()) {
                sender.pushErrorMessage("Please wait for attached files to finish loading before sending.");
                return;
            }

            for (var cleanupIndex = 0; cleanupIndex < attachments.length; cleanupIndex++)
                chat.cleanupTemporaryAttachment(attachments[cleanupIndex].path || "");
            chat.attachedFiles = [];
            chat.chatInputText = "";
            chat.clearChatInput();
            // Writing instead of answering ends the model's question: the request stops and this message is sent.
            if (chat.loading && sender.directToolsRef && sender.directToolsRef.hasPendingQuestion())
                chat.stopStreaming();
            // The quote chips above the box go with this message (and are cleared).
            var quotes = chat.composerRef && chat.composerRef.takeQuotes ? chat.composerRef.takeQuotes() : [];
            if (chat.loading) {
                sender.appendUserMessage(text, "queued", attachments, quotes);
                return ;
            }
            sender.appendUserMessage(text, "user", attachments, quotes);
            sender.sendMessageByIndex(chat.messages.length - 1);
        } catch (err) {
            chat.loading = false;
            chat.activeXhr = null;
            sender.pushErrorMessage("Send failed: " + err);
            sender.processNextQueuedMessage();
        }
    }

    function resetStream() {
        chat.currentStreamIndex = -1;
        chat.currentStreamText = "";
        chat.streamBuffer.clear();
        chat.currentStreamReasoning = "";
        chat.currentStreamExtractedReasoning = "";
        chat.streamingResponse = false;
    }

    // "/image <prompt>": makes a picture with the default image service as the reply to this message.
    // Returns {ok, code, problem}: code "none" when there is no image service yet, "invalid" with
    // `problem` (plain words) when the default one can't be used now.
    function sendImageCommand(prompt) {
        var providerId = ProviderService.defaultImageProvider(chat.plasmoid.configuration);
        if (providerId === "")
            return {"ok": false, "code": "none", "problem": ""};
        var cfg = chat.getProviderConfig(providerId, chat.currentSessionId);
        var problem = sender.imageJobsRef.validate(providerId, cfg);
        if (problem !== "")
            return {"ok": false, "code": "invalid", "problem": problem};
        sender.appendUserMessage("/image " + prompt, "user", [], []);
        sender.resetStream();
        var sessionId = chat.currentSessionId;
        chat.setCurrentSessionSource();
        sender.imageJobsRef.send(sessionId, sender.beginRequest(sessionId), cfg, providerId, prompt);
        return {"ok": true, "code": "", "problem": ""};
    }

    function sendMessageByIndex(index) {
        sender.resetStream();

        var source = chat.messages[index] || {
        };
        var text = (source.content || "").trim();
        var hasAttachments = source.attachments && source.attachments.length > 0;
        if (!text && !hasAttachments)
            return ;

        chat.applySessionSource(chat.sessions[chat.sessionIndexById(chat.currentSessionId)]);
        var validationError = sender.validateCurrentSendTarget();
        if (validationError !== "") {
            sender.pushErrorMessage(validationError);
            return ;
        }
        if ((source.role || "") === "queued") {
            var copy = chat.messages.slice();
            var queued = Object.assign({}, copy[index]);
            queued.role = "user";
            queued.at = Date.now();
            queued.time = TimeFormat.nowTime(queued.at);
            copy[index] = queued;
            chat.messages = copy;
            chat.nameChatFromFirstMessage(queued.content);
            chat.saveCurrentSessionState(true);
        }
        var requestSessionId = chat.currentSessionId;
        chat.setCurrentSessionSource();
        var requestGeneration = sender.beginRequest(requestSessionId);
        if (chat.openCodeMode) {
            sender.openCodeRef.send(requestSessionId, requestGeneration);
            return ;
        }
        if (chat.piMode) {
            sender.piAgentRef.send(requestSessionId, requestGeneration);
            return ;
        }
        var provider = chat.getEffectiveProvider(requestSessionId);
        var cfg = chat.getProviderConfig(provider, requestSessionId);
        if (cfg.type === "image") {
            // Every message of a chat with an image service becomes pictures (the chat stays a direct chat).
            sender.imageJobsRef.send(requestSessionId, requestGeneration, cfg, provider, text);
            return ;
        }
        chat.doDirectRequest(cfg, requestSessionId, requestGeneration);
    }

    function processNextQueuedMessage() {
        if (chat.loading)
            return ;

        for (var i = 0; i < chat.messages.length; i++) {
            if ((chat.messages[i].role || "") === "queued") {
                sender.sendMessageByIndex(i);
                return ;
            }
        }
    }

    function stopStreaming() {
        sender.invalidateActiveRequest(false);
        try { chat.saveCurrentSessionState(true); } catch (e) { console.error("Stop save failed:", e); }
        sender.processNextQueuedMessage();
    }
}
