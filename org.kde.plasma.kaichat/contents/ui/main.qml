import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation
    Plasmoid.icon: "dialog-messages"
    hideOnWindowDeactivate: false
    fullRepresentation: fullRep
    compactRepresentation: compactRep

    property var chatModel: []
    property bool isLoading: false
    property string currentProvider: plasmoid.configuration.provider
    property string opencodeSessionId: plasmoid.configuration.opencodeSessionId || ""

    // Compact state: idle | streaming | done | error
    property string compactState: "idle"
    property string lastAssistantPreview: "Open Kai Chat"

    // Streaming state
    property var activeStreamXhr: null
    property string sseBuffer: ""
    property int sseOffset: 0
    property int streamingAssistantIndex: -1
    property bool userScrolled: false
    property string attachmentText: ""
    property string attachmentLabel: ""

    // Session persistence
    property string conversationDir: "$HOME/.local/share/plasmoids/org.kde.plasma.kaichat/conversations"
    property var sessionsModel: []
    property string currentSessionId: plasmoid.configuration.lastSessionId || ""
    property string currentSessionTitle: "New Chat"
    property string currentSessionCreatedAt: ""
    property string convOp: ""

    // Global activation support (shortcut tab in Plasma config uses this)
    property var inputFieldRef: null
    property var chatListViewRef: null
    property var runtimeApiKeys: ({})
    property var pendingMessages: []
    property bool pendingSendAfterSecretLookup: false
    property string pendingSecretProvider: ""

    property bool hasValidConfig: {
        switch (currentProvider) {
        case "openai":      return (runtimeApiKeys.openai || plasmoid.configuration.openaiApiKey)      !== ""
        case "anthropic":   return (runtimeApiKeys.anthropic || plasmoid.configuration.anthropicApiKey) !== ""
        case "gemini":      return (runtimeApiKeys.gemini || plasmoid.configuration.geminiApiKey)      !== ""
        case "mistral":     return (runtimeApiKeys.mistral || plasmoid.configuration.mistralApiKey)    !== ""
        case "grok":        return (runtimeApiKeys.grok || plasmoid.configuration.grokApiKey)          !== ""
        case "deepseek":    return (runtimeApiKeys.deepseek || plasmoid.configuration.deepseekApiKey)  !== ""
        case "nvidia":      return (runtimeApiKeys.nvidia || plasmoid.configuration.nvidiaApiKey)      !== ""
        case "cerebras":    return (runtimeApiKeys.cerebras || plasmoid.configuration.cerebrasApiKey)  !== ""
        case "cloudflare":  return plasmoid.configuration.cfAccountId       !== ""
                                && (runtimeApiKeys.cloudflare || plasmoid.configuration.cfApiToken)      !== ""
        case "huggingface": return (runtimeApiKeys.huggingface || plasmoid.configuration.hfApiKey)     !== ""
        case "openrouter":  return (runtimeApiKeys.openrouter || plasmoid.configuration.openrouterApiKey)!== ""
        case "litellm":     return true
        case "local":       return true
        case "opencode":    return true
        default:             return false
        }
    }

    function activate() {
        plasmoid.expanded = true
        if (root.inputFieldRef) {
            root.inputFieldRef.forceActiveFocus()
        }
    }

    onExpandedChanged: {
        if (plasmoid.expanded) {
            Qt.callLater(function() {
                if (root.inputFieldRef)
                    root.inputFieldRef.forceActiveFocus()
            })
        }
    }

    Timer {
        id: stateResetTimer
        interval: 1400
        repeat: false
        onTriggered: {
            if (!root.isLoading)
                root.compactState = "idle"
        }
    }

    P5Support.DataSource {
        id: execDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var out = (data["stdout"] || "").trim()
            var err = (data["stderr"] || "").trim()
            if (out !== "" || err !== "") {
                root.chatModel.push({ role: "system", content: "CLI: " + (out !== "" ? out : err), timestamp: nowIso(), model: "" })
                root.chatModel = root.chatModel
                maybeAutoScroll()
            }
            disconnectSource(sourceName)
            saveConversation()
        }
    }

    P5Support.DataSource {
        id: convDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var out = data["stdout"] || ""
            var err = data["stderr"] || ""

            if (root.convOp === "list") {
                var ids = out.trim() === "" ? [] : out.trim().split("\n")
                var mapped = []
                for (var i = 0; i < ids.length; i++) {
                    mapped.push({ value: ids[i], text: ids[i] })
                }
                root.sessionsModel = mapped

                if (ids.length === 0) {
                    startNewSession()
                } else {
                    var preferred = root.currentSessionId
                    var found = false
                    for (var j = 0; j < ids.length; j++) {
                        if (ids[j] === preferred) {
                            found = true
                            break
                        }
                    }
                    loadConversation(found ? preferred : ids[0])
                }
            } else if (root.convOp === "load") {
                try {
                    var obj = JSON.parse(out)
                    root.currentSessionId = obj.id || makeSessionId()
                    root.currentSessionTitle = obj.title || "New Chat"
                    root.currentSessionCreatedAt = obj.createdAt || nowIso()
                    root.chatModel = obj.messages || []
                    root.lastAssistantPreview = previewFromMessages(root.chatModel)
                    plasmoid.configuration.lastSessionId = root.currentSessionId
                } catch (e) {
                    root.chatModel = []
                    pushError("Failed to load session JSON: " + e)
                }
            } else if (root.convOp === "save") {
                // Refresh list after save so new sessions appear in dropdown.
                refreshSessions()
            }

            if (err.trim() !== "" && root.convOp !== "list") {
                pushError("Session I/O error: " + err.trim())
            }
            disconnectSource(sourceName)
        }
    }

    P5Support.DataSource {
        id: clipDs
        engine: "executable"
        connectedSources: []
        property bool readingPrimary: false
        onNewData: function(sourceName, data) {
            var out = (data["stdout"] || "")
            var text = out.trim()
            if (text === "") {
                disconnectSource(sourceName)
                return
            }

            if (text.length > 500) {
                root.attachmentText = text
                root.attachmentLabel = "Clipboard content attached (" + formatBytes(text.length) + ")"
            } else if (root.inputFieldRef) {
                root.inputFieldRef.text = quoteForPrompt(text) + root.inputFieldRef.text
                root.inputFieldRef.forceActiveFocus()
            }
            disconnectSource(sourceName)
        }
    }

    P5Support.DataSource {
        id: secretDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var key = (data["stdout"] || "").trim()
            if (root.pendingSendAfterSecretLookup) {
                if (key !== "") {
                    root.runtimeApiKeys[root.pendingSecretProvider] = key
                    var messages = root.pendingMessages
                    root.pendingMessages = []
                    root.pendingSendAfterSecretLookup = false
                    dispatchMessages(messages)
                } else {
                    root.pendingMessages = []
                    root.pendingSendAfterSecretLookup = false
                    pushError("No API key found in Secret Service for provider: " + root.pendingSecretProvider)
                }
            }
            disconnectSource(sourceName)
        }
    }

    P5Support.DataSource {
        id: notifyDs
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            disconnectSource(sourceName)
        }
    }

    function runCli(program, args) {
        var parts = [program]
        for (var i = 0; i < args.length - 1; i++)
            parts.push(args[i])

        var last = (args.length > 0 ? args[args.length - 1] : "").replace(/'/g, "'\\''")
        parts.push("'" + last + "'")
        execDs.connectSource(parts.join(" "))
    }

    function writeToClipboard(text) {
        var escaped = (text || "").replace(/'/g, "'\\''")
        var cmd = "sh -lc \"if [ -n '$WAYLAND_DISPLAY' ]; then printf '%s' '" + escaped + "' | wl-copy; else printf '%s' '" + escaped + "' | xclip -selection clipboard; fi\""
        execDs.connectSource(cmd)
    }

    function requestClipboard(usePrimarySelection) {
        var cmd = "sh -lc \"if [ -n '$WAYLAND_DISPLAY' ]; then wl-paste " + (usePrimarySelection ? "-p" : "") + "; else xclip -o -selection " + (usePrimarySelection ? "primary" : "clipboard") + "; fi\""
        clipDs.connectSource(cmd)
    }

    function quoteForPrompt(text) {
        return "> " + text.replace(/\n/g, "\n> ") + "\n\n"
    }

    function formatBytes(chars) {
        var bytes = chars
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB"
        return (bytes / (1024 * 1024)).toFixed(1) + " MB"
    }

    function extractCodeBlocks(text) {
        var blocks = []
        var re = /```[\w-]*\n([\s\S]*?)```/g
        var m
        while ((m = re.exec(text || "")) !== null) {
            blocks.push(m[1])
        }
        return blocks
    }

    function providerHasKeyRequirement(provider) {
        return provider !== "local" && provider !== "litellm" && provider !== "opencode"
    }

    function providerSecretName(provider) {
        return "kai-chat-" + provider
    }

    function ensureProviderKeyThenDispatch(messages) {
        if (!providerHasKeyRequirement(root.currentProvider)) {
            dispatchMessages(messages)
            return
        }

        var cfg = apiConfig()
        if (root.currentProvider === "anthropic") {
            if (cfg.anthropicApiKey && cfg.anthropicApiKey !== "") {
                dispatchMessages(messages)
                return
            }
        } else {
            var resolved = resolveOpenAICompat(root.currentProvider, cfg)
            if (resolved && resolved.apiKey && resolved.apiKey !== "") {
                dispatchMessages(messages)
                return
            }
        }

        root.pendingSendAfterSecretLookup = true
        root.pendingMessages = messages
        root.pendingSecretProvider = root.currentProvider
        var service = providerSecretName(root.currentProvider)
        var cmd = "sh -lc \"secret-tool lookup service " + service + " account default 2>/dev/null\""
        secretDs.connectSource(cmd)
    }

    function notifyBackgroundCompletion(text) {
        if (plasmoid.expanded || !plasmoid.configuration.notifyOnBackgroundCompletion)
            return
        var body = (text || "").split("\n")[0]
        if (body.length > 120)
            body = body.slice(0, 120) + "..."
        var title = "Kai Chat - " + (root.currentSessionTitle || "Response ready")
        var safeTitle = title.replace(/'/g, "'\\''")
        var safeBody = body.replace(/'/g, "'\\''")
        var cmd = "sh -lc \"notify-send '" + safeTitle + "' '" + safeBody + "'\""
        notifyDs.connectSource(cmd)
    }

    function nowIso() {
        return new Date().toISOString()
    }

    function makeSessionId() {
        return "session-" + Date.now() + "-" + Math.floor(Math.random() * 100000)
    }

    function sessionFile(sessionId) {
        return root.conversationDir + "/" + sessionId + ".json"
    }

    function runConvCommand(mode, cmd) {
        root.convOp = mode
        convDs.connectSource(cmd)
    }

    function refreshSessions() {
        var cmd = "sh -lc \"mkdir -p " + root.conversationDir + "; for f in $(ls -1t " + root.conversationDir + "/*.json 2>/dev/null); do basename \\\"$f\\\" .json; done\""
        runConvCommand("list", cmd)
    }

    function loadConversation(sessionId) {
        if (!sessionId || sessionId === "") return
        root.currentSessionId = sessionId
        plasmoid.configuration.lastSessionId = sessionId
        var cmd = "sh -lc \"cat " + sessionFile(sessionId) + "\""
        runConvCommand("load", cmd)
    }

    function saveConversation() {
        if (!root.currentSessionId || root.currentSessionId === "")
            root.currentSessionId = makeSessionId()

        var title = root.currentSessionTitle
        if (!title || title === "New Chat") {
            title = autoTitleFromConversation()
            root.currentSessionTitle = title
        }

        var payload = {
            id: root.currentSessionId,
            title: title,
            createdAt: root.currentSessionCreatedAt || nowIso(),
            updatedAt: nowIso(),
            messages: root.chatModel
        }

        var json = JSON.stringify(payload)
        var escaped = json.replace(/'/g, "'\\''")
        var cmd = "sh -lc \"mkdir -p " + root.conversationDir + "; printf '%s' '" + escaped + "' > " + sessionFile(root.currentSessionId) + "\""
        runConvCommand("save", cmd)
    }

    function startNewSession() {
        root.currentSessionId = makeSessionId()
        root.currentSessionTitle = "New Chat"
        root.currentSessionCreatedAt = nowIso()
        root.chatModel = []
        root.lastAssistantPreview = "Open Kai Chat"
        plasmoid.configuration.lastSessionId = root.currentSessionId
        saveConversation()
    }

    function previewFromMessages(messages) {
        for (var i = messages.length - 1; i >= 0; i--) {
            if (messages[i].role === "assistant") {
                var txt = (messages[i].content || "").split("\n")[0]
                return txt.length > 90 ? txt.slice(0, 90) + "..." : txt
            }
        }
        return "Open Kai Chat"
    }

    function autoTitleFromConversation() {
        for (var i = 0; i < root.chatModel.length; i++) {
            if (root.chatModel[i].role === "user") {
                var words = (root.chatModel[i].content || "").trim().split(/\s+/)
                return words.slice(0, 5).join(" ") || "New Chat"
            }
        }
        return "New Chat"
    }

    function pushError(text) {
        root.chatModel.push({ role: "error", content: text, timestamp: nowIso(), model: "" })
        root.chatModel = root.chatModel
        root.compactState = "error"
        root.isLoading = false
        stateResetTimer.restart()
        maybeAutoScroll()
    }

    function apiConfig() {
        return {
            openaiApiKey:      runtimeApiKeys.openai || plasmoid.configuration.openaiApiKey,
            openaiBaseUrl:     plasmoid.configuration.openaiBaseUrl,
            openaiModel:       plasmoid.configuration.openaiModel,
            anthropicApiKey:   runtimeApiKeys.anthropic || plasmoid.configuration.anthropicApiKey,
            anthropicModel:    plasmoid.configuration.anthropicModel,
            geminiApiKey:      runtimeApiKeys.gemini || plasmoid.configuration.geminiApiKey,
            geminiModel:       plasmoid.configuration.geminiModel,
            mistralApiKey:     runtimeApiKeys.mistral || plasmoid.configuration.mistralApiKey,
            mistralModel:      plasmoid.configuration.mistralModel,
            grokApiKey:        runtimeApiKeys.grok || plasmoid.configuration.grokApiKey,
            grokModel:         plasmoid.configuration.grokModel,
            deepseekApiKey:    runtimeApiKeys.deepseek || plasmoid.configuration.deepseekApiKey,
            deepseekModel:     plasmoid.configuration.deepseekModel,
            nvidiaApiKey:      runtimeApiKeys.nvidia || plasmoid.configuration.nvidiaApiKey,
            nvidiaModel:       plasmoid.configuration.nvidiaModel,
            cerebrasApiKey:    runtimeApiKeys.cerebras || plasmoid.configuration.cerebrasApiKey,
            cerebrasModel:     plasmoid.configuration.cerebrasModel,
            cfAccountId:       plasmoid.configuration.cfAccountId,
            cfApiToken:        runtimeApiKeys.cloudflare || plasmoid.configuration.cfApiToken,
            cfModel:           plasmoid.configuration.cfModel,
            hfApiKey:          runtimeApiKeys.huggingface || plasmoid.configuration.hfApiKey,
            hfModel:           plasmoid.configuration.hfModel,
            openrouterApiKey:  runtimeApiKeys.openrouter || plasmoid.configuration.openrouterApiKey,
            openrouterModel:   plasmoid.configuration.openrouterModel,
            litellmBaseUrl:    plasmoid.configuration.litellmBaseUrl,
            litellmApiKey:     runtimeApiKeys.litellm || plasmoid.configuration.litellmApiKey,
            litellmModel:      plasmoid.configuration.litellmModel,
            localBaseUrl:      plasmoid.configuration.localBaseUrl,
            localModel:        plasmoid.configuration.localModel,
            opencodeServerUrl: plasmoid.configuration.opencodeServerUrl,
            opencodeSessionId: root.opencodeSessionId,
            temperature:       plasmoid.configuration.temperature
        }
    }

    function buildMessages() {
        var msgs = [{ role: "system", content: plasmoid.configuration.systemPrompt }]
        for (var i = 0; i < root.chatModel.length; i++) {
            var m = root.chatModel[i]
            if (m.role === "user" || m.role === "assistant")
                msgs.push({ role: m.role, content: m.content })
        }
        return msgs
    }

    function resolveOpenAICompat(provider, c) {
        switch (provider) {
        case "openai":
            return { baseUrl: c.openaiBaseUrl, apiKey: c.openaiApiKey, model: c.openaiModel }
        case "gemini":
            return { baseUrl: "https://generativelanguage.googleapis.com/v1beta/openai", apiKey: c.geminiApiKey, model: c.geminiModel }
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
            return { baseUrl: "https://api.cloudflare.com/client/v4/accounts/" + c.cfAccountId + "/ai/v1", apiKey: c.cfApiToken, model: c.cfModel }
        case "huggingface":
            return { baseUrl: "https://api-inference.huggingface.co/v1", apiKey: c.hfApiKey, model: c.hfModel }
        case "openrouter":
            return { baseUrl: "https://openrouter.ai/api/v1", apiKey: c.openrouterApiKey, model: c.openrouterModel }
        case "litellm":
            return { baseUrl: c.litellmBaseUrl, apiKey: c.litellmApiKey || "", model: c.litellmModel }
        case "local":
            return { baseUrl: c.localBaseUrl, apiKey: "", model: c.localModel }
        default:
            return null
        }
    }

    function startStreamingOpenAICompat(messages) {
        var c = apiConfig()
        var resolved = resolveOpenAICompat(root.currentProvider, c)
        if (!resolved)
            return false

        var xhr = new XMLHttpRequest()
        var url = resolved.baseUrl.replace(/\/$/, "") + "/chat/completions"

        root.isLoading = true
        root.compactState = "streaming"
        root.sseOffset = 0
        root.sseBuffer = ""
        root.streamingAssistantIndex = -1
        root.activeStreamXhr = xhr

        xhr.open("POST", url, true)
        xhr.setRequestHeader("Content-Type", "application/json")
        if (resolved.apiKey && resolved.apiKey !== "")
            xhr.setRequestHeader("Authorization", "Bearer " + resolved.apiKey)
        if (root.currentProvider === "openrouter") {
            xhr.setRequestHeader("HTTP-Referer", "https://kde.org")
            xhr.setRequestHeader("X-Title", "Kai Chat")
        }

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.LOADING || xhr.readyState === XMLHttpRequest.DONE) {
                var delta = xhr.responseText.slice(root.sseOffset)
                root.sseOffset = xhr.responseText.length
                processSseDelta(delta)
            }

            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status >= 200 && xhr.status < 300) {
                    finishStreamingSuccess()
                } else {
                    var err = "HTTP " + xhr.status + ": " + xhr.statusText
                    try {
                        var obj = JSON.parse(xhr.responseText)
                        if (obj.error && obj.error.message)
                            err = obj.error.message
                    } catch (e) {}
                    finishStreamingError(err)
                }
            }
        }
        xhr.onerror = function() {
            finishStreamingError("Network error reaching " + resolved.baseUrl)
        }

        var body = {
            model: resolved.model,
            messages: messages,
            temperature: c.temperature,
            stream: true
        }
        xhr.send(JSON.stringify(body))
        return true
    }

    function ensureStreamingAssistantMessage() {
        if (root.streamingAssistantIndex >= 0)
            return

        root.chatModel.push({
            role: "assistant",
            content: "",
            timestamp: nowIso(),
            model: root.currentProvider
        })
        root.streamingAssistantIndex = root.chatModel.length - 1
        root.chatModel = root.chatModel
    }

    function processSseDelta(chunk) {
        if (!chunk || chunk === "")
            return

        root.sseBuffer += chunk

        while (true) {
            var idx = root.sseBuffer.indexOf("\n\n")
            if (idx < 0)
                break

            var block = root.sseBuffer.slice(0, idx)
            root.sseBuffer = root.sseBuffer.slice(idx + 2)

            var lines = block.split("\n")
            var payload = ""
            for (var i = 0; i < lines.length; i++) {
                if (lines[i].indexOf("data:") === 0)
                    payload += lines[i].slice(5).trim()
            }
            if (payload === "")
                continue
            if (payload === "[DONE]")
                continue

            try {
                var obj = JSON.parse(payload)
                var delta = obj.choices && obj.choices[0] && obj.choices[0].delta ? obj.choices[0].delta : null
                var token = ""
                if (delta && typeof delta.content === "string") {
                    token = delta.content
                } else if (delta && delta.content && delta.content.length) {
                    for (var j = 0; j < delta.content.length; j++) {
                        var part = delta.content[j]
                        if (part && part.text)
                            token += part.text
                    }
                }

                if (token !== "") {
                    ensureStreamingAssistantMessage()
                    root.chatModel[root.streamingAssistantIndex].content += token
                    root.chatModel = root.chatModel
                    maybeAutoScroll()
                }
            } catch (e) {
                // ignore non-JSON keepalive chunks
            }
        }
    }

    function finishStreamingSuccess() {
        root.isLoading = false
        root.activeStreamXhr = null
        root.sseBuffer = ""
        root.sseOffset = 0
        root.compactState = "done"
        stateResetTimer.restart()

        if (root.streamingAssistantIndex >= 0) {
            var content = root.chatModel[root.streamingAssistantIndex].content || ""
            var first = content.split("\n")[0]
            root.lastAssistantPreview = first.length > 90 ? first.slice(0, 90) + "..." : first
            notifyBackgroundCompletion(content)
        }
        root.streamingAssistantIndex = -1
        root.chatModel = root.chatModel
        saveConversation()
    }

    function finishStreamingError(errMsg) {
        root.isLoading = false
        root.activeStreamXhr = null
        root.sseBuffer = ""
        root.sseOffset = 0
        root.streamingAssistantIndex = -1
        root.compactState = "error"
        stateResetTimer.restart()
        pushError(errMsg)
    }

    function stopStreaming() {
        if (root.activeStreamXhr) {
            try { root.activeStreamXhr.abort() } catch (e) {}
            root.activeStreamXhr = null
        }
        root.isLoading = false
        root.compactState = "done"
        stateResetTimer.restart()
        saveConversation()
    }

    function maybeAutoScroll() {
        if (!root.userScrolled && root.chatListViewRef)
            root.chatListViewRef.positionViewAtEnd()
    }

    function dispatchMessages(msgs) {
        if (startStreamingOpenAICompat(msgs))
            return

        root.isLoading = true
        root.compactState = "streaming"
        apiWorker.sendMessage({
            provider: root.currentProvider,
            messages: msgs,
            config: apiConfig()
        })
    }

    function sendMessage() {
        var text = root.inputFieldRef ? root.inputFieldRef.text.trim() : ""
        if (text === "" || root.isLoading)
            return

        if (root.attachmentText !== "") {
            text = quoteForPrompt(root.attachmentText) + text
            root.attachmentText = ""
            root.attachmentLabel = ""
        }

        root.chatModel.push({ role: "user", content: text, timestamp: nowIso(), model: "" })
        root.chatModel = root.chatModel
        if (root.inputFieldRef) root.inputFieldRef.text = ""
        maybeAutoScroll()
        saveConversation()

        if (!root.hasValidConfig) {
            pushError("Provider config is incomplete. Open Settings and check API keys / URL.")
            return
        }

        var msgs = buildMessages()
        ensureProviderKeyThenDispatch(msgs)
    }

    function regenerate() {
        if (root.isLoading)
            return

        if (root.chatModel.length > 0 && root.chatModel[root.chatModel.length - 1].role === "assistant") {
            root.chatModel.pop()
            root.chatModel = root.chatModel
        }
        if (root.chatModel.length === 0)
            return

        saveConversation()

        var msgs = buildMessages()
        ensureProviderKeyThenDispatch(msgs)
    }

    function clearChat() {
        root.chatModel = []
        root.lastAssistantPreview = "Open Kai Chat"
        saveConversation()
    }

    TextEdit { id: clipHelper; visible: false }

    WorkerScript {
        id: apiWorker
        source: "apiWorker.mjs"
        onMessage: function(msg) {
            root.isLoading = false
            if (msg.opencodeSessionId) {
                root.opencodeSessionId = msg.opencodeSessionId
                plasmoid.configuration.opencodeSessionId = msg.opencodeSessionId
            }
            if (msg.error) {
                root.compactState = "error"
                pushError(msg.error)
            } else {
                root.chatModel.push({
                    role: "assistant",
                    content: msg.content,
                    model: msg.model || "",
                    timestamp: nowIso()
                })
                root.chatModel = root.chatModel
                root.compactState = "done"
                stateResetTimer.restart()
                root.lastAssistantPreview = previewFromMessages(root.chatModel)
                notifyBackgroundCompletion(msg.content || "")
                maybeAutoScroll()
                saveConversation()
            }
        }
    }

    Component {
        id: compactRep
        Item {
            implicitWidth: Kirigami.Units.iconSizes.medium + Kirigami.Units.smallSpacing * 2
            implicitHeight: implicitWidth

            Kirigami.Icon {
                anchors.centerIn: parent
                width: Kirigami.Units.iconSizes.medium
                height: width
                source: "dialog-messages"
            }

            Rectangle {
                id: statusDot
                width: Kirigami.Units.smallSpacing * 1.8
                height: width
                radius: width / 2
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 1
                border.width: 1
                border.color: Kirigami.Theme.backgroundColor
                color: {
                    if (root.compactState === "streaming") return Kirigami.Theme.highlightColor
                    if (root.compactState === "done") return Kirigami.Theme.positiveTextColor
                    if (root.compactState === "error") return Kirigami.Theme.negativeTextColor
                    return Kirigami.Theme.disabledTextColor
                }

                SequentialAnimation on opacity {
                    running: root.compactState === "streaming"
                    loops: Animation.Infinite
                    NumberAnimation { from: 1.0; to: 0.3; duration: 450 }
                    NumberAnimation { from: 0.3; to: 1.0; duration: 450 }
                }
            }

            MouseArea {
                id: compactMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: plasmoid.expanded = !plasmoid.expanded
            }

            QQC2.ToolTip.visible: compactMouse.containsMouse
            QQC2.ToolTip.text: root.lastAssistantPreview
        }
    }

    Component {
        id: fullRep
        Item {
            id: fullRepItem
            implicitWidth: 480
            implicitHeight: 600
            Layout.minimumWidth: implicitWidth
            Layout.minimumHeight: implicitHeight
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight

            Component.onCompleted: {
                root.inputFieldRef = msgInput
                root.chatListViewRef = chatListView
                refreshSessions()
            }

            Rectangle {
                anchors.fill: parent
                color: Kirigami.Theme.backgroundColor
                radius: Kirigami.Units.smallSpacing

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    spacing: Kirigami.Units.smallSpacing

                RowLayout {
                    Layout.fillWidth: true

                    PC3.ComboBox {
                        id: sessionCombo
                        Layout.minimumWidth: 170
                        model: root.sessionsModel
                        textRole: "text"
                        valueRole: "value"
                        enabled: model.length > 0 && !root.isLoading
                        currentIndex: {
                            for (var i = 0; i < model.length; i++) {
                                if (model[i].value === root.currentSessionId) return i
                            }
                            return 0
                        }
                        onActivated: {
                            if (currentValue !== root.currentSessionId)
                                loadConversation(currentValue)
                        }
                    }

                    PC3.ToolButton {
                        icon.name: "list-add"
                        QQC2.ToolTip.text: "New Chat"
                        QQC2.ToolTip.visible: hovered
                        onClicked: startNewSession()
                    }

                    PC3.ComboBox {
                        id: providerCombo
                        Layout.fillWidth: true
                        model: [
                            { value: "openai",      text: "OpenAI" },
                            { value: "anthropic",   text: "Anthropic" },
                            { value: "gemini",      text: "Google Gemini" },
                            { value: "mistral",     text: "Mistral AI" },
                            { value: "grok",        text: "xAI Grok" },
                            { value: "deepseek",    text: "DeepSeek" },
                            { value: "nvidia",      text: "NVIDIA NIMs" },
                            { value: "cerebras",    text: "Cerebras" },
                            { value: "cloudflare",  text: "Cloudflare Workers AI" },
                            { value: "huggingface", text: "HuggingFace" },
                            { value: "openrouter",  text: "OpenRouter" },
                            { value: "litellm",     text: "LiteLLM (proxy)" },
                            { value: "local",       text: "Local" },
                            { value: "opencode",    text: "[BETA] OpenCode Bridge" }
                        ]
                        textRole: "text"
                        valueRole: "value"
                        currentIndex: {
                            for (var i = 0; i < model.length; i++) {
                                if (model[i].value === root.currentProvider) return i
                            }
                            return 0
                        }
                        onActivated: {
                            root.currentProvider = currentValue
                            plasmoid.configuration.provider = currentValue
                        }
                    }

                    PC3.ToolButton {
                        visible: root.currentProvider === "opencode"
                        icon.name: "view-refresh"
                        QQC2.ToolTip.text: "Reset OpenCode Session"
                        QQC2.ToolTip.visible: hovered
                        onClicked: {
                            root.opencodeSessionId = ""
                            plasmoid.configuration.opencodeSessionId = ""
                        }
                    }

                    PC3.ToolButton {
                        icon.name: "settings-configure"
                        QQC2.ToolTip.text: "Settings"
                        QQC2.ToolTip.visible: hovered
                        onClicked: plasmoid.action("configure").trigger()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: !root.hasValidConfig
                    color: Kirigami.Theme.negativeBackgroundColor
                    radius: Kirigami.Units.smallSpacing
                    height: warn.implicitHeight + Kirigami.Units.smallSpacing * 2
                    PC3.Label {
                        id: warn
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.largeSpacing
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        color: Kirigami.Theme.negativeTextColor
                        text: "Provider configuration is missing or incomplete. Open Settings to update API endpoint and key."
                    }
                }

                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                    ListView {
                        id: chatListView
                        model: root.chatModel
                        spacing: Kirigami.Units.smallSpacing
                        onMovementStarted: root.userScrolled = true
                        onMovementEnded: {
                            var nearBottom = (contentY + height) >= (contentHeight - Kirigami.Units.gridUnit)
                            if (nearBottom)
                                root.userScrolled = false
                        }

                        delegate: Rectangle {
                            width: chatListView.width
                            height: bubble.implicitHeight + Kirigami.Units.smallSpacing * 2
                            radius: Kirigami.Units.smallSpacing
                            color: {
                                if (modelData.role === "user") {
                                    return Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                   Kirigami.Theme.highlightColor.g,
                                                   Kirigami.Theme.highlightColor.b,
                                                   0.15)
                                }
                                if (modelData.role === "error")
                                    return Kirigami.Theme.negativeBackgroundColor
                                if (modelData.role === "system")
                                    return Qt.rgba(Kirigami.Theme.textColor.r,
                                                   Kirigami.Theme.textColor.g,
                                                   Kirigami.Theme.textColor.b,
                                                   0.06)
                                return Kirigami.Theme.alternateBackgroundColor
                            }

                            Column {
                                id: bubble
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing / 2

                                Row {
                                    spacing: Kirigami.Units.smallSpacing
                                    PC3.Label {
                                        text: modelData.role === "user" ? "You" : (modelData.role === "assistant" ? "AI" : (modelData.role === "system" ? "CLI" : "Error"))
                                        font.bold: true
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    }
                                    PC3.Label {
                                        visible: !!modelData.timestamp
                                        text: "- " + (modelData.timestamp || "")
                                        opacity: 0.55
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                                    }
                                }

                                PC3.Label {
                                    width: bubble.width
                                    wrapMode: Text.Wrap
                                    textFormat: Text.MarkdownText
                                    text: modelData.content || ""
                                    color: modelData.role === "error"
                                           ? Kirigami.Theme.negativeTextColor
                                           : Kirigami.Theme.textColor
                                    onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                                }

                                Row {
                                    visible: modelData.role === "assistant"
                                    spacing: Kirigami.Units.smallSpacing
                                    PC3.ToolButton {
                                        icon.name: "edit-copy"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: "Copy"
                                        onClicked: {
                                            writeToClipboard(modelData.content || "")
                                        }
                                    }
                                    PC3.ToolButton {
                                        icon.name: "view-refresh"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: "Regenerate"
                                        onClicked: regenerate()
                                    }
                                    PC3.ToolButton {
                                        icon.name: "edit-delete"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: "Delete message"
                                        onClicked: {
                                            root.chatModel.splice(index, 1)
                                            root.chatModel = root.chatModel
                                            saveConversation()
                                        }
                                    }
                                    PC3.ToolButton {
                                        visible: plasmoid.configuration.enableOpencodeBridge
                                              || plasmoid.configuration.enableAiderBridge
                                              || plasmoid.configuration.enableClaudeCodeBridge
                                        icon.name: "utilities-terminal"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: "Send to coding CLI"
                                        onClicked: cliMenu.open()

                                        PC3.Menu {
                                            id: cliMenu
                                            PC3.MenuItem {
                                                visible: plasmoid.configuration.enableOpencodeBridge
                                                text: "Opencode"
                                                onTriggered: runCli(plasmoid.configuration.opencodePath, ["-p", modelData.content || ""])
                                            }
                                            PC3.MenuItem {
                                                visible: plasmoid.configuration.enableAiderBridge
                                                text: "Aider"
                                                onTriggered: runCli(plasmoid.configuration.aiderPath, ["--message", modelData.content || ""])
                                            }
                                            PC3.MenuItem {
                                                visible: plasmoid.configuration.enableClaudeCodeBridge
                                                text: "Claude"
                                                onTriggered: runCli(plasmoid.configuration.claudeCodePath, ["-p", modelData.content || ""])
                                            }
                                        }
                                    }
                                }

                                Row {
                                    visible: modelData.role === "assistant" && extractCodeBlocks(modelData.content || "").length > 0
                                    spacing: Kirigami.Units.smallSpacing
                                    Repeater {
                                        model: extractCodeBlocks(modelData.content || "")
                                        delegate: PC3.ToolButton {
                                            icon.name: "edit-copy"
                                            text: "Copy code " + (index + 1)
                                            onClicked: writeToClipboard(modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.isLoading
                    PC3.BusyIndicator {
                        running: root.isLoading
                        width: Kirigami.Units.iconSizes.small
                        height: width
                    }
                    PC3.Label { text: "Streaming response..."; opacity: 0.72 }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PC3.ToolButton {
                        icon.name: "edit-paste"
                        display: PC3.AbstractButton.IconOnly
                        QQC2.ToolTip.text: "Use clipboard text"
                        QQC2.ToolTip.visible: hovered
                        enabled: !root.isLoading
                        onClicked: requestClipboard(false)
                    }

                    PC3.ToolButton {
                        icon.name: "selection-mode"
                        display: PC3.AbstractButton.IconOnly
                        QQC2.ToolTip.text: "Use selected text"
                        QQC2.ToolTip.visible: hovered
                        enabled: !root.isLoading
                        onClicked: requestClipboard(true)
                    }

                    QQC2.TextArea {
                        id: msgInput
                        Layout.fillWidth: true
                        enabled: !root.isLoading
                        wrapMode: Text.WordWrap
                        placeholderText: "Type message. Enter sends, Shift+Enter inserts newline"
                        Keys.onPressed: function(event) {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                    && !(event.modifiers & Qt.ShiftModifier)) {
                                event.accepted = true
                                sendMessage()
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing
                        PC3.Button {
                            icon.name: root.isLoading ? "process-stop" : "document-send"
                            text: root.isLoading ? "Stop" : "Send"
                            enabled: root.isLoading || (msgInput.text.trim() !== "" && root.hasValidConfig)
                            onClicked: {
                                if (root.isLoading)
                                    stopStreaming()
                                else
                                    sendMessage()
                            }
                        }
                        PC3.ToolButton {
                            icon.name: "edit-clear-history"
                            display: PC3.AbstractButton.IconOnly
                            QQC2.ToolTip.text: "Clear current chat"
                            QQC2.ToolTip.visible: hovered
                            enabled: !root.isLoading
                            onClicked: clearChat()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    visible: root.attachmentLabel !== ""
                    radius: Kirigami.Units.smallSpacing
                    color: Kirigami.Theme.alternateBackgroundColor
                    height: attachLabel.implicitHeight + Kirigami.Units.smallSpacing * 2

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing
                        spacing: Kirigami.Units.smallSpacing
                        PC3.Label {
                            id: attachLabel
                            Layout.fillWidth: true
                            text: root.attachmentLabel
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                        PC3.ToolButton {
                            icon.name: "window-close"
                            display: PC3.AbstractButton.IconOnly
                            onClicked: {
                                root.attachmentText = ""
                                root.attachmentLabel = ""
                            }
                        }
                    }
                }
            }

            Component.onDestruction: {
                root.inputFieldRef = null
                root.chatListViewRef = null
            }
        }
    }
}
}
