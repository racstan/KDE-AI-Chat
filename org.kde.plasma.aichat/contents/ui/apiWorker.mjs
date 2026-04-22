import QtQuick

WorkerScript {
    onMessage: {
        var provider = messageObject.provider
        var messages = messageObject.messages
        var config = messageObject.config

        if (provider === "openai" || provider === "local") {
            callOpenAICompatible(config, messages, provider)
        } else if (provider === "anthropic") {
            callAnthropic(config, messages)
        }
    }

    function callOpenAICompatible(config, messages, provider) {
        var apiKey = provider === "openai" ? config.openaiApiKey : ""
        var baseUrl = provider === "openai" ? config.openaiBaseUrl : config.localBaseUrl
        var model = provider === "openai" ? config.openaiModel : config.localModel

        var xhr = new XMLHttpRequest()
        var url = baseUrl + "/chat/completions"

        xhr.open("POST", url, true)
        xhr.setRequestHeader("Content-Type", "application/json")
        if (apiKey) {
            xhr.setRequestHeader("Authorization", "Bearer " + apiKey)
        }

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText)
                        var content = response.choices[0].message.content
                        WorkerScript.sendMessage({
                            content: content,
                            model: model,
                            error: null
                        })
                    } catch (e) {
                        WorkerScript.sendMessage({
                            content: "",
                            error: "Failed to parse response: " + e
                        })
                    }
                } else {
                    try {
                        var errorResponse = JSON.parse(xhr.responseText)
                        var errorMsg = errorResponse.error?.message || xhr.statusText
                        WorkerScript.sendMessage({
                            content: "",
                            error: "API Error (" + xhr.status + "): " + errorMsg
                        })
                    } catch (e) {
                        WorkerScript.sendMessage({
                            content: "",
                            error: "HTTP Error " + xhr.status + ": " + xhr.statusText
                        })
                    }
                }
            }
        }

        xhr.onerror = function() {
            WorkerScript.sendMessage({
                content: "",
                error: "Network error. Check your connection and endpoint configuration."
            })
        }

        var requestBody = {
            model: model,
            messages: messages
        }

        xhr.send(JSON.stringify(requestBody))
    }

    function callAnthropic(config, messages) {
        var apiKey = config.anthropicApiKey
        var model = config.anthropicModel

        // Convert messages to Anthropic format
        var anthropicMessages = []
        var systemContent = ""

        for (var i = 0; i < messages.length; i++) {
            if (messages[i].role === "system") {
                systemContent = messages[i].content
            } else {
                anthropicMessages.push({
                    role: messages[i].role,
                    content: messages[i].content
                })
            }
        }

        var xhr = new XMLHttpRequest()
        xhr.open("POST", "https://api.anthropic.com/v1/messages", true)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("x-api-key", apiKey)
        xhr.setRequestHeader("anthropic-version", "2023-06-01")

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var response = JSON.parse(xhr.responseText)
                        var content = ""
                        if (response.content && response.content.length > 0) {
                            content = response.content[0].text
                        }
                        WorkerScript.sendMessage({
                            content: content,
                            model: model,
                            error: null
                        })
                    } catch (e) {
                        WorkerScript.sendMessage({
                            content: "",
                            error: "Failed to parse response: " + e
                        })
                    }
                } else {
                    try {
                        var errorResponse = JSON.parse(xhr.responseText)
                        var errorMsg = errorResponse.error?.message || xhr.statusText
                        WorkerScript.sendMessage({
                            content: "",
                            error: "API Error (" + xhr.status + "): " + errorMsg
                        })
                    } catch (e) {
                        WorkerScript.sendMessage({
                            content: "",
                            error: "HTTP Error " + xhr.status + ": " + xhr.statusText
                        })
                    }
                }
            }
        }

        xhr.onerror = function() {
            WorkerScript.sendMessage({
                content: "",
                error: "Network error. Check your connection and API key."
            })
        }

        var requestBody = {
            model: model,
            max_tokens: 4096,
            messages: anthropicMessages
        }

        if (systemContent) {
            requestBody.system = systemContent
        }

        xhr.send(JSON.stringify(requestBody))
    }
}
