import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

    property var sessions: []
    property string currentSessionId: ""
    property string currentSessionTitle: ""
    property var messages: []

    property bool historyOnlyMode: false
    property bool loading: false
    property var activeXhr: null
    property var inputRef: null
    property var listRef: null

    property int editingMessageIndex: -1
    property string editingDraft: ""

    property string editingSessionId: ""
    property string editingSessionDraft: ""

    property bool openCodeMode: plasmoid.configuration.useOpenCode

    Component.onCompleted: loadSessions()

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height) * 0.8
            height: width
            source: "dialog-messages"
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: 420
        Layout.minimumHeight: 520
        Layout.preferredWidth: 680
        Layout.preferredHeight: 640

        Component.onCompleted: {
            root.inputRef = msgInput
            root.listRef = msgList
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true

                PC3.ToolButton {
                    icon.name: root.historyOnlyMode ? "go-previous-symbolic" : "view-list-icons"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: root.historyOnlyMode ? "Back to chat" : "Expand history"
                    onClicked: root.historyOnlyMode = !root.historyOnlyMode
                }

                Item { Layout.fillWidth: true }

                PC3.Label {
                    text: root.historyOnlyMode ? "Chat History" : (root.currentSessionTitle || "New Chat")
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Item { Layout.fillWidth: true }

                PC3.ToolButton {
                    icon.name: "list-add"
                    QQC2.ToolTip.visible: hovered
                    QQC2.ToolTip.text: "New chat"
                    enabled: !root.loading
                    onClicked: root.createSession(true)
                }
            }

            Rectangle {
                visible: root.historyOnlyMode
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 6
                color: Kirigami.Theme.alternateBackgroundColor

                QQC2.ScrollView {
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing
                    clip: true
                    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                    ListView {
                        id: historyList
                        model: root.sessions
                        spacing: Kirigami.Units.smallSpacing / 2

                        delegate: Rectangle {
                            required property var modelData
                            width: historyList.width
                            height: historyContent.implicitHeight + Kirigami.Units.smallSpacing * 2
                            radius: 6
                            color: modelData.value === root.currentSessionId
                                ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                          Kirigami.Theme.highlightColor.g,
                                          Kirigami.Theme.highlightColor.b,
                                          0.2)
                                : "transparent"

                            Column {
                                id: historyContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing / 2

                                Row {
                                    width: parent.width
                                    spacing: Kirigami.Units.smallSpacing / 2

                                    QQC2.TextField {
                                        visible: root.editingSessionId === modelData.value
                                        width: parent.width - renameBtn.width - deleteBtn.width - Kirigami.Units.smallSpacing * 2
                                        text: root.editingSessionDraft
                                        onTextChanged: root.editingSessionDraft = text
                                        onAccepted: root.saveSessionRename(modelData.value)
                                    }

                                    PC3.Label {
                                        visible: root.editingSessionId !== modelData.value
                                        width: parent.width - renameBtn.width - deleteBtn.width - Kirigami.Units.smallSpacing * 2
                                        elide: Text.ElideRight
                                        text: modelData.text || "New Chat"
                                    }

                                    PC3.ToolButton {
                                        id: renameBtn
                                        icon.name: root.editingSessionId === modelData.value ? "dialog-ok-apply" : "document-edit"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: root.editingSessionId === modelData.value ? "Save title" : "Rename chat"
                                        onClicked: {
                                            if (root.editingSessionId === modelData.value)
                                                root.saveSessionRename(modelData.value)
                                            else
                                                root.startSessionRename(modelData.value)
                                        }
                                    }

                                    PC3.ToolButton {
                                        id: deleteBtn
                                        icon.name: root.editingSessionId === modelData.value ? "dialog-cancel" : "edit-delete"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.visible: hovered
                                        QQC2.ToolTip.text: root.editingSessionId === modelData.value ? "Cancel rename" : "Delete chat"
                                        onClicked: {
                                            if (root.editingSessionId === modelData.value)
                                                root.cancelSessionRename()
                                            else
                                                root.deleteSession(modelData.value)
                                        }
                                    }
                                }

                                PC3.Label {
                                    opacity: 0.7
                                    text: "Updated " + root.formatDateTime(modelData.updatedAt || modelData.createdAt || Date.now())
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton
                                onClicked: {
                                    root.switchSession(modelData.value)
                                    root.historyOnlyMode = false
                                }
                                z: -1
                            }
                        }
                    }
                }
            }

            Item {
                visible: !root.historyOnlyMode
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                        ListView {
                            id: msgList
                            model: root.messages
                            spacing: Kirigami.Units.smallSpacing

                            delegate: Item {
                                width: msgList.width
                                height: bubble.implicitHeight

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Kirigami.Units.smallSpacing
                                    anchors.rightMargin: Kirigami.Units.smallSpacing

                                    Item {
                                        Layout.fillWidth: modelData.role !== "user"
                                        visible: modelData.role !== "user"
                                    }

                                    Rectangle {
                                        id: bubble
                                        Layout.maximumWidth: msgList.width * 0.78
                                        radius: 8
                                        color: modelData.role === "user"
                                            ? Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                      Kirigami.Theme.highlightColor.g,
                                                      Kirigami.Theme.highlightColor.b,
                                                      0.20)
                                            : modelData.role === "error"
                                              ? Kirigami.Theme.negativeBackgroundColor
                                              : Kirigami.Theme.alternateBackgroundColor
                                        border.width: 1
                                        border.color: Qt.rgba(Kirigami.Theme.textColor.r,
                                                              Kirigami.Theme.textColor.g,
                                                              Kirigami.Theme.textColor.b,
                                                              0.12)

                                        Column {
                                            anchors.fill: parent
                                            anchors.margins: Kirigami.Units.smallSpacing
                                            spacing: Kirigami.Units.smallSpacing / 2

                                            Row {
                                                spacing: Kirigami.Units.smallSpacing

                                                PC3.Label {
                                                    text: modelData.role === "user" ? "You" : (modelData.role === "error" ? "Error" : "AI")
                                                    font.bold: true
                                                }

                                                PC3.Label {
                                                    text: modelData.time || ""
                                                    opacity: 0.7
                                                    visible: text !== ""
                                                }

                                                PC3.Label {
                                                    text: modelData.role === "assistant" && modelData.model ? ("(" + modelData.model + ")") : ""
                                                    opacity: 0.6
                                                    visible: text !== ""
                                                }
                                            }

                                            Loader {
                                                active: root.editingMessageIndex === index
                                                sourceComponent: QQC2.TextArea {
                                                    text: root.editingDraft
                                                    wrapMode: Text.WordWrap
                                                    onTextChanged: root.editingDraft = text
                                                }
                                            }

                                            PC3.Label {
                                                visible: root.editingMessageIndex !== index
                                                width: bubble.width - Kirigami.Units.smallSpacing * 2
                                                wrapMode: Text.Wrap
                                                textFormat: Text.MarkdownText
                                                text: modelData.content
                                                color: modelData.role === "error"
                                                    ? Kirigami.Theme.negativeTextColor
                                                    : Kirigami.Theme.textColor
                                                onLinkActivated: function(link) { Qt.openUrlExternally(link) }
                                            }

                                            Row {
                                                spacing: Kirigami.Units.smallSpacing

                                                PC3.ToolButton {
                                                    visible: root.editingMessageIndex !== index
                                                    icon.name: "document-edit"
                                                    display: PC3.AbstractButton.IconOnly
                                                    QQC2.ToolTip.visible: hovered
                                                    QQC2.ToolTip.text: "Edit message"
                                                    onClicked: {
                                                        root.editingMessageIndex = index
                                                        root.editingDraft = modelData.content
                                                    }
                                                }

                                                PC3.ToolButton {
                                                    visible: root.editingMessageIndex === index
                                                    icon.name: "dialog-ok-apply"
                                                    display: PC3.AbstractButton.IconOnly
                                                    QQC2.ToolTip.visible: hovered
                                                    QQC2.ToolTip.text: "Save edit"
                                                    onClicked: root.saveEditedMessage()
                                                }

                                                PC3.ToolButton {
                                                    visible: root.editingMessageIndex === index
                                                    icon.name: "dialog-cancel"
                                                    display: PC3.AbstractButton.IconOnly
                                                    QQC2.ToolTip.visible: hovered
                                                    QQC2.ToolTip.text: "Cancel edit"
                                                    onClicked: {
                                                        root.editingMessageIndex = -1
                                                        root.editingDraft = ""
                                                    }
                                                }

                                                PC3.ToolButton {
                                                    icon.name: "edit-delete"
                                                    display: PC3.AbstractButton.IconOnly
                                                    QQC2.ToolTip.visible: hovered
                                                    QQC2.ToolTip.text: "Delete message"
                                                    onClicked: root.deleteMessage(index)
                                                }
                                            }
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: modelData.role === "user"
                                        visible: modelData.role === "user"
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        visible: root.loading
                        PC3.BusyIndicator { running: root.loading; width: 20; height: 20 }
                        PC3.Label { text: "Generating..."; opacity: 0.8 }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignBottom
                        spacing: Kirigami.Units.smallSpacing

                        QQC2.TextArea {
                            id: msgInput
                            Layout.fillWidth: true
                            Layout.minimumHeight: Kirigami.Units.gridUnit * 3
                            Layout.maximumHeight: Kirigami.Units.gridUnit * 7
                            Layout.preferredHeight: Math.min(Layout.maximumHeight, Math.max(Layout.minimumHeight, contentHeight + topPadding + bottomPadding))
                            wrapMode: Text.WordWrap
                            clip: true
                            enabled: !root.loading
                            placeholderText: "Type message (Enter sends, Shift+Enter newline)"

                            Keys.onPressed: function(event) {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                        && !(event.modifiers & Qt.ShiftModifier)) {
                                    event.accepted = true
                                    root.sendMessage()
                                }
                            }
                        }

                        PC3.Button {
                            icon.name: root.loading ? "process-stop" : "document-send"
                            text: root.loading ? "Stop" : "Send"
                            Layout.minimumWidth: Kirigami.Units.gridUnit * 5
                            Layout.preferredHeight: Kirigami.Units.gridUnit * 3
                            Layout.alignment: Qt.AlignBottom
                            enabled: root.loading || msgInput.text.trim() !== ""
                            onClicked: root.loading ? root.stopStreaming() : root.sendMessage()
                        }
                    }
                }
            }
        }
    }

    function nowTime() {
        return new Date().toLocaleTimeString()
    }

    function formatDateTime(ts) {
        return new Date(ts).toLocaleString(undefined, {
            year: "numeric",
            month: "short",
            day: "2-digit",
            hour: "2-digit",
            minute: "2-digit"
        })
    }

    function makeSessionId() {
        return "s-" + Date.now() + "-" + Math.floor(Math.random() * 100000)
    }

    function parseSessions() {
        var raw = plasmoid.configuration.chatSessionsJson || "[]"
        try {
            var arr = JSON.parse(raw)
            if (Array.isArray(arr)) {
                for (var i = 0; i < arr.length; i++) {
                    if (!arr[i].messages)
                        arr[i].messages = []
                    if (!arr[i].updatedAt)
                        arr[i].updatedAt = arr[i].createdAt || Date.now()
                }
                return arr
            }
            return []
        } catch (e) {
            return []
        }
    }

    function persistSessions() {
        plasmoid.configuration.chatSessionsJson = JSON.stringify(root.sessions)
        plasmoid.configuration.lastSessionId = root.currentSessionId
    }

    function sortSessionsByUpdated() {
        var copy = root.sessions.slice()
        copy.sort(function(a, b) {
            return (b.updatedAt || b.createdAt || 0) - (a.updatedAt || a.createdAt || 0)
        })
        root.sessions = copy
    }

    function sessionIndexById(sessionId) {
        for (var i = 0; i < root.sessions.length; i++) {
            if (root.sessions[i].value === sessionId)
                return i
        }
        return -1
    }

    function createSession(switchToNew) {
        var s = {
            value: makeSessionId(),
            text: "New Chat",
            createdAt: Date.now(),
            updatedAt: Date.now(),
            messages: []
        }
        root.sessions = [s].concat(root.sessions)

        if (switchToNew) {
            root.currentSessionId = s.value
            root.currentSessionTitle = s.text
            root.messages = []
            root.editingMessageIndex = -1
            root.editingDraft = ""
            root.editingSessionId = ""
            root.editingSessionDraft = ""
            root.historyOnlyMode = false
        }
        persistSessions()
    }

    function loadSessions() {
        root.sessions = parseSessions()
        if (root.sessions.length === 0)
            createSession(true)

        var preferred = plasmoid.configuration.lastSessionId || ""
        var idx = sessionIndexById(preferred)
        if (idx < 0)
            idx = 0

        root.currentSessionId = root.sessions[idx].value
        root.currentSessionTitle = root.sessions[idx].text
        root.messages = root.sessions[idx].messages || []
        sortSessionsByUpdated()
    }

    function saveCurrentSessionState() {
        var idx = sessionIndexById(root.currentSessionId)
        if (idx < 0)
            return

        var updated = root.sessions.slice()
        var s = Object.assign({}, updated[idx])
        s.text = root.currentSessionTitle || "New Chat"
        s.updatedAt = Date.now()
        s.messages = root.messages
        updated[idx] = s
        root.sessions = updated
        sortSessionsByUpdated()
        persistSessions()
    }

    function switchSession(sessionId) {
        if (!sessionId || sessionId === root.currentSessionId)
            return

        saveCurrentSessionState()

        var idx = sessionIndexById(sessionId)
        if (idx < 0)
            return

        root.currentSessionId = root.sessions[idx].value
        root.currentSessionTitle = root.sessions[idx].text
        root.messages = root.sessions[idx].messages || []
        root.editingMessageIndex = -1
        root.editingDraft = ""
        root.editingSessionId = ""
        root.editingSessionDraft = ""
        persistSessions()
        scrollToBottom()
    }

    function startSessionRename(sessionId) {
        var idx = sessionIndexById(sessionId)
        if (idx < 0)
            return
        root.editingSessionId = sessionId
        root.editingSessionDraft = root.sessions[idx].text || ""
    }

    function cancelSessionRename() {
        root.editingSessionId = ""
        root.editingSessionDraft = ""
    }

    function saveSessionRename(sessionId) {
        var idx = sessionIndexById(sessionId)
        if (idx < 0)
            return

        var title = (root.editingSessionDraft || "").trim()
        if (title === "")
            title = "New Chat"

        var updated = root.sessions.slice()
        var s = Object.assign({}, updated[idx])
        s.text = title
        s.updatedAt = Date.now()
        updated[idx] = s
        root.sessions = updated

        if (root.currentSessionId === sessionId)
            root.currentSessionTitle = title

        sortSessionsByUpdated()
        persistSessions()
        cancelSessionRename()
    }

    function deleteSession(sessionId) {
        if (root.sessions.length <= 1)
            return

        var idx = sessionIndexById(sessionId)
        if (idx < 0)
            return

        var updated = root.sessions.slice()
        updated.splice(idx, 1)
        root.sessions = updated

        if (root.currentSessionId === sessionId) {
            var next = root.sessions[0]
            root.currentSessionId = next.value
            root.currentSessionTitle = next.text
            root.messages = next.messages || []
        }

        cancelSessionRename()
        persistSessions()
    }

    function deleteMessage(index) {
        var copy = root.messages.slice()
        if (index < 0 || index >= copy.length)
            return
        copy.splice(index, 1)
        root.messages = copy
        root.editingMessageIndex = -1
        root.editingDraft = ""
        saveCurrentSessionState()
    }

    function saveEditedMessage() {
        var i = root.editingMessageIndex
        if (i < 0 || i >= root.messages.length)
            return

        var copy = root.messages.slice()
        var item = Object.assign({}, copy[i])
        item.content = root.editingDraft
        copy[i] = item
        root.messages = copy
        root.editingMessageIndex = -1
        root.editingDraft = ""
        saveCurrentSessionState()
    }

    function scrollToBottom() {
        if (root.listRef)
            root.listRef.positionViewAtEnd()
    }

    function pushErrorMessage(text) {
        root.messages = root.messages.concat([{ role: "error", content: text, time: nowTime(), model: "" }])
        scrollToBottom()
        saveCurrentSessionState()
    }

    function validateProviderConfig(cfg) {
        if (!cfg)
            return "Provider configuration missing."
        if (!cfg.baseUrl && cfg.type !== "anthropic")
            return "Provider base URL is missing."
        if (!cfg.model)
            return "Model is missing for the selected provider."
        if (cfg.type === "anthropic" && !cfg.apiKey)
            return "Anthropic API key missing in settings."
        if (cfg.type !== "anthropic" && !cfg.allowEmptyKey && !cfg.apiKey)
            return "API key missing for the selected provider."
        return ""
    }

    function sendMessage() {
        var text = (root.inputRef ? root.inputRef.text : "").trim()
        if (text === "" || root.loading)
            return

        root.messages = root.messages.concat([{ role: "user", content: text, time: nowTime(), model: "" }])
        if (root.inputRef)
            root.inputRef.text = ""

        saveCurrentSessionState()
        scrollToBottom()

        if (root.openCodeMode) {
            doOpenAICompatRequest(
                (plasmoid.configuration.openCodeUrl || "http://127.0.0.1:4096/v1"),
                (plasmoid.configuration.openCodeApiKey || ""),
                (plasmoid.configuration.openCodeModel || "gpt-4o-mini"),
                null,
                (plasmoid.configuration.openCodeModel || "gpt-4o-mini")
            )
            return
        }

        var provider = plasmoid.configuration.provider || "openai"
        var providerCfg = getProviderConfig(provider)
        var validationError = validateProviderConfig(providerCfg)
        if (validationError !== "") {
            pushErrorMessage(validationError)
            return
        }

        if (providerCfg.type === "anthropic") {
            doAnthropicRequest(providerCfg.apiKey, providerCfg.model)
        } else {
            doOpenAICompatRequest(
                providerCfg.baseUrl,
                providerCfg.apiKey,
                providerCfg.model,
                providerCfg.headers,
                providerCfg.model
            )
        }
    }

    function getProviderConfig(provider) {
        if (provider === "anthropic") {
            return {
                type: "anthropic",
                apiKey: plasmoid.configuration.anthropicApiKey || "",
                model: plasmoid.configuration.anthropicModel || "claude-3-5-sonnet-latest",
                allowEmptyKey: false
            }
        }
        if (provider === "local") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.localBaseUrl || "http://localhost:11434/v1",
                apiKey: "",
                model: plasmoid.configuration.localModel || "llama3.2",
                headers: null,
                allowEmptyKey: true
            }
        }
        if (provider === "groq") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.groqBaseUrl || "https://api.groq.com/openai/v1",
                apiKey: plasmoid.configuration.groqApiKey || "",
                model: plasmoid.configuration.groqModel || "llama-3.3-70b-versatile",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "openrouter") {
            var headers = {}
            var referer = plasmoid.configuration.openRouterReferer || ""
            var title = plasmoid.configuration.openRouterTitle || "Kai Chat"
            if (referer)
                headers["HTTP-Referer"] = referer
            if (title)
                headers["X-OpenRouter-Title"] = title
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.openRouterBaseUrl || "https://openrouter.ai/api/v1",
                apiKey: plasmoid.configuration.openRouterApiKey || "",
                model: plasmoid.configuration.openRouterModel || "openai/gpt-4o-mini",
                headers: headers,
                allowEmptyKey: false
            }
        }
        if (provider === "mistral") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.mistralBaseUrl || "https://api.mistral.ai/v1",
                apiKey: plasmoid.configuration.mistralApiKey || "",
                model: plasmoid.configuration.mistralModel || "mistral-small-latest",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "cloudflare") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.cloudflareBaseUrl || "https://api.cloudflare.com/client/v4/accounts/YOUR_ACCOUNT_ID/ai/v1",
                apiKey: plasmoid.configuration.cloudflareApiKey || "",
                model: plasmoid.configuration.cloudflareModel || "@cf/meta/llama-3.1-8b-instruct",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "nvidia") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.nvidiaBaseUrl || "https://integrate.api.nvidia.com/v1",
                apiKey: plasmoid.configuration.nvidiaApiKey || "",
                model: plasmoid.configuration.nvidiaModel || "meta/llama-3.1-70b-instruct",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "huggingface") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.huggingFaceBaseUrl || "https://router.huggingface.co/v1",
                apiKey: plasmoid.configuration.huggingFaceApiKey || "",
                model: plasmoid.configuration.huggingFaceModel || "openai/gpt-oss-120b:groq",
                headers: null,
                allowEmptyKey: false
            }
        }
        if (provider === "xai") {
            return {
                type: "openai-compat",
                baseUrl: plasmoid.configuration.xaiBaseUrl || "https://api.x.ai/v1",
                apiKey: plasmoid.configuration.xaiApiKey || "",
                model: plasmoid.configuration.xaiModel || "grok-2-latest",
                headers: null,
                allowEmptyKey: false
            }
        }
        return {
            type: "openai-compat",
            baseUrl: plasmoid.configuration.baseUrl || "https://api.openai.com/v1",
            apiKey: plasmoid.configuration.apiKey || "",
            model: plasmoid.configuration.model || "gpt-4o-mini",
            headers: null,
            allowEmptyKey: false
        }
    }

    function buildOpenAICompatPayload() {
        var sys = plasmoid.configuration.systemPrompt || "You are a helpful assistant."
        var arr = [{ role: "system", content: sys }]
        for (var i = 0; i < root.messages.length; i++) {
            var m = root.messages[i]
            if (m.role === "user" || m.role === "assistant")
                arr.push({ role: m.role, content: m.content })
        }
        return arr
    }

    function buildAnthropicPayload() {
        var arr = []
        for (var i = 0; i < root.messages.length; i++) {
            var m = root.messages[i]
            if (m.role === "user" || m.role === "assistant")
                arr.push({ role: m.role, content: m.content })
        }
        return arr
    }

    function doOpenAICompatRequest(baseUrl, apiKey, model, extraHeaders, modelLabel) {
        var url = (baseUrl || "").replace(/\/$/, "") + "/chat/completions"
        var xhr = new XMLHttpRequest()
        root.loading = true
        root.activeXhr = xhr

        var sseBuffer = ""
        var sseOffset = 0
        var assistantIdx = -1

        xhr.open("POST", url, true)
        xhr.setRequestHeader("Content-Type", "application/json")
        if (apiKey !== "")
            xhr.setRequestHeader("Authorization", "Bearer " + apiKey)
        if (extraHeaders) {
            for (var headerName in extraHeaders) {
                if (Object.prototype.hasOwnProperty.call(extraHeaders, headerName) && extraHeaders[headerName])
                    xhr.setRequestHeader(headerName, extraHeaders[headerName])
            }
        }

        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.LOADING || xhr.readyState === XMLHttpRequest.DONE) {
                var delta = xhr.responseText.slice(sseOffset)
                sseOffset = xhr.responseText.length
                sseBuffer += delta

                while (true) {
                    var split = sseBuffer.indexOf("\n\n")
                    if (split < 0)
                        break

                    var block = sseBuffer.slice(0, split)
                    sseBuffer = sseBuffer.slice(split + 2)

                    var lines = block.split("\n")
                    for (var i = 0; i < lines.length; i++) {
                        if (lines[i].indexOf("data:") !== 0)
                            continue

                        var payload = lines[i].slice(5).trim()
                        if (payload === "" || payload === "[DONE]")
                            continue

                        try {
                            var obj = JSON.parse(payload)
                            var token = (obj.choices && obj.choices[0]
                                        && obj.choices[0].delta
                                        && obj.choices[0].delta.content) || ""
                            if (token !== "") {
                                if (assistantIdx < 0) {
                                    root.messages = root.messages.concat([{ role: "assistant", content: token, time: nowTime(), model: modelLabel || model || "" }])
                                    assistantIdx = root.messages.length - 1
                                } else {
                                    var copy = root.messages.slice()
                                    var a = Object.assign({}, copy[assistantIdx])
                                    a.content = (a.content || "") + token
                                    copy[assistantIdx] = a
                                    root.messages = copy
                                }
                                scrollToBottom()
                            }
                        } catch (e) {
                        }
                    }
                }
            }

            if (xhr.readyState === XMLHttpRequest.DONE) {
                root.loading = false
                root.activeXhr = null

                if (xhr.status < 200 || xhr.status >= 300) {
                    var err = "HTTP " + xhr.status
                    try {
                        var eobj = JSON.parse(xhr.responseText)
                        if (eobj.error && eobj.error.message)
                            err = eobj.error.message
                    } catch (e2) {
                    }
                    pushErrorMessage(err)
                }

                saveCurrentSessionState()
            }
        }

        xhr.onerror = function() {
            root.loading = false
            root.activeXhr = null
            pushErrorMessage("Network error")
        }

        xhr.send(JSON.stringify({
            model: model,
            messages: buildOpenAICompatPayload(),
            stream: true
        }))
    }

    function doAnthropicRequest(apiKey, model) {
        if (!apiKey) {
            pushErrorMessage("Anthropic API key missing in settings.")
            return
        }

        var xhr = new XMLHttpRequest()
        root.loading = true
        root.activeXhr = xhr

        xhr.open("POST", "https://api.anthropic.com/v1/messages", true)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.setRequestHeader("x-api-key", apiKey)
        xhr.setRequestHeader("anthropic-version", "2023-06-01")

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return

            root.loading = false
            root.activeXhr = null

            if (xhr.status >= 200 && xhr.status < 300) {
                try {
                    var obj = JSON.parse(xhr.responseText)
                    var text = ""
                    if (obj.content && obj.content.length) {
                        for (var i = 0; i < obj.content.length; i++) {
                            if (obj.content[i].type === "text")
                                text += obj.content[i].text
                        }
                    }
                    root.messages = root.messages.concat([{ role: "assistant", content: text || "(empty response)", time: nowTime(), model: model || "" }])
                } catch (e) {
                    pushErrorMessage("Failed to parse Anthropic response")
                }
            } else {
                var err = "Anthropic HTTP " + xhr.status
                try {
                    var eobj = JSON.parse(xhr.responseText)
                    if (eobj.error && eobj.error.message)
                        err = eobj.error.message
                } catch (e2) {
                }
                pushErrorMessage(err)
            }

            scrollToBottom()
            saveCurrentSessionState()
        }

        xhr.onerror = function() {
            root.loading = false
            root.activeXhr = null
            pushErrorMessage("Network error")
        }

        xhr.send(JSON.stringify({
            model: model,
            max_tokens: 1024,
            system: plasmoid.configuration.systemPrompt || "You are a helpful assistant.",
            messages: buildAnthropicPayload()
        }))
    }

    function stopStreaming() {
        if (root.activeXhr) {
            try {
                root.activeXhr.abort()
            } catch (e) {
            }
            root.activeXhr = null
        }
        root.loading = false
        saveCurrentSessionState()
    }
}
