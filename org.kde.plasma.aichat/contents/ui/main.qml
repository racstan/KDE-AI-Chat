import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PE
import QtQuick.Dialogs

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    fullRepresentation: fullRep
    compactRepresentation: compactRep

    property var chatModel: []
    property bool isLoading: false
    property string currentProvider: plasmoid.configuration.provider
    property var config: plasmoid.configuration

    // Determine if we have a valid configuration
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
            color: Kirigami.Theme.backgroundColor
            Layout.minimumWidth: 380
            Layout.minimumHeight: 480
            Layout.preferredWidth: 480
            Layout.preferredHeight: 600

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                // Header with provider selector and settings
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PC3.ComboBox {
                        id: providerCombo
                        Layout.fillWidth: true
                        model: [
                            { value: "openai", text: "OpenAI" },
                            { value: "anthropic", text: "Anthropic" },
                            { value: "local", text: "Local (Ollama/LM Studio)" }
                        ]
                        textRole: "text"
                        valueRole: "value"
                        currentIndex: {
                            for (let i = 0; i < model.length; i++) {
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
                        onClicked: plasmoid.action("configure").trigger()
                    }
                }

                // Bridge indicators
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    visible: config.enableOpencodeBridge || config.enableAiderBridge || config.enableClaudeCodeBridge

                    PC3.Label {
                        text: "Bridges:"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                    }

                    Repeater {
                        model: [
                            { enabled: config.enableOpencodeBridge, name: "Opencode", color: "#4CAF50" },
                            { enabled: config.enableAiderBridge, name: "Aider", color: "#2196F3" },
                            { enabled: config.enableClaudeCodeBridge, name: "Claude Code", color: "#FF9800" }
                        ]

                        delegate: Rectangle {
                            visible: modelData.enabled
                            width: bridgeLabel.implicitWidth + Kirigami.Units.smallSpacing * 2
                            height: Kirigami.Units.gridUnit
                            radius: Kirigami.Units.smallSpacing
                            color: modelData.color
                            opacity: 0.8

                            PC3.Label {
                                id: bridgeLabel
                                anchors.centerIn: parent
                                text: modelData.name
                                color: "white"
                                font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                            }
                        }
                    }
                }

                // Configuration warning
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
                        text: currentProvider === "openai" ? "Please configure your OpenAI API key in settings." :
                              currentProvider === "anthropic" ? "Please configure your Anthropic API key in settings." :
                              "Local provider selected. Ensure your local server is running."
                        color: Kirigami.Theme.negativeTextColor
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                // Chat history
                ListView {
                    id: chatListView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: Kirigami.Units.smallSpacing
                    model: root.chatModel

                    delegate: Rectangle {
                        width: chatListView.width
                        height: msgColumn.implicitHeight + Kirigami.Units.smallSpacing * 2
                        color: modelData.role === "user" ? Kirigami.ColorUtils.tintWithAlpha(Kirigami.Theme.backgroundColor, Kirigami.Theme.highlightColor, 0.1) :
                              modelData.role === "assistant" ? Kirigami.Theme.backgroundColor :
                              Kirigami.Theme.alternateBackgroundColor
                        radius: Kirigami.Units.smallSpacing

                        Column {
                            id: msgColumn
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing / 2

                            Row {
                                spacing: Kirigami.Units.smallSpacing
                                Kirigami.Icon {
                                    width: Kirigami.Units.iconSizes.small
                                    height: width
                                    source: modelData.role === "user" ? "user-identity" :
                                            modelData.role === "assistant" ? "dialog-messages" : "code-context"
                                }
                                PC3.Label {
                                    text: modelData.role === "user" ? "You" :
                                          modelData.role === "assistant" ? "AI" : "System"
                                    font.bold: true
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                }
                                PC3.Label {
                                    visible: modelData.model !== undefined && modelData.model !== ""
                                    text: modelData.model || ""
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize - 2
                                    opacity: 0.6
                                }
                            }

                            PC3.Label {
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: modelData.content
                                textFormat: Text.MarkdownText
                                onLinkActivated: Qt.openUrlExternally(link)
                            }

                            // Action buttons for assistant messages
                            Row {
                                visible: modelData.role === "assistant" && !root.isLoading
                                spacing: Kirigami.Units.smallSpacing

                                PC3.ToolButton {
                                    icon.name: "edit-copy"
                                    text: "Copy"
                                    display: PC3.AbstractButton.IconOnly
                                    onClicked: {
                                        clipboardHelper.text = modelData.content
                                        clipboardHelper.selectAll()
                                        clipboardHelper.copy()
                                    }
                                }

                                PC3.ToolButton {
                                    visible: config.enableOpencodeBridge || config.enableAiderBridge
                                    icon.name: "dialog-xml-editor"
                                    text: "Send to CLI"
                                    display: PC3.AbstractButton.IconOnly
                                    onClicked: sendToCliMenu.open()

                                    PC3.Menu {
                                        id: sendToCliMenu
                                        PC3.MenuItem {
                                            visible: config.enableOpencodeBridge
                                            text: "Send to Opencode"
                                            onTriggered: sendToOpencode(modelData.content)
                                        }
                                        PC3.MenuItem {
                                            visible: config.enableAiderBridge
                                            text: "Send to Aider"
                                            onTriggered: sendToAider(modelData.content)
                                        }
                                        PC3.MenuItem {
                                            visible: config.enableClaudeCodeBridge
                                            text: "Send to Claude Code"
                                            onTriggered: sendToClaudeCode(modelData.content)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    PC3.ScrollBar.vertical: PC3.ScrollBar {}

                    function scrollToBottom() {
                        if (count > 0) {
                            positionViewAtEnd()
                        }
                    }
                }

                // Loading indicator
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.isLoading
                    spacing: Kirigami.Units.smallSpacing

                    PC3.BusyIndicator {
                        running: root.isLoading
                        width: Kirigami.Units.iconSizes.small
                        height: width
                    }

                    PC3.Label {
                        text: "Thinking..."
                        opacity: 0.7
                    }
                }

                // Input area
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PC3.TextArea {
                        id: messageInput
                        Layout.fillWidth: true
                        placeholderText: "Type your message..." + (config.enableOpencodeBridge ? " (Shift+Enter for newline)" : "")
                        wrapMode: Text.WordWrap
                        onAccepted: {
                            if (!(event.modifiers & Qt.ShiftModifier)) {
                                sendMessage()
                            }
                        }
                    }

                    ColumnLayout {
                        spacing: Kirigami.Units.smallSpacing

                        PC3.Button {
                            icon.name: "send-message"
                            enabled: !root.isLoading && messageInput.text.trim() !== "" && root.hasValidConfig
                            onClicked: sendMessage()
                        }

                        PC3.ToolButton {
                            icon.name: "edit-clear"
                            display: PC3.AbstractButton.IconOnly
                            onClicked: clearChat()
                        }
                    }
                }
            }

            // Clipboard helper
            TextEdit {
                id: clipboardHelper
                visible: false
            }

            // API request worker
            WorkerScript {
                id: apiWorker
                source: "apiWorker.mjs"
                onMessage: {
                    root.isLoading = false
                    if (messageObject.error) {
                        root.chatModel.push({
                            role: "error",
                            content: "Error: " + messageObject.error,
                            model: ""
                        })
                        root.chatModel = root.chatModel
                    } else {
                        root.chatModel.push({
                            role: "assistant",
                            content: messageObject.content,
                            model: messageObject.model || ""
                        })
                        root.chatModel = root.chatModel
                        saveHistory()
                    }
                    chatListView.scrollToBottom()
                }
            }

            function sendMessage() {
                var text = messageInput.text.trim()
                if (text === "" || root.isLoading) return

                // Add user message
                root.chatModel.push({
                    role: "user",
                    content: text,
                    model: ""
                })
                root.chatModel = root.chatModel
                messageInput.text = ""
                root.isLoading = true
                chatListView.scrollToBottom()

                // Prepare request
                var messages = []
                messages.push({
                    role: "system",
                    content: config.systemPrompt
                })

                for (var i = 0; i < root.chatModel.length; i++) {
                    if (root.chatModel[i].role !== "error") {
                        messages.push({
                            role: root.chatModel[i].role,
                            content: root.chatModel[i].content
                        })
                    }
                }

                var requestData = {
                    provider: root.currentProvider,
                    messages: messages,
                    config: {
                        openaiApiKey: config.openaiApiKey,
                        openaiBaseUrl: config.openaiBaseUrl,
                        openaiModel: config.openaiModel,
                        anthropicApiKey: config.anthropicApiKey,
                        anthropicModel: config.anthropicModel,
                        localBaseUrl: config.localBaseUrl,
                        localModel: config.localModel
                    }
                }

                apiWorker.sendMessage(requestData)
            }

            function clearChat() {
                root.chatModel = []
                plasmoid.configuration.chatHistory = []
            }

            function saveHistory() {
                var history = []
                var maxItems = Math.min(root.chatModel.length, config.maxHistory)
                var startIdx = root.chatModel.length - maxItems
                for (var i = startIdx; i < root.chatModel.length; i++) {
                    history.push(JSON.stringify(root.chatModel[i]))
                }
                plasmoid.configuration.chatHistory = history
            }

            function loadHistory() {
                var history = plasmoid.configuration.chatHistory
                if (history && history.length > 0) {
                    var loaded = []
                    for (var i = 0; i < history.length; i++) {
                        try {
                            loaded.push(JSON.parse(history[i]))
                        } catch (e) {}
                    }
                    root.chatModel = loaded
                }
            }

            function sendToOpencode(content) {
                bridgeToCli(config.opencodePath, content)
            }

            function sendToAider(content) {
                bridgeToCli(config.aiderPath, content)
            }

            function sendToClaudeCode(content) {
                bridgeToCli(config.claudeCodePath, content)
            }

            function bridgeToCli(cliPath, content) {
                var proc = Qt.createQmlObject(`
                    import QtQuick
                    Process {
                        property var callback
                        onReadyReadStandardOutput: {
                            var output = readAllStandardOutput()
                            console.log("CLI output:", output)
                        }
                        onReadyReadStandardError: {
                            var error = readAllStandardError()
                            console.log("CLI error:", error)
                        }
                    }
                `, root)

                proc.program = cliPath
                proc.arguments = ["--message", content]
                proc.start()
            }

            Component.onCompleted: {
                loadHistory()
            }
        }
    }
}
