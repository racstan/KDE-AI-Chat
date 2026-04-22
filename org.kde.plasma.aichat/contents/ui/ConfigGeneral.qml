import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support

Kirigami.ScrollablePage {
    id: configPage
    title: "AI Chat – Settings"

    readonly property var openaiModels: [
        "gpt-4o", "gpt-4o-mini",
        "gpt-4.1", "gpt-4.1-mini", "gpt-4.1-nano",
        "gpt-4-turbo", "gpt-4",
        "o1", "o1-mini", "o3", "o3-mini", "o4-mini"
    ]
    readonly property var anthropicModels: [
        "claude-sonnet-4-5",
        "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022",
        "claude-3-7-sonnet-20250219",
        "claude-3-opus-20240229", "claude-3-haiku-20240307"
    ]

    // CLI tester using Plasma 6 plasma5support DataSource
    P5Support.DataSource {
        id: testDs
        engine: "executable"
        connectedSources: []
        property var resultLabel: null
        onNewData: function(sourceName, data) {
            var found = ((data["stdout"] || "").trim() !== "")
            if (resultLabel) {
                resultLabel.color = found ? Kirigami.Theme.positiveTextColor
                                          : Kirigami.Theme.negativeTextColor
                resultLabel.text  = found ? "✔ found" : "✘ not found"
                resultLabel = null
            }
            disconnectSource(sourceName)
        }
    }

    function testCli(cmd, lbl) {
        lbl.text  = "checking…"
        lbl.color = Kirigami.Theme.textColor
        testDs.resultLabel = lbl
        testDs.connectSource("which " + cmd)
    }

    Kirigami.FormLayout {
        wideMode: true

        // ══ Provider ══════════════════════════════════════════════════
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

        // ══ OpenAI ════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "OpenAI"
        }

        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: oaiKey
                Layout.minimumWidth: 240
                echoMode: showOai.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.openaiApiKey
                onTextEdited: plasmoid.configuration.openaiApiKey = text
                placeholderText: "sk-…"
            }
            PC3.CheckBox { id: showOai; text: "Show" }
        }

        PC3.TextField {
            Kirigami.FormData.label: "Base URL:"
            Layout.minimumWidth: 280
            text: plasmoid.configuration.openaiBaseUrl
            onTextEdited: plasmoid.configuration.openaiBaseUrl = text
            placeholderText: "https://api.openai.com/v1"
        }

        RowLayout {
            Kirigami.FormData.label: "Model:"
            spacing: Kirigami.Units.smallSpacing
            PC3.ComboBox {
                id: oaiModel
                Layout.minimumWidth: 220
                editable: true
                model: configPage.openaiModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.openaiModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.openaiModel
                }
                onEditTextChanged: plasmoid.configuration.openaiModel = editText
                onActivated:       plasmoid.configuration.openaiModel = currentText
            }
            PC3.Label {
                text: "(or type any model ID)"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                opacity: 0.6
            }
        }

        // ══ Anthropic ═════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Anthropic"
        }

        RowLayout {
            Kirigami.FormData.label: "API Key:"
            spacing: Kirigami.Units.smallSpacing
            PC3.TextField {
                id: antKey
                Layout.minimumWidth: 240
                echoMode: showAnt.checked ? TextInput.Normal : TextInput.Password
                text: plasmoid.configuration.anthropicApiKey
                onTextEdited: plasmoid.configuration.anthropicApiKey = text
                placeholderText: "sk-ant-…"
            }
            PC3.CheckBox { id: showAnt; text: "Show" }
        }

        RowLayout {
            Kirigami.FormData.label: "Model:"
            spacing: Kirigami.Units.smallSpacing
            PC3.ComboBox {
                id: antModel
                Layout.minimumWidth: 280
                editable: true
                model: configPage.anthropicModels
                Component.onCompleted: {
                    var idx = find(plasmoid.configuration.anthropicModel)
                    currentIndex = idx >= 0 ? idx : -1
                    editText = plasmoid.configuration.anthropicModel
                }
                onEditTextChanged: plasmoid.configuration.anthropicModel = editText
                onActivated:       plasmoid.configuration.anthropicModel = currentText
            }
        }

        // ══ Local ═════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Local Server"
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
            text: "Ollama: http://localhost:11434/v1\nLM Studio: http://localhost:1234/v1"
        }

        // ══ Chat ══════════════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Chat Behaviour"
        }

        QQC2.TextArea {
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

        // ══ CLI Bridges ═══════════════════════════════════════════════
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "CLI Bridges"
        }

        PC3.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Send AI responses directly to a coding CLI tool."
        }

        // Opencode
        PC3.CheckBox {
            Kirigami.FormData.label: "Opencode:"
            text: "Enable"
            checked: plasmoid.configuration.enableOpencodeBridge
            onToggled: plasmoid.configuration.enableOpencodeBridge = checked
        }
        RowLayout {
            Kirigami.FormData.label: "Command:"
            spacing: Kirigami.Units.smallSpacing
            enabled: plasmoid.configuration.enableOpencodeBridge
            PC3.TextField {
                id: ocPath
                Layout.minimumWidth: 180
                text: plasmoid.configuration.opencodePath
                onTextEdited: plasmoid.configuration.opencodePath = text
                placeholderText: "opencode"
            }
            PC3.Button {
                text: "Test"
                onClicked: testCli(ocPath.text, ocResult)
            }
            PC3.Label { id: ocResult; font.pointSize: Kirigami.Theme.smallFont.pointSize }
        }
        PC3.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Runs: opencode -p \"…\"\nInstall: curl -fsSL https://opencode.ai/install | bash"
        }

        // Aider
        PC3.CheckBox {
            Kirigami.FormData.label: "Aider:"
            text: "Enable"
            checked: plasmoid.configuration.enableAiderBridge
            onToggled: plasmoid.configuration.enableAiderBridge = checked
        }
        RowLayout {
            Kirigami.FormData.label: "Command:"
            spacing: Kirigami.Units.smallSpacing
            enabled: plasmoid.configuration.enableAiderBridge
            PC3.TextField {
                id: aiderPath
                Layout.minimumWidth: 180
                text: plasmoid.configuration.aiderPath
                onTextEdited: plasmoid.configuration.aiderPath = text
                placeholderText: "aider"
            }
            PC3.Button {
                text: "Test"
                onClicked: testCli(aiderPath.text, aiderResult)
            }
            PC3.Label { id: aiderResult; font.pointSize: Kirigami.Theme.smallFont.pointSize }
        }
        PC3.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Runs: aider --message \"…\"\nInstall: pip install aider-chat"
        }

        // Claude Code
        PC3.CheckBox {
            Kirigami.FormData.label: "Claude Code:"
            text: "Enable"
            checked: plasmoid.configuration.enableClaudeCodeBridge
            onToggled: plasmoid.configuration.enableClaudeCodeBridge = checked
        }
        RowLayout {
            Kirigami.FormData.label: "Command:"
            spacing: Kirigami.Units.smallSpacing
            enabled: plasmoid.configuration.enableClaudeCodeBridge
            PC3.TextField {
                id: claudePath
                Layout.minimumWidth: 180
                text: plasmoid.configuration.claudeCodePath
                onTextEdited: plasmoid.configuration.claudeCodePath = text
                placeholderText: "claude"
            }
            PC3.Button {
                text: "Test"
                onClicked: testCli(claudePath.text, claudeResult)
            }
            PC3.Label { id: claudeResult; font.pointSize: Kirigami.Theme.smallFont.pointSize }
        }
        PC3.Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap; opacity: 0.6
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: "Runs: claude -p \"…\"\nInstall: npm install -g @anthropic-ai/claude-code"
        }
    }
}
