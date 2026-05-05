import QtQuick

// ─────────────────────────────────────────────────────────────────────────────
//  Kai Chat – background API worker (Plasma 6 WorkerScript / ES module)
//
//  Providers and their base URLs:
//    openai      https://api.openai.com/v1                (openai-compat)
//    anthropic   https://api.anthropic.com/v1/messages    (native)
//    gemini      https://generativelanguage.googleapis.com/v1beta/openai/ (compat)
//    mistral     https://api.mistral.ai/v1                (openai-compat)
//    grok        https://api.x.ai/v1                      (openai-compat)
//    deepseek    https://api.deepseek.com/v1              (openai-compat)
//    nvidia      https://integrate.api.nvidia.com/v1      (openai-compat)
//    cerebras    https://api.cerebras.ai/v1               (openai-compat)
//    cloudflare  https://api.cloudflare.com/client/v4/accounts/{id}/ai/v1 (compat)
//    huggingface https://api-inference.huggingface.co/v1  (openai-compat)
//    openrouter  https://openrouter.ai/api/v1             (openai-compat)
//    litellm     <user-configured>                        (openai-compat)
//    local       <user-configured>                        (openai-compat)
//    opencode    <user-configured, default :4096>         (native REST)
// ─────────────────────────────────────────────────────────────────────────────

