import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3

Kirigami.ScrollablePage {
    id: configPage
    title: "AI Chat – Settings"

    // ── Preset model lists ───────────────────────────────────────────────
    readonly property var openaiModels: [
        "gpt-4o", "gpt-4o-mini", "gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano",
        "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo",
        "o1", "o1-mini", "o3", "o3-mini", "o4-mini"
    ]
    readonly property var anthropicModels: [
        "claude-sonnet-4-5", "claude-opus-4-5",
        "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022",
        "claude-3-7-sonnet-20250219",
        "claude-3-opus-20240229", "claude-3-haiku-20240307"
    ]

    Kirigami.FormLayout {
        wideMode: true

        // ════════════════════════════════════════════════════════════════
        // SECTION: Provider
        // ════════════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Active Provider"
        }

        PC3.ComboBox {
            id: providerCombo
            Kirigami.FormData.label: "Provider:"
            Layout.minimumWidth: 280
            model: [
                { value: "openai",    text: "OpenAI" },
                { value: "anthropic", text: "Anthropic Claude" },
                { value: "local",     text: "Local (Ollama / LM Studio / etc.)" }
            ]
            textRole: "text"
            valueRole: "value"
            currentIndex: {
                for (var i = 0; i < model.length; i++) {
                    if (model[i].value === plasmoid.configuration.provider) return i
                }
                return 0
            }
            onActivated: plasmoid.configuration.provider = currentValue
        }

        // ════════════════════════════════════════════════════════════════
        // SECTION: OpenAI
        // ════════════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "OpenAI Settings"
        }

        // API key with show/hide toggle
        RowLayout {
            Kirigami.FormData.label: "API Key:"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.TextField {
                id: openaiKeyField
                Layout.fillWidth: true
                echoMode: showOpenaiKey.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.openaiApiKey
                onTextEdited: plasmoid.configuration.openaiApiKey = text
                placeholderText: "sk-..."
            }
            PC3.CheckBox {
                id: showOpenaiKey
                text: "Show"
                checked: false
            }
        }

        PC3.TextField {
            Kirigami.FormData.label: "Base URL:"
            Layout.minimumWidth: 280
            text: plasmoid.configuration.openaiBaseUrl
            onTextEdited: plasmoid.configuration.openaiBaseUrl = text
            placeholderText: "https://api.openai.com/v1"
        }

        // Model: combo with free-text fallback
        RowLayout {
            Kirigami.FormData.label: "Model:"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.ComboBox {
                id: openaiModelCombo
                Layout.minimumWidth: 220
                editable: true
                model: configPage.openaiModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.openaiModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.openaiModel
                }
                onEditTextChanged: plasmoid.configuration.openaiModel = editText
                onActivated: plasmoid.configuration.openaiModel = currentText
            }
            PC3.Label {
                text: "or type custom model ID"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.6
            }
        }

        // ════════════════════════════════════════════════════════════════
        // SECTION: Anthropic
        // ════════════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Anthropic Settings"
        }

        RowLayout {
            Kirigami.FormData.label: "API Key:"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.TextField {
                id: anthropicKeyField
                Layout.fillWidth: true
                echoMode: showAnthropicKey.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.anthropicApiKey
                onTextEdited: plasmoid.configuration.anthropicApiKey = text
                placeholderText: "sk-ant-..."
            }
            PC3.CheckBox {
                id: showAnthropicKey
                text: "Show"
                checked: false
            }
        }

        RowLayout {
            Kirigami.FormData.label: "Model:"
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            PC3.ComboBox {
                id: anthropicModelCombo
                Layout.minimumWidth: 280
                editable: true
                model: configPage.anthropicModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.anthropicModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.anthropicModel
                }
                onEditTextChanged: plasmoid.configuration.anthropicModel = editText
                onActivated: plasmoid.configuration.anthropicModel = currentText
            }
        }

        // ════════════════════════════════════════════════════════════════
        // SECTION: Local / OpenAI-compatible
        // ════════════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Local Server Settings"
        }

        PC3.TextField {
            Kirigami.FormData.label: "Base URL:"
            Layout.minimumWidth: 280
            text: plasmoid.configuration.localBaseUrl
            onTextEdited: plasmoid.configuration.localBaseUrl = text
            placeholderText: "http://localhost:11434/v1"
        }

        PC3.TextField {
            Kirigami.FormData.label: "Model:"
            Layout.minimumWidth: 280
            text: plasmoid.configuration.localModel
            onTextEdited: plasmoid.configuration.localModel = text
            placeholderText: "llama3.2, mistral, codellama…"
        }

        PC3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.65
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Works with Ollama (port 11434), LM Studio (port 1234), llama.cpp server, text-generation-webui, and any OpenAI-compatible endpoint."
        }

        // ════════════════════════════════════════════════════════════════
        // SECTION: Chat behaviour
        // ════════════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Chat Behaviour"
        }

        PC3.TextArea {
            Kirigami.FormData.label: "System Prompt:"
            Layout.minimumWidth: 320
            Layout.minimumHeight: 80
            wrapMode: Text.WordWrap
            text: plasmoid.configuration.systemPrompt
            onTextChanged: plasmoid.configuration.systemPrompt = text
        }

        PC3.SpinBox {
            Kirigami.FormData.label: "Max history messages:"
            from: 10; to: 500; stepSize: 10
            value: plasmoid.configuration.maxHistory
            onValueModified: plasmoid.configuration.maxHistory = value
        }

        // ════════════════════════════════════════════════════════════════
        // SECTION: CLI Bridges
        // ════════════════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "CLI Bridges"
        }

        PC3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Bridges let you send an AI response directly to a coding CLI tool running in your terminal."
        }

        // ── Opencode ──────────────────────────────────────
        PC3.CheckBox {
            Kirigami.FormData.label: "Opencode:"
            text: "Enable Opencode bridge"
            checked: plasmoid.configuration.enableOpencodeBridge
            onToggled: plasmoid.configuration.enableOpencodeBridge = checked
        }

        RowLayout {
            Kirigami.FormData.label: "Path / command:"
            spacing: Kirigami.Units.smallSpacing
            enabled: plasmoid.configuration.enableOpencodeBridge

            PC3.TextField {
                id: opencodePathField
                Layout.minimumWidth: 220
                text: plasmoid.configuration.opencodePath
                onTextEdited: plasmoid.configuration.opencodePath = text
                placeholderText: "opencode"
            }
            PC3.Button {
                text: "Test"
                onClicked: testCli(opencodePathField.text, opencodeTestResult)
            }
            PC3.Label {
                id: opencodeTestResult
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        PC3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.65
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Invokes: opencode -p \"<response>\"\nInstall: curl -fsSL https://opencode.ai/install | bash"
        }

        // ── Aider ─────────────────────────────────────────
        PC3.CheckBox {
            Kirigami.FormData.label: "Aider:"
            text: "Enable Aider bridge"
            checked: plasmoid.configuration.enableAiderBridge
            onToggled: plasmoid.configuration.enableAiderBridge = checked
        }

        RowLayout {
            Kirigami.FormData.label: "Path / command:"
            spacing: Kirigami.Units.smallSpacing
            enabled: plasmoid.configuration.enableAiderBridge

            PC3.TextField {
                id: aiderPathField
                Layout.minimumWidth: 220
                text: plasmoid.configuration.aiderPath
                onTextEdited: plasmoid.configuration.aiderPath = text
                placeholderText: "aider"
            }
            PC3.Button {
                text: "Test"
                onClicked: testCli(aiderPathField.text, aiderTestResult)
            }
            PC3.Label {
                id: aiderTestResult
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        PC3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.65
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Invokes: aider --message \"<response>\"\nInstall: pip install aider-chat"
        }

        // ── Claude Code ───────────────────────────────────
        PC3.CheckBox {
            Kirigami.FormData.label: "Claude Code:"
            text: "Enable Claude Code bridge"
            checked: plasmoid.configuration.enableClaudeCodeBridge
            onToggled: plasmoid.configuration.enableClaudeCodeBridge = checked
        }

        RowLayout {
            Kirigami.FormData.label: "Path / command:"
            spacing: Kirigami.Units.smallSpacing
            enabled: plasmoid.configuration.enableClaudeCodeBridge

            PC3.TextField {
                id: claudePathField
                Layout.minimumWidth: 220
                text: plasmoid.configuration.claudeCodePath
                onTextEdited: plasmoid.configuration.claudeCodePath = text
                placeholderText: "claude"
            }
            PC3.Button {
                text: "Test"
                onClicked: testCli(claudePathField.text, claudeTestResult)
            }
            PC3.Label {
                id: claudeTestResult
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        PC3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            opacity: 0.65
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Invokes: claude -p \"<response>\"\nInstall: npm install -g @anthropic-ai/claude-code"
        }
    }

    // ── Helpers ─────────────────────────────────────────────────────────
    PlasmaCore.DataSource {
        id: testDs
        engine: "executable"
        connectedSources: []
        property var pendingLabel: null
        onNewData: (src, data) => {
            if (pendingLabel) {
                var found = (data["stdout"] || "").trim() !== "" || (data["stderr"] || "").trim() === ""
                pendingLabel.color = found ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                pendingLabel.text  = found ? "✔ found" : "✘ not found"
                pendingLabel = null
            }
            disconnectSource(src)
        }
    }

    function testCli(cmd, resultLabel) {
        resultLabel.text = "checking…"
        resultLabel.color = Kirigami.Theme.textColor
        testDs.pendingLabel = resultLabel
        testDs.connectSource("which " + cmd)
    }
}
