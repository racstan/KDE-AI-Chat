import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import org.kde.kconfig as KConfig
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3

Kirigami.ScrollablePage {
    title: "AI Chat Configuration"

    Kirigami.FormLayout {
        wideMode: true

        // Provider Selection
        Item {
            Kirigami.FormData.label: "AI Provider:"
            Kirigami.FormData.isSection: false
        }

        PC3.ComboBox {
            Kirigami.FormData.label: "Provider:"
            Layout.fillWidth: true
            id: providerCombo
            model: [
                { value: "openai", text: "OpenAI" },
                { value: "anthropic", text: "Anthropic Claude" },
                { value: "local", text: "Local (Ollama / LM Studio / etc.)" }
            ]
            textRole: "text"
            valueRole: "value"
            currentIndex: providerCombo.indexOfValue(plasmoid.configuration.provider)
            onActivated: plasmoid.configuration.provider = currentValue
        }

        // OpenAI Settings
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "OpenAI Settings"
            visible: providerCombo.currentValue === "openai"
        }

        PC3.TextField {
            Kirigami.FormData.label: "API Key:"
            Layout.fillWidth: true
            visible: providerCombo.currentValue === "openai"
            echoMode: TextInput.Password
            text: plasmoid.configuration.openaiApiKey
            onTextChanged: plasmoid.configuration.openaiApiKey = text
            placeholderText: "sk-..."
        }

        PC3.TextField {
            Kirigami.FormData.label: "Base URL:"
            Layout.fillWidth: true
            visible: providerCombo.currentValue === "openai"
            text: plasmoid.configuration.openaiBaseUrl
            onTextChanged: plasmoid.configuration.openaiBaseUrl = text
            placeholderText: "https://api.openai.com/v1"
        }

        PC3.TextField {
            Kirigami.FormData.label: "Model:"
            Layout.fillWidth: true
            visible: providerCombo.currentValue === "openai"
            text: plasmoid.configuration.openaiModel
            onTextChanged: plasmoid.configuration.openaiModel = text
            placeholderText: "gpt-4o-mini"
        }

        // Anthropic Settings
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Anthropic Settings"
            visible: providerCombo.currentValue === "anthropic"
        }

        PC3.TextField {
            Kirigami.FormData.label: "API Key:"
            Layout.fillWidth: true
            visible: providerCombo.currentValue === "anthropic"
            echoMode: TextInput.Password
            text: plasmoid.configuration.anthropicApiKey
            onTextChanged: plasmoid.configuration.anthropicApiKey = text
            placeholderText: "sk-ant-..."
        }

        PC3.TextField {
            Kirigami.FormData.label: "Model:"
            Layout.fillWidth: true
            visible: providerCombo.currentValue === "anthropic"
            text: plasmoid.configuration.anthropicModel
            onTextChanged: plasmoid.configuration.anthropicModel = text
            placeholderText: "claude-3-5-sonnet-20241022"
        }

        // Local Settings
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Local Server Settings"
            visible: providerCombo.currentValue === "local"
        }

        PC3.TextField {
            Kirigami.FormData.label: "Base URL:"
            Layout.fillWidth: true
            visible: providerCombo.currentValue === "local"
            text: plasmoid.configuration.localBaseUrl
            onTextChanged: plasmoid.configuration.localBaseUrl = text
            placeholderText: "http://localhost:11434/v1"
        }

        PC3.TextField {
            Kirigami.FormData.label: "Model:"
            Layout.fillWidth: true
            visible: providerCombo.currentValue === "local"
            text: plasmoid.configuration.localModel
            onTextChanged: plasmoid.configuration.localModel = text
            placeholderText: "llama2, codellama, mistral..."
        }

        PC3.Label {
            visible: providerCombo.currentValue === "local"
            text: "Compatible with Ollama, LM Studio, llama.cpp server, text-generation-webui, and any OpenAI-compatible local endpoint."
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        // General Settings
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "General Settings"
        }

        PC3.TextArea {
            Kirigami.FormData.label: "System Prompt:"
            Layout.fillWidth: true
            text: plasmoid.configuration.systemPrompt
            onTextChanged: plasmoid.configuration.systemPrompt = text
            wrapMode: Text.WordWrap
        }

        PC3.SpinBox {
            Kirigami.FormData.label: "Max History:"
            from: 10
            to: 200
            value: plasmoid.configuration.maxHistory
            onValueModified: plasmoid.configuration.maxHistory = value
        }

        // CLI Bridge Settings
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "CLI Bridge Settings"
        }

        PC3.Label {
            text: "Enable bridges to send AI responses directly to coding CLI tools:"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        PC3.CheckBox {
            Kirigami.FormData.label: "Opencode:"
            text: "Enable Opencode bridge"
            checked: plasmoid.configuration.enableOpencodeBridge
            onCheckedChanged: plasmoid.configuration.enableOpencodeBridge = checked
        }

        PC3.TextField {
            Kirigami.FormData.label: "Path:"
            Layout.fillWidth: true
            text: plasmoid.configuration.opencodePath
            onTextChanged: plasmoid.configuration.opencodePath = text
            placeholderText: "opencode"
        }

        PC3.CheckBox {
            Kirigami.FormData.label: "Aider:"
            text: "Enable Aider bridge"
            checked: plasmoid.configuration.enableAiderBridge
            onCheckedChanged: plasmoid.configuration.enableAiderBridge = checked
        }

        PC3.TextField {
            Kirigami.FormData.label: "Path:"
            Layout.fillWidth: true
            text: plasmoid.configuration.aiderPath
            onTextChanged: plasmoid.configuration.aiderPath = text
            placeholderText: "aider"
        }

        PC3.CheckBox {
            Kirigami.FormData.label: "Claude Code:"
            text: "Enable Claude Code bridge"
            checked: plasmoid.configuration.enableClaudeCodeBridge
            onCheckedChanged: plasmoid.configuration.enableClaudeCodeBridge = checked
        }

        PC3.TextField {
            Kirigami.FormData.label: "Path:"
            Layout.fillWidth: true
            text: plasmoid.configuration.claudeCodePath
            onTextChanged: plasmoid.configuration.claudeCodePath = text
            placeholderText: "claude"
        }

        PC3.Label {
            text: "Note: CLI bridges send the AI response as a message/command to the respective tool. Make sure the tools are installed and available in your PATH."
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            opacity: 0.7
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }

        PC3.Button {
            text: "Test CLI Availability"
            onClicked: testCliAvailability()
        }
    }

    function testCliAvailability() {
        var tools = [
            { name: "Opencode", path: plasmoid.configuration.opencodePath, enabled: plasmoid.configuration.enableOpencodeBridge },
            { name: "Aider", path: plasmoid.configuration.aiderPath, enabled: plasmoid.configuration.enableAiderBridge },
            { name: "Claude Code", path: plasmoid.configuration.claudeCodePath, enabled: plasmoid.configuration.enableClaudeCodeBridge }
        ]

        var results = []
        var checkedCount = 0

        for (var i = 0; i < tools.length; i++) {
            if (!tools[i].enabled) continue
            checkedCount++

            var proc = Qt.createQmlObject(`
                import QtQuick
                Process {
                    property string toolName
                    property var onComplete
                    onReadyReadStandardOutput: {
                        var output = readAllStandardOutput()
                        onComplete(toolName, true, output)
                    }
                    onReadyReadStandardError: {
                        var error = readAllStandardError()
                        onComplete(toolName, false, error)
                    }
                }
            `, parent)

            proc.toolName = tools[i].name
            proc.onComplete = function(name, success, output) {
                results.push(name + ": " + (success ? "Available" : "Not found"))
                if (results.length === checkedCount) {
                    testResultDialog.text = results.join("\n")
                    testResultDialog.open()
                }
            }
            proc.program = "which"
            proc.arguments = [tools[i].path]
            proc.start()
        }

        if (checkedCount === 0) {
            testResultDialog.text = "No CLI bridges enabled."
            testResultDialog.open()
        }
    }

    Dialog {
        id: testResultDialog
        title: "CLI Availability Test"
        standardButtons: Dialog.Ok
        modal: true
        anchors.centerIn: parent
        width: 300

        property alias text: resultLabel.text

        PC3.Label {
            id: resultLabel
            width: parent.width
            wrapMode: Text.Wrap
        }
    }
}
