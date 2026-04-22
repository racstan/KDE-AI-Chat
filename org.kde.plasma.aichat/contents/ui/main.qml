import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
// Plasma 6: DataSource (executable engine) lives in plasma5support
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    fullRepresentation: fullRep
    compactRepresentation: compactRep

    property var chatModel: []
    property bool isLoading: false
    property string currentProvider: plasmoid.configuration.provider

    property bool hasValidConfig: {
        if (currentProvider === "openai")    return plasmoid.configuration.openaiApiKey    !== ""
        if (currentProvider === "anthropic") return plasmoid.configuration.anthropicApiKey !== ""
        if (currentProvider === "local")     return true
        return false
    }

    // ── Plasma 6 executable DataSource for CLI bridges ──────────────────
    P5Support.DataSource {
        id: execDs
        engine: "executable"
        connectedSources: []
        property string pendingCmd: ""
        onNewData: function(sourceName, data) {
            var out = (data["stdout"] || "").trim()
            var err = (data["stderr"] || "").trim()
            var msg = out !== "" ? out : (err !== "" ? "CLI error: " + err : "CLI command sent.")
            root.chatModel.push({ role: "system", content: "⚡ " + msg, model: "" })
            root.chatModel = root.chatModel
            disconnectSource(sourceName)
        }
    }

    function runCli(program, args) {
        // Build a single shell command string
        var parts = [program]
        for (var i = 0; i < args.length - 1; i++) parts.push(args[i])
        // Last arg is the prompt — shell-escape it
        parts.push(args[args.length - 1].replace(/'/g, "'\\''"))
        var cmd = parts.slice(0, parts.length - 1).join(" ") + " '" + parts[parts.length - 1] + "'"
        execDs.connectSource(cmd)
    }

    // ── Compact representation ──────────────────────────────────────────
    Component {
        id: compactRep
        Item {
            Kirigami.Icon {
                anchors.fill: parent
                source: "dialog-messages"
            }
        }
    }

    // ── Full representation ─────────────────────────────────────────────
    Component {
        id: fullRep
        Item {
            id: fullRepItem
            Layout.minimumWidth:  400
            Layout.minimumHeight: 500
            Layout.preferredWidth: 520
            Layout.preferredHeight: 660

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                // ── Top bar ───────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true

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
                        QQC2.ToolTip.text: "Settings"
                        QQC2.ToolTip.visible: hovered
                        onClicked: plasmoid.action("configure").trigger()
                    }
                }

                // ── Bridge pills ──────────────────────────────────────
                Flow {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing
                    visible: plasmoid.configuration.enableOpencodeBridge
                          || plasmoid.configuration.enableAiderBridge
                          || plasmoid.configuration.enableClaudeCodeBridge

                    PC3.Label {
                        text: "Bridges:"
                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                        opacity: 0.7
                    }

                    Repeater {
                        model: [
                            { on: plasmoid.configuration.enableOpencodeBridge,   name: "Opencode",    bg: "#4CAF50" },
                            { on: plasmoid.configuration.enableAiderBridge,      name: "Aider",       bg: "#2196F3" },
                            { on: plasmoid.configuration.enableClaudeCodeBridge, name: "Claude Code", bg: "#FF9800" }
                        ]
                        delegate: Rectangle {
                            visible: modelData.on
                            width:  lbl.implicitWidth + Kirigami.Units.smallSpacing * 2
                            height: Kirigami.Units.gridUnit
                            radius: height / 2
                            color:  modelData.bg
                            PC3.Label {
                                id: lbl
                                anchors.centerIn: parent
                                text: modelData.name
                                color: "white"
                                font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                            }
                        }
                    }
                }

                // ── Config warning ────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: warnLabel.implicitHeight + Kirigami.Units.smallSpacing * 2
                    visible: !root.hasValidConfig
                    color: Kirigami.Theme.negativeBackgroundColor
                    radius: Kirigami.Units.smallSpacing
                    PC3.Label {
                        id: warnLabel
                        anchors.centerIn: parent
                        width: parent.width - Kirigami.Units.smallSpacing * 4
                        wrapMode: Text.Wrap
                        horizontalAlignment: Text.AlignHCenter
                        color: Kirigami.Theme.negativeTextColor
                        text: root.currentProvider === "openai"
                              ? "Set your OpenAI API key in Settings (gear icon)."
                              : root.currentProvider === "anthropic"
                                ? "Set your Anthropic API key in Settings (gear icon)."
                                : "Local provider – make sure your server is running."
                    }
                }

                // ── Chat list ─────────────────────────────────────────
                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    QQC2.ScrollBar.horizontal.policy: QQC2.ScrollBar.AlwaysOff

                    ListView {
                        id: chatListView
                        spacing: Kirigami.Units.smallSpacing
                        model: root.chatModel

                        delegate: Rectangle {
                            width: chatListView.width
                            height: msgCol.implicitHeight + Kirigami.Units.smallSpacing * 2
                            radius: Kirigami.Units.smallSpacing
                            color: {
                                if (modelData.role === "user")   return Qt.rgba(
                                    Kirigami.Theme.highlightColor.r,
                                    Kirigami.Theme.highlightColor.g,
                                    Kirigami.Theme.highlightColor.b, 0.10)
                                if (modelData.role === "error")  return Kirigami.Theme.negativeBackgroundColor
                                if (modelData.role === "system") return Qt.rgba(0,0,0,0.06)
                                return Kirigami.Theme.alternateBackgroundColor
                            }

                            Column {
                                id: msgCol
                                anchors {
                                    top: parent.top; left: parent.left; right: parent.right
                                    margins: Kirigami.Units.smallSpacing
                                }
                                spacing: Kirigami.Units.smallSpacing / 2

                                // Role header
                                Row {
                                    spacing: Kirigami.Units.smallSpacing
                                    Kirigami.Icon {
                                        width: Kirigami.Units.iconSizes.small; height: width
                                        source: modelData.role === "user"   ? "user-identity"
                                              : modelData.role === "error"  ? "dialog-error"
                                              : modelData.role === "system" ? "utilities-terminal"
                                              :                                "dialog-messages"
                                    }
                                    PC3.Label {
                                        font.bold: true
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize
                                        text: modelData.role === "user"   ? "You"
                                            : modelData.role === "error"  ? "Error"
                                            : modelData.role === "system" ? "CLI"
                                            :                               "AI"
                                    }
                                    PC3.Label {
                                        visible: (modelData.model || "") !== ""
                                        text: "· " + (modelData.model || "")
                                        font.pointSize: Kirigami.Theme.smallFont.pointSize - 1
                                        opacity: 0.55
                                    }
                                }

                                // Body
                                PC3.Label {
                                    width: msgCol.width
                                    wrapMode: Text.Wrap
                                    textFormat: Text.MarkdownText
                                    text: modelData.content
                                    color: modelData.role === "error"
                                           ? Kirigami.Theme.negativeTextColor
                                           : Kirigami.Theme.textColor
                                    onLinkActivated: link => Qt.openUrlExternally(link)
                                }

                                // Action row (assistant messages only)
                                Row {
                                    visible: modelData.role === "assistant" && !root.isLoading
                                    spacing: Kirigami.Units.smallSpacing

                                    PC3.ToolButton {
                                        icon.name: "edit-copy"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.text: "Copy"
                                        QQC2.ToolTip.visible: hovered
                                        onClicked: {
                                            clipHelper.text = modelData.content
                                            clipHelper.selectAll()
                                            clipHelper.copy()
                                        }
                                    }

                                    PC3.ToolButton {
                                        visible: plasmoid.configuration.enableOpencodeBridge
                                              || plasmoid.configuration.enableAiderBridge
                                              || plasmoid.configuration.enableClaudeCodeBridge
                                        icon.name: "utilities-terminal"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.text: "Send to coding CLI"
                                        QQC2.ToolTip.visible: hovered
                                        onClicked: cliMenu.open()

                                        PC3.Menu {
                                            id: cliMenu
                                            PC3.MenuItem {
                                                visible: plasmoid.configuration.enableOpencodeBridge
                                                text: "Opencode  (opencode -p …)"
                                                onTriggered: root.runCli(
                                                    plasmoid.configuration.opencodePath,
                                                    ["-p", modelData.content])
                                            }
                                            PC3.MenuItem {
                                                visible: plasmoid.configuration.enableAiderBridge
                                                text: "Aider  (aider --message …)"
                                                onTriggered: root.runCli(
                                                    plasmoid.configuration.aiderPath,
                                                    ["--message", modelData.content])
                                            }
                                            PC3.MenuItem {
                                                visible: plasmoid.configuration.enableClaudeCodeBridge
                                                text: "Claude Code  (claude -p …)"
                                                onTriggered: root.runCli(
                                                    plasmoid.configuration.claudeCodePath,
                                                    ["-p", modelData.content])
                                            }
                                        }
                                    }

                                    PC3.ToolButton {
                                        icon.name: "view-refresh"
                                        display: PC3.AbstractButton.IconOnly
                                        QQC2.ToolTip.text: "Regenerate"
                                        QQC2.ToolTip.visible: hovered
                                        onClicked: regenerate()
                                    }
                                }
                            }
                        }

                        function scrollToBottom() { positionViewAtEnd() }
                    }
                }

                // ── Thinking indicator ────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.isLoading
                    PC3.BusyIndicator {
                        running: root.isLoading
                        width: Kirigami.Units.iconSizes.small; height: width
                    }
                    PC3.Label { text: "Thinking…"; opacity: 0.7 }
                }

                // ── Input row ─────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    QQC2.TextArea {
                        id: msgInput
                        Layout.fillWidth: true
                        placeholderText: "Message… (Enter = send, Shift+Enter = newline)"
                        wrapMode: Text.WordWrap
                        background: Rectangle {
                            color: Kirigami.Theme.backgroundColor
                            border.color: msgInput.activeFocus
                                ? Kirigami.Theme.highlightColor
                                : Kirigami.Theme.disabledTextColor
                            border.width: 1
                            radius: Kirigami.Units.smallSpacing
                        }
                        color: Kirigami.Theme.textColor
                        // FIX: TextArea has no onAccepted — use Keys.onPressed
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
                            icon.name: "document-send"
                            QQC2.ToolTip.text: "Send"
                            QQC2.ToolTip.visible: hovered
                            enabled: !root.isLoading
                                  && msgInput.text.trim() !== ""
                                  && root.hasValidConfig
                            onClicked: sendMessage()
                        }

                        PC3.ToolButton {
                            icon.name: "edit-clear-history"
                            display: PC3.AbstractButton.IconOnly
                            QQC2.ToolTip.text: "Clear chat"
                            QQC2.ToolTip.visible: hovered
                            onClicked: clearChat()
                        }
                    }
                }
            }

            // Invisible clipboard helper
            TextEdit { id: clipHelper; visible: false }

            // ── API worker ────────────────────────────────────────────
            WorkerScript {
                id: apiWorker
                source: "apiWorker.mjs"
                onMessage: function(msg) {
                    root.isLoading = false
                    if (msg.error) {
                        root.chatModel.push({ role: "error", content: msg.error, model: "" })
                    } else {
                        root.chatModel.push({ role: "assistant", content: msg.content, model: msg.model || "" })
                        saveHistory()
                    }
                    root.chatModel = root.chatModel
                    chatListView.scrollToBottom()
                }
            }

            // ── Helpers ───────────────────────────────────────────────
            function apiConfig() {
                return {
                    openaiApiKey:    plasmoid.configuration.openaiApiKey,
                    openaiBaseUrl:   plasmoid.configuration.openaiBaseUrl,
                    openaiModel:     plasmoid.configuration.openaiModel,
                    anthropicApiKey: plasmoid.configuration.anthropicApiKey,
                    anthropicModel:  plasmoid.configuration.anthropicModel,
                    localBaseUrl:    plasmoid.configuration.localBaseUrl,
                    localModel:      plasmoid.configuration.localModel
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

            function sendMessage() {
                var text = msgInput.text.trim()
                if (text === "" || root.isLoading) return
                root.chatModel.push({ role: "user", content: text, model: "" })
                root.chatModel = root.chatModel
                msgInput.text = ""
                root.isLoading = true
                chatListView.scrollToBottom()
                apiWorker.sendMessage({
                    provider: root.currentProvider,
                    messages: buildMessages(),
                    config: apiConfig()
                })
            }

            function regenerate() {
                if (root.chatModel.length > 0
                        && root.chatModel[root.chatModel.length - 1].role === "assistant") {
                    root.chatModel.pop()
                    root.chatModel = root.chatModel
                }
                if (root.chatModel.length === 0) return
                root.isLoading = true
                apiWorker.sendMessage({
                    provider: root.currentProvider,
                    messages: buildMessages(),
                    config: apiConfig()
                })
            }

            function clearChat() {
                root.chatModel = []
                plasmoid.configuration.chatHistory = []
            }

            function saveHistory() {
                var h = []
                var start = Math.max(0, root.chatModel.length - plasmoid.configuration.maxHistory)
                for (var i = start; i < root.chatModel.length; i++)
                    h.push(JSON.stringify(root.chatModel[i]))
                plasmoid.configuration.chatHistory = h
            }

            function loadHistory() {
                var raw = plasmoid.configuration.chatHistory
                if (!raw || raw.length === 0) return
                var out = []
                for (var i = 0; i < raw.length; i++) {
                    try { out.push(JSON.parse(raw[i])) } catch(e) {}
                }
                root.chatModel = out
            }

            Component.onCompleted: loadHistory()
        }
    }
}
