import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PE

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    fullRepresentation: fullRep
    compactRepresentation: compactRep

    property var chatModel: []
    property bool isLoading: false
    property string currentProvider: plasmoid.configuration.provider
    property var config: plasmoid.configuration

    property bool hasValidConfig: {
        if (currentProvider === "openai") return config.openaiApiKey !== ""
        if (currentProvider === "anthropic") return config.anthropicApiKey !== ""
        if (currentProvider === "local") return true
        return false
    }

    Component {
        id: compactRep
        Rectangle {
            width: Kirigami.Units.iconSizes.medium
            height: width
            color: "transparent"

            Kirigami.Icon {
                anchors.fill: parent
                source: "dialog-messages"
            }

            Rectangle {
                visible: root.chatModel.length > 0
                anchors.top: parent.top
                anchors.right: parent.right
                width: Kirigami.Units.smallSpacing * 2.5
                height: width
                radius: width / 2
                color: Kirigami.Theme.positiveBackgroundColor
            }
        }
    }

    Component {
        id: fullRep
        Rectangle {
            id: fullRepRect
            color: Kirigami.Theme.backgroundColor
            Layout.minimumWidth: 400
            Layout.minimumHeight: 500
            Layout.preferredWidth: 500
            Layout.preferredHeight: 640

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                // ── Header ──────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PC3.ComboBox {
                        id: providerCombo
                        Layout.fillWidth: true
                        model: [
                            { value: "openai",    text: "OpenAI" },
                            { value: "anthropic", text: "Anthropic" },
                            { value: "local",     text: "Local (Ollama / LM Studio)" }
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
                        icon.name: "settings-configure"
                        ToolTip.text: "Settings"
                        ToolTip.visible: hovered
                        onClicked: plasmoid.action("configure").trigger()
                    }
                }

                // ── Active bridge pills ──────────────────────────────────
                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    visible: config.enableOpencodeBridge || config.enableAiderBridge || config.enableClaudeCodeBridge

                    PC3.Label {
                        text: "Bridges:"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Repeater {
                        model: [
                            { enabled: config.enableOpencodeBridge,    name: "Opencode",    color: "#4CAF50" },
                            { enabled: config.enableAiderBridge,       name: "Aider",       color: "#2196F3" },
                            { enabled: config.enableClaudeCodeBridge,  name: "Claude Code", color: "#FF9800" }
                        ]
                        delegate: Rectangle {
                            visible: modelData.enabled
                            width: pillLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                            height: Kirigami.Units.gridUnit
                            radius: height / 2
                            color: modelData.color
                            opacity: 0.85
                            PC3.Label {
                                id: pillLabel
                                anchors.centerIn: parent
                                text: modelData.name
                                color: "white"
                                font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                            }
                        }
                    }
                }

                // ── Config warning ──────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: configWarning.implicitHeight + Kirigami.Units.smallSpacing * 2
                    visible: !root.hasValidConfig
                    color: Kirigami.Theme.negativeBackgroundColor
                    radius: Kirigami.Units.smallSpacing

                    PC3.Label {
                        id: configWarning
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.smallSpacing * 4
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        color: Kirigami.Theme.negativeTextColor
                        text: currentProvider === "openai"     ? "Set your OpenAI API key in Settings." :
                              currentProvider === "anthropic"  ? "Set your Anthropic API key in Settings." :
                                                                 "Local provider – make sure your server is running."
                    }
                }

                // ── Chat list ───────────────────────────────────────────
                ListView {
                    id: chatListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Kirigami.Units.smallSpacing
                    model: root.chatModel

                    delegate: Rectangle {
                        width: chatListView.width
                        height: msgCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: Kirigami.Units.smallSpacing
                        color: {
                            if (modelData.role === "user")      return Qt.rgba(Kirigami.Theme.highlightColor.r,
                                                                               Kirigami.Theme.highlightColor.g,
                                                                               Kirigami.Theme.highlightColor.b, 0.08)
                            if (modelData.role === "error")     return Kirigami.Theme.negativeBackgroundColor
                            return Kirigami.Theme.alternateBackgroundColor
                        }

                        Column {
                            id: msgCol
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Kirigami.Units.smallSpacing }
                            spacing: Kirigami.Units.smallSpacing / 2

                            // Role row
                            Row {
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Icon {
                                    width: Kirigami.Units.iconSizes.small; height: width
                                    source: modelData.role === "user"  ? "user-identity" :
                                            modelData.role === "error" ? "dialog-error"  : "dialog-messages"
                                }
                                PC3.Label {
                                    text: modelData.role === "user"  ? "You" :
                                          modelData.role === "error" ? "Error" : "AI"
                                    font.bold: true
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                }
                                PC3.Label {
                                    visible: modelData.model !== undefined && modelData.model !== ""
                                    text: "· " + (modelData.model || "")
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                                    opacity: 0.55
                                }
                            }

                            // Message body
                            PC3.Label {
                                width: msgCol.width
                                wrapMode: Text.Wrap
                                text: modelData.content
                                textFormat: Text.MarkdownText
                                onLinkActivated: link => Qt.openUrlExternally(link)
                                color: modelData.role === "error" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                            }

                            // Action row (assistant only)
                            Row {
                                visible: modelData.role === "assistant" && !root.isLoading
                                spacing: Kirigami.Units.smallSpacing

                                // Copy button
                                PC3.ToolButton {
                                    icon.name: "edit-copy"
                                    display: PC3.AbstractButton.IconOnly
                                    ToolTip.text: "Copy response"
                                    ToolTip.visible: hovered
                                    onClicked: {
                                        clipboardEdit.text = modelData.content
                                        clipboardEdit.selectAll()
                                        clipboardEdit.copy()
                                    }
                                }

                                // Send-to-CLI button + menu
                                PC3.ToolButton {
                                    visible: config.enableOpencodeBridge || config.enableAiderBridge || config.enableClaudeCodeBridge
                                    icon.name: "utilities-terminal"
                                    display: PC3.AbstractButton.IconOnly
                                    ToolTip.text: "Send to coding CLI"
                                    ToolTip.visible: hovered
                                    onClicked: cliMenu.open()

                                    PC3.Menu {
                                        id: cliMenu
                                        PC3.MenuItem {
                                            visible: config.enableOpencodeBridge
                                            text: "Send to Opencode"
                                            icon.name: "utilities-terminal"
                                            // opencode -p "prompt"  (non-interactive mode per opencode docs)
                                            onTriggered: bridgeToCli(config.opencodePath, ["-p", modelData.content])
                                        }
                                        PC3.MenuItem {
                                            visible: config.enableAiderBridge
                                            text: "Send to Aider"
                                            icon.name: "utilities-terminal"
                                            // aider --message "prompt"
                                            onTriggered: bridgeToCli(config.aiderPath, ["--message", modelData.content])
                                        }
                                        PC3.MenuItem {
                                            visible: config.enableClaudeCodeBridge
                                            text: "Send to Claude Code"
                                            icon.name: "utilities-terminal"
                                            // claude -p "prompt"
                                            onTriggered: bridgeToCli(config.claudeCodePath, ["-p", modelData.content])
                                        }
                                    }
                                }

                                // Retry button
                                PC3.ToolButton {
                                    visible: modelData.role === "assistant"
                                    icon.name: "view-refresh"
                                    display: PC3.AbstractButton.IconOnly
                                    ToolTip.text: "Regenerate"
                                    ToolTip.visible: hovered
                                    onClicked: regenerateLastMessage()
                                }
                            }
                        }
                    }

                    PC3.ScrollBar.vertical: PC3.ScrollBar { id: chatScrollBar }

                    function scrollToBottom() {
                        if (count > 0) positionViewAtEnd()
                    }
                }

                // ── CLI output log ──────────────────────────────────────
                Rectangle {
                    id: cliOutputBox
                    Layout.fillWidth: true
                    height: cliOutputLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                    visible: cliOutputLabel.text !== ""
                    color: "#1e1e2e"
                    radius: Kirigami.Units.smallSpacing

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Kirigami.Units.smallSpacing

                        PC3.Label {
                            id: cliOutputLabel
                            Layout.fillWidth: true
                            text: ""
                            color: "#a6e3a1"
                            font.family: "monospace"
                            font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                            wrapMode: Text.Wrap
                        }
                        PC3.ToolButton {
                            icon.name: "window-close"
                            display: PC3.AbstractButton.IconOnly
                            onClicked: cliOutputLabel.text = ""
                        }
                    }
                }

                // ── Thinking indicator ──────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.isLoading
                    spacing: Kirigami.Units.smallSpacing
                    PC3.BusyIndicator {
                        running: root.isLoading
                        width: Kirigami.Units.iconSizes.small; height: width
                    }
                    PC3.Label { text: "Thinking..."; opacity: 0.7 }
                }

                // ── Input area ──────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    // TextArea – Enter sends, Shift+Enter inserts newline
                    TextArea {
                        id: messageInput
                        Layout.fillWidth: true
                        placeholderText: "Message… (Enter to send, Shift+Enter for newline)"
                        wrapMode: Text.WordWrap
                        background: Rectangle {
                            color: Kirigami.Theme.backgroundColor
                            border.color: messageInput.activeFocus ? Kirigami.Theme.highlightColor : Kirigami.Theme.disabledTextColor
                            border.width: 1
                            radius: Kirigami.Units.smallSpacing
                        }
                        color: Kirigami.Theme.textColor
                        // Fix: TextArea has no onAccepted; intercept key here
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // let the default handler insert a newline
                                } else {
                                    event.accepted = true
                                    sendMessage()
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing

                        PC3.Button {
                            icon.name: "document-send"
                            ToolTip.text: "Send"
                            ToolTip.visible: hovered
                            enabled: !root.isLoading && messageInput.text.trim() !== "" && root.hasValidConfig
                            onClicked: sendMessage()
                        }

                        PC3.ToolButton {
                            icon.name: "edit-clear-history"
                            display: PC3.AbstractButton.IconOnly
                            ToolTip.text: "Clear chat"
                            ToolTip.visible: hovered
                            onClicked: clearChat()
                        }
                    }
                }
            }

            // Invisible clipboard helper
            TextEdit { id: clipboardEdit; visible: false }

            // ── API worker ──────────────────────────────────────────────
            WorkerScript {
                id: apiWorker
                source: "apiWorker.mjs"
                onMessage: {
                    root.isLoading = false
                    if (messageObject.error) {
                        root.chatModel.push({ role: "error", content: messageObject.error, model: "" })
                    } else {
                        root.chatModel.push({ role: "assistant", content: messageObject.content, model: messageObject.model || "" })
                        saveHistory()
                    }
                    root.chatModel = root.chatModel
                    chatListView.scrollToBottom()
                }
            }

            // ── Functions ───────────────────────────────────────────────
            function buildMessages() {
                var msgs = [{ role: "system", content: config.systemPrompt }]
                for (var i = 0; i < root.chatModel.length; i++) {
                    if (root.chatModel[i].role !== "error") {
                        msgs.push({ role: root.chatModel[i].role, content: root.chatModel[i].content })
                    }
                }
                return msgs
            }

            function sendMessage() {
                var text = messageInput.text.trim()
                if (text === "" || root.isLoading) return

                root.chatModel.push({ role: "user", content: text, model: "" })
                root.chatModel = root.chatModel
                messageInput.text = ""
                root.isLoading = true
                chatListView.scrollToBottom()

                apiWorker.sendMessage({
                    provider: root.currentProvider,
                    messages: buildMessages(),
                    config: {
                        openaiApiKey:    config.openaiApiKey,
                        openaiBaseUrl:   config.openaiBaseUrl,
                        openaiModel:     config.openaiModel,
                        anthropicApiKey: config.anthropicApiKey,
                        anthropicModel:  config.anthropicModel,
                        localBaseUrl:    config.localBaseUrl,
                        localModel:      config.localModel
                    }
                })
            }

            function regenerateLastMessage() {
                // Remove last assistant message and resend
                if (root.chatModel.length > 0 && root.chatModel[root.chatModel.length - 1].role === "assistant") {
                    root.chatModel.pop()
                    root.chatModel = root.chatModel
                }
                if (root.chatModel.length === 0) return
                root.isLoading = true
                apiWorker.sendMessage({
                    provider: root.currentProvider,
                    messages: buildMessages(),
                    config: {
                        openaiApiKey:    config.openaiApiKey,
                        openaiBaseUrl:   config.openaiBaseUrl,
                        openaiModel:     config.openaiModel,
                        anthropicApiKey: config.anthropicApiKey,
                        anthropicModel:  config.anthropicModel,
                        localBaseUrl:    config.localBaseUrl,
                        localModel:      config.localModel
                    }
                })
            }

            function clearChat() {
                root.chatModel = []
                plasmoid.configuration.chatHistory = []
            }

            function saveHistory() {
                var history = []
                var start = Math.max(0, root.chatModel.length - config.maxHistory)
                for (var i = start; i < root.chatModel.length; i++) {
                    history.push(JSON.stringify(root.chatModel[i]))
                }
                plasmoid.configuration.chatHistory = history
            }

            function loadHistory() {
                var raw = plasmoid.configuration.chatHistory
                if (!raw || raw.length === 0) return
                var loaded = []
                for (var i = 0; i < raw.length; i++) {
                    try { loaded.push(JSON.parse(raw[i])) } catch(e) {}
                }
                root.chatModel = loaded
            }

            // Opencode bridge: opencode -p "prompt"  (non-interactive mode)
            // Aider bridge:    aider --message "prompt"
            // Claude Code:     claude -p "prompt"
            function bridgeToCli(program, args) {
                var script = `
                    import QtQuick 2.0
                    import org.kde.plasma.core 2.0 as PlasmaCore
                    PlasmaCore.DataSource {
                        id: ds
                        engine: "executable"
                        connectedSources: []
                        onNewData: (src, data) => {
                            cliOutputLabel.text = (data["stdout"] || "") + (data["stderr"] || "")
                            disconnectSource(src)
                        }
                    }
                `
                // Build shell command – quote the last argument (the prompt)
                var cmd = program
                for (var i = 0; i < args.length; i++) {
                    if (i === args.length - 1) {
                        cmd += " " + JSON.stringify(args[i])   // quoted prompt
                    } else {
                        cmd += " " + args[i]
                    }
                }
                cliOutputLabel.text = "Running: " + cmd
                // Use PlasmaCore.DataSource executable engine
                executableDs.connectSource(cmd)
            }

            Component.onCompleted: loadHistory()
        }
    }

    // Plasma executable data source for CLI bridging
    PlasmaCore.DataSource {
        id: executableDs
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            var out = (data["stdout"] || "").trim()
            var err = (data["stderr"] || "").trim()
            // We can't directly reference fullRepRect here; use a signal or property
            execOutput = out !== "" ? out : (err !== "" ? "Error: " + err : "Done.")
            disconnectSource(sourceName)
        }
    }

    property string execOutput: ""
    onExecOutputChanged: {
        // The cliOutputLabel lives inside the component; update via the model trick
        if (execOutput !== "") {
            root.chatModel.push({ role: "error", content: "CLI: " + execOutput, model: "" })
            root.chatModel = root.chatModel
            execOutput = ""
        }
    }
}