WorkerScript {
    onMessage: function(msg) {
        var p = msg.provider
        var c = msg.config
        var messages = msg.messages

        var temperature = (typeof c.temperature === "number") ? c.temperature : 0.7

        if (p === "anthropic") {
            callAnthropic(c, messages, temperature)
        } else if (p === "opencode") {
            callOpenCode(c, messages)
        } else {
            // Resolve OpenAI-compatible parameters for the given provider
            var resolved = resolveOpenAICompat(p, c)
            if (!resolved) {
                WorkerScript.sendMessage({ content: "", error: "Unknown provider: " + p })
                return
            }
            callOpenAICompat(resolved.baseUrl, resolved.apiKey, resolved.model, messages, p, temperature)
        }
    }

    // ── Provider → OpenAI-compat params ──────────────────────────────────
    function resolveOpenAICompat(provider, c) {
        switch (provider) {
        case "openai":
            return { baseUrl: c.openaiBaseUrl, apiKey: c.openaiApiKey, model: c.openaiModel }
        case "gemini":
            return {
                baseUrl: "https://generativelanguage.googleapis.com/v1beta/openai",
                apiKey:  c.geminiApiKey,
                model:   c.geminiModel
            }
        case "mistral":
            return { baseUrl: "https://api.mistral.ai/v1", apiKey: c.mistralApiKey, model: c.mistralModel }
        case "grok":
            return { baseUrl: "https://api.x.ai/v1", apiKey: c.grokApiKey, model: c.grokModel }
        case "deepseek":
            return { baseUrl: "https://api.deepseek.com/v1", apiKey: c.deepseekApiKey, model: c.deepseekModel }
        case "nvidia":
            return { baseUrl: "https://integrate.api.nvidia.com/v1", apiKey: c.nvidiaApiKey, model: c.nvidiaModel }
        case "cerebras":
            return { baseUrl: "https://api.cerebras.ai/v1", apiKey: c.cerebrasApiKey, model: c.cerebrasModel }
        case "cloudflare":
            return {
                baseUrl: "https://api.cloudflare.com/client/v4/accounts/" + c.cfAccountId + "/ai/v1",
                apiKey:  c.cfApiToken,
                model:   c.cfModel
            }
        case "huggingface":
            return { baseUrl: "https://api-inference.huggingface.co/v1", apiKey: c.hfApiKey, model: c.hfModel }
        case "openrouter":
            return { baseUrl: "https://openrouter.ai/api/v1", apiKey: c.openrouterApiKey, model: c.openrouterModel }
        case "litellm":
            return { baseUrl: c.litellmBaseUrl, apiKey: c.litellmApiKey || "no-key", model: c.litellmModel }
        case "local":
            return { baseUrl: c.localBaseUrl, apiKey: "", model: c.localModel }
        default:
            return null
        }
    }

    // ── OpenAI-compatible handler ─────────────────────────────────────────
    function callOpenAICompat(baseUrl, apiKey, model, messages, providerLabel, temperature) {
        var xhr = new XMLHttpRequest()
        var url = baseUrl.replace(/\/$/, "") + "/chat/completions"

        xhr.open("POST", url, true)
        xhr.setRequestHeader("Content-Type", "application/json")
        if (apiKey && apiKey !== "" && apiKey !== "no-key") {
            xhr.setRequestHeader("Authorization", "Bearer " + apiKey)
        }
        // OpenRouter asks for a site URL and app name for rankings (optional but polite)
        if (providerLabel === "openrouter") {
            xhr.setRequestHeader("HTTP-Referer", "https://kde.org")
            xhr.setRequestHeader("X-Title", "Kai Chat")
        }

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText)
                    var content = response.choices[0].message.content
                    WorkerScript.sendMessage({ content: content, model: model, error: null })
                } catch (e) {
                    WorkerScript.sendMessage({ content: "", error: "Failed to parse response: " + e })
                }
            } else {
                try {
                    var errResp = JSON.parse(xhr.responseText)
                    var errMsg = (errResp.error && errResp.error.message)
                                 ? errResp.error.message
                                 : xhr.statusText
                    WorkerScript.sendMessage({ content: "", error: "API Error (" + xhr.status + "): " + errMsg })
                } catch (e) {
                    WorkerScript.sendMessage({ content: "", error: "HTTP " + xhr.status + ": " + xhr.statusText })
                }
            }
        }
        xhr.onerror = function() {
            WorkerScript.sendMessage({ content: "", error: "Network error reaching " + baseUrl + ". Check URL and connection." })
        }

        var body = { model: model, messages: messages, temperature: temperature }
        xhr.send(JSON.stringify(body))
    }

    // ── Anthropic native handler ──────────────────────────────────────────
    function callAnthropic(c, messages, temperature) {
        var apiKey = c.anthropicApiKey
        var model  = c.anthropicModel

        var systemContent = ""
        var anthropicMessages = []
        for (var i = 0; i < messages.length; i++) {
            if (messages[i].role === "system") {
                systemContent = messages[i].content
            } else if (messages[i].role === "user" || messages[i].role === "assistant") {
                anthropicMessages.push({ role: messages[i].role, content: messages[i].content })
            }
        }

        var xhr = new XMLHttpRequest()
        xhr.open("POST", "https://api.anthropic.com/v1/messages", true)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("x-api-key", apiKey)
        xhr.setRequestHeader("anthropic-version", "2023-06-01")

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText)
                    var content = ""
                    if (response.content && response.content.length > 0)
                        content = response.content[0].text
                    WorkerScript.sendMessage({ content: content, model: model, error: null })
                } catch (e) {
                    WorkerScript.sendMessage({ content: "", error: "Failed to parse Anthropic response: " + e })
                }
            } else {
                try {
                    var errResp = JSON.parse(xhr.responseText)
                    var errMsg = (errResp.error && errResp.error.message)
                                 ? errResp.error.message
                                 : xhr.statusText
                    WorkerScript.sendMessage({ content: "", error: "Anthropic Error (" + xhr.status + "): " + errMsg })
                } catch (e) {
                    WorkerScript.sendMessage({ content: "", error: "HTTP " + xhr.status + ": " + xhr.statusText })
                }
            }
        }
        xhr.onerror = function() {
            WorkerScript.sendMessage({ content: "", error: "Network error reaching Anthropic API." })
        }

        var body = { model: model, max_tokens: 4096, messages: anthropicMessages, temperature: temperature }
        if (systemContent) body.system = systemContent
        xhr.send(JSON.stringify(body))
    }

    // ── OpenCode Bridge (BETA) ─────────────────────────────────────────────
    //
    //  Flow:
    //    1. If no sessionId, POST /session  → get new sessionId, bubble it
    //       back to QML via opencodeSessionId in the reply.
    //    2. POST /session/{id}/message  with { parts: [{ type:"text", text }] }
    //    3. Extract text from the returned parts array.
    //
    //  The session persists across messages so OpenCode retains context.
    //  A "new session" resets root.opencodeSessionId on the QML side.
    // ─────────────────────────────────────────────────────────────────────────
    function callOpenCode(c, messages) {
        var serverUrl  = (c.opencodeServerUrl || "http://localhost:4096").replace(/\/$/, "")
        var sessionId  = c.opencodeSessionId || ""

        // Extract just the last user message (OpenCode manages its own context)
        var userText = ""
        for (var i = messages.length - 1; i >= 0; i--) {
            if (messages[i].role === "user") {
                userText = messages[i].content
                break
            }
        }
        if (!userText) {
            WorkerScript.sendMessage({ content: "", error: "No user message to send to OpenCode." })
            return
        }

        if (sessionId && sessionId !== "") {
            sendOpenCodeMessage(serverUrl, sessionId, userText, false)
        } else {
            createOpenCodeSession(serverUrl, userText)
        }
    }

    function createOpenCodeSession(serverUrl, userText) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", serverUrl + "/session", true)
        xhr.setRequestHeader("Content-Type", "application/json")

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200 || xhr.status === 201) {
                try {
                    var session = JSON.parse(xhr.responseText)
                    var newId = session.id || session.sessionID || session.sessionId || ""
                    if (!newId) {
                        WorkerScript.sendMessage({ content: "", error: "OpenCode: session created but no ID returned." })
                        return
                    }
                    sendOpenCodeMessage(serverUrl, newId, userText, true)
                } catch (e) {
                    WorkerScript.sendMessage({ content: "", error: "OpenCode: failed to parse session response: " + e })
                }
            } else {
                WorkerScript.sendMessage({ content: "",
                    error: "OpenCode: failed to create session (HTTP " + xhr.status + "). Is OpenCode running? Try: opencode serve" })
            }
        }
        xhr.onerror = function() {
            WorkerScript.sendMessage({ content: "",
                error: "OpenCode: cannot connect to " + serverUrl + ". Start OpenCode with: opencode serve" })
        }

        xhr.send(JSON.stringify({}))
    }

    function sendOpenCodeMessage(serverUrl, sessionId, userText, isNewSession) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", serverUrl + "/session/" + sessionId + "/message", true)
        xhr.setRequestHeader("Content-Type", "application/json")

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200 || xhr.status === 201) {
                try {
                    var response = JSON.parse(xhr.responseText)
                    // Response shape: { info: AssistantMessage, parts: Part[] }
                    var content = extractOpenCodeText(response)
                    var reply = { content: content, model: "opencode", error: null }
                    if (isNewSession) reply.opencodeSessionId = sessionId
                    WorkerScript.sendMessage(reply)
                } catch (e) {
                    WorkerScript.sendMessage({ content: "", error: "OpenCode: failed to parse message response: " + e })
                }
            } else if (xhr.status === 404 && !isNewSession) {
                // Session expired – the stored ID is stale; report clearly
                WorkerScript.sendMessage({ content: "",
                    error: "OpenCode session not found. Use the + button to start a new session." })
            } else {
                WorkerScript.sendMessage({ content: "",
                    error: "OpenCode message error (HTTP " + xhr.status + "): " + xhr.statusText })
            }
        }
        xhr.onerror = function() {
            WorkerScript.sendMessage({ content: "",
                error: "OpenCode: connection lost to " + serverUrl + ". Is OpenCode still running?" })
        }

        var body = {
            parts: [{ type: "text", text: userText }]
        }
        xhr.send(JSON.stringify(body))
    }

    function extractOpenCodeText(response) {
        // Primary: parts array with type=text
        if (response.parts && Array.isArray(response.parts)) {
            var chunks = []
            for (var i = 0; i < response.parts.length; i++) {
                var part = response.parts[i]
                if (part.type === "text" && part.text) chunks.push(part.text)
                else if (part.type === "text" && part.content) chunks.push(part.content)
            }
            if (chunks.length > 0) return chunks.join("")
        }
        // Fallback: info.content (some versions)
        if (response.info && response.info.content) {
            if (typeof response.info.content === "string") return response.info.content
            if (Array.isArray(response.info.content)) {
                var text = ""
                for (var j = 0; j < response.info.content.length; j++) {
                    if (response.info.content[j].text) text += response.info.content[j].text
                }
                return text
            }
        }
        // Last resort: stringify for debugging
        return JSON.stringify(response)
    }
}
