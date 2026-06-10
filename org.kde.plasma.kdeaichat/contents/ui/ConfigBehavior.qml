// LINKAGE RELATIONSHIPS:
// - ConfigBehavior.qml: Standalone KCM settings page for Behavior features.
//   Contains System Prompt, Global Memory, Global Context, Prompt Templates, and Voice settings.
// - Registered as a ConfigCategory in config.qml alongside General and Widget Shortcuts.
// - Binds directly to plasmoid.configuration via cfg_* properties (no page proxy needed).

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import "translations.js" as Translations

QQC2.ScrollView {
    id: behaviorPage

    contentWidth: availableWidth
    contentHeight: contentColumn.implicitHeight + Kirigami.Units.gridUnit * 2

    // ── cfg_ bindings — auto-synced by KDE KCM framework ──────────────────
    property string cfg_systemPrompt: ""
    property bool   cfg_memoryEnabled: false
    property string cfg_userMemory: ""
    property bool   cfg_globalContextEnabled: true
    property int    cfg_globalContextLimit: 10
    property bool   cfg_globalContextAutoCompact: false
    property int    cfg_globalContextCompactThreshold: 10
    property string cfg_promptTemplates: "[]"
    property bool   cfg_voiceEnabled: false
    property bool   cfg_voiceTtsEnabled: false
    property bool   cfg_voiceAutoSend: false
    property string cfg_language: ""

    // ── helpers ────────────────────────────────────────────────────────────
    function translate(text) {
        return Translations.translate(text, cfg_language);
    }

    readonly property real fieldMaxWidth: Math.min(availableWidth, Kirigami.Units.gridUnit * 38)

    ColumnLayout {
        id: contentColumn
        width: behaviorPage.availableWidth
        spacing: 0

        Kirigami.FormLayout {
            id: behaviorForm
            Layout.fillWidth: true

            // ── Section header ─────────────────────────────────────────────
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: behaviorPage.translate("Behavior")
            }

            // ── System Prompt ──────────────────────────────────────────────
            QQC2.ScrollView {
                id: systemPromptScrollView
                Kirigami.FormData.label: behaviorPage.translate("System prompt:")
                implicitHeight: Kirigami.Units.gridUnit * 5
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                Layout.preferredHeight: Kirigami.Units.gridUnit * 5
                Layout.maximumHeight: Kirigami.Units.gridUnit * 5
                clip: true

                QQC2.TextArea {
                    id: systemPromptArea
                    width: systemPromptScrollView.availableWidth
                    wrapMode: Text.Wrap
                    placeholderText: "You are KDE AI Chat, a precise and helpful assistant."
                    background: null
                    padding: Kirigami.Units.smallSpacing + 2
                    text: behaviorPage.cfg_systemPrompt
                    onTextChanged: behaviorPage.cfg_systemPrompt = text
                }

                background: Rectangle {
                    color: Kirigami.Theme.backgroundColor
                    radius: 4
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                    border.width: 1
                }
            }

            QQC2.Label {
                Kirigami.FormData.label: ""
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: behaviorPage.translate("Sets a default instruction sent to the AI at the start of every conversation. Leave blank for the built-in default.")
            }

            // ── Global Memory ──────────────────────────────────────────────
            QQC2.CheckBox {
                id: memoryEnabledToggle
                Kirigami.FormData.label: behaviorPage.translate("Global Memory:")
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                checked: behaviorPage.cfg_memoryEnabled
                onCheckedChanged: behaviorPage.cfg_memoryEnabled = checked
                text: checked
                    ? behaviorPage.translate("Enabled — memory is injected into every prompt")
                    : behaviorPage.translate("Disabled")
            }

            QQC2.Label {
                Kirigami.FormData.label: ""
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: behaviorPage.translate("Write facts you want the AI to always remember — your name, preferences, context. Injected at the start of every prompt when enabled.")
            }

            QQC2.ScrollView {
                id: userMemoryScrollView
                visible: memoryEnabledToggle.checked
                implicitHeight: Kirigami.Units.gridUnit * 6
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                Layout.preferredHeight: Kirigami.Units.gridUnit * 6
                Layout.maximumHeight: Kirigami.Units.gridUnit * 6
                clip: true

                QQC2.TextArea {
                    id: userMemoryArea
                    width: userMemoryScrollView.availableWidth
                    wrapMode: Text.Wrap
                    placeholderText: "E.g., My name is Alex. I use KDE Plasma 6. I prefer Python for scripting. Always be concise."
                    background: null
                    padding: Kirigami.Units.smallSpacing + 2
                    text: behaviorPage.cfg_userMemory
                    onTextChanged: behaviorPage.cfg_userMemory = text
                }

                background: Rectangle {
                    color: Kirigami.Theme.backgroundColor
                    radius: 4
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
                    border.width: 1
                }
            }

            QQC2.Label {
                visible: memoryEnabledToggle.checked
                Kirigami.FormData.label: ""
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: behaviorPage.translate("Memory is saved with your settings (Apply/OK). It persists across sessions and is prepended to the system prompt.")
            }

            // ── Global Context ─────────────────────────────────────────────
            QQC2.CheckBox {
                id: globalContextEnabledToggle
                Kirigami.FormData.label: behaviorPage.translate("Global Context:")
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                checked: behaviorPage.cfg_globalContextEnabled
                onCheckedChanged: behaviorPage.cfg_globalContextEnabled = checked
                text: checked
                    ? behaviorPage.translate("Enabled — chat context will be sent to AI")
                    : behaviorPage.translate("Disabled — AI will only see the current prompt")
            }

            QQC2.Label {
                Kirigami.FormData.label: ""
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: behaviorPage.translate("Each chat has the ability to modify the context settings for that chat. If nothing is specified there, then this global context default is used. When disabled, the AI only answers the immediate question without remembering previous messages.")
            }

            RowLayout {
                visible: globalContextEnabledToggle.checked
                spacing: Kirigami.Units.smallSpacing
                Kirigami.FormData.label: behaviorPage.translate("Context limit:")
                Layout.maximumWidth: behaviorPage.fieldMaxWidth

                QQC2.SpinBox {
                    id: globalContextLimitSpin
                    from: 1
                    to: 100
                    value: behaviorPage.cfg_globalContextLimit
                    editable: true
                    onValueChanged: behaviorPage.cfg_globalContextLimit = value
                }

                QQC2.Label {
                    text: behaviorPage.translate("messages")
                }
            }

            QQC2.Label {
                visible: globalContextEnabledToggle.checked
                Kirigami.FormData.label: ""
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: behaviorPage.translate("The maximum number of recent messages sent to the AI in each request to preserve token limit / memory.")
            }

            QQC2.CheckBox {
                id: globalContextAutoCompactToggle
                visible: globalContextEnabledToggle.checked
                Kirigami.FormData.label: behaviorPage.translate("Context compacting:")
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                checked: behaviorPage.cfg_globalContextAutoCompact
                onCheckedChanged: behaviorPage.cfg_globalContextAutoCompact = checked
                text: behaviorPage.translate("Auto compact")
            }

            QQC2.Label {
                visible: globalContextEnabledToggle.checked
                Kirigami.FormData.label: ""
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: behaviorPage.translate("When enabled, older messages exceeding the threshold are automatically summarized in the background and replaced with a single summary message to preserve context window tokens.")
            }

            RowLayout {
                visible: globalContextEnabledToggle.checked && globalContextAutoCompactToggle.checked
                spacing: Kirigami.Units.smallSpacing
                Kirigami.FormData.label: behaviorPage.translate("Compacting threshold:")
                Layout.maximumWidth: behaviorPage.fieldMaxWidth

                QQC2.SpinBox {
                    id: globalContextCompactThresholdSpin
                    from: 5
                    to: 100
                    value: behaviorPage.cfg_globalContextCompactThreshold
                    editable: true
                    onValueChanged: behaviorPage.cfg_globalContextCompactThreshold = value
                }

                QQC2.Label {
                    text: behaviorPage.translate("messages")
                }
            }

            QQC2.Label {
                visible: globalContextEnabledToggle.checked && globalContextAutoCompactToggle.checked
                Kirigami.FormData.label: ""
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: behaviorPage.translate("When the number of uncompacted messages exceeds this threshold, the widget automatically summarizes them in the background and replaces them with a single summary message to save context tokens.")
            }

            // ── Prompt Templates ───────────────────────────────────────────
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: behaviorPage.translate("Prompt Templates")
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                Kirigami.FormData.label: behaviorPage.translate("About:")
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: behaviorPage.translate("Save frequently used prompts. Use /template in chat to apply them.")
            }

            // Existing templates list
            Repeater {
                id: templatesRepeater
                model: {
                    try {
                        return JSON.parse(behaviorPage.cfg_promptTemplates || "[]");
                    } catch(e) { return []; }
                }

                delegate: RowLayout {
                    Layout.fillWidth: true
                    Layout.maximumWidth: behaviorPage.fieldMaxWidth
                    spacing: Kirigami.Units.smallSpacing
                    Kirigami.FormData.label: index === 0 ? behaviorPage.translate("Saved templates:") : ""

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: templateRow.implicitHeight + Kirigami.Units.smallSpacing * 2
                        radius: 4
                        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)
                        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.1)
                        border.width: 1

                        RowLayout {
                            id: templateRow
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.smallSpacing
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.Icon {
                                source: "document-edit"
                                Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                opacity: 0.6
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: modelData.name || ("Template " + (index + 1))
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                QQC2.Label {
                                    Layout.fillWidth: true
                                    text: modelData.prompt || ""
                                    elide: Text.ElideRight
                                    opacity: 0.65
                                    font: Kirigami.Theme.smallFont
                                }
                            }

                            QQC2.ToolButton {
                                icon.name: "edit-delete"
                                ToolTip.text: behaviorPage.translate("Delete template")
                                ToolTip.visible: hovered
                                onClicked: {
                                    let arr = [];
                                    try { arr = JSON.parse(behaviorPage.cfg_promptTemplates || "[]"); } catch(e) {}
                                    arr.splice(index, 1);
                                    behaviorPage.cfg_promptTemplates = JSON.stringify(arr);
                                }
                            }
                        }
                    }
                }
            }

            // Add new template
            ColumnLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                Kirigami.FormData.label: behaviorPage.translate("Add template:")
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    id: newTemplateName
                    Layout.fillWidth: true
                    placeholderText: behaviorPage.translate("Template name (e.g. \"Code Review\")")
                }

                QQC2.TextField {
                    id: newTemplatePrompt
                    Layout.fillWidth: true
                    placeholderText: behaviorPage.translate("System prompt text")
                }

                QQC2.Button {
                    id: addTemplateButton
                    text: behaviorPage.translate("Add Template")
                    icon.name: "list-add"
                    enabled: newTemplateName.text.trim() !== ""
                    onClicked: {
                        let arr = [];
                        try { arr = JSON.parse(behaviorPage.cfg_promptTemplates || "[]"); } catch(e) {}
                        arr.push({
                            "name": newTemplateName.text.trim(),
                            "prompt": newTemplatePrompt.text.trim()
                        });
                        behaviorPage.cfg_promptTemplates = JSON.stringify(arr);
                        newTemplateName.text = "";
                        newTemplatePrompt.text = "";
                    }
                }
            }

            // ── Voice & Audio ──────────────────────────────────────────────
            Kirigami.Separator {
                Kirigami.FormData.isSection: true
                Kirigami.FormData.label: behaviorPage.translate("Voice & Audio")
            }

            QQC2.Label {
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                Kirigami.FormData.label: behaviorPage.translate("About:")
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: behaviorPage.translate("Speech-to-text and text-to-speech. Experimental — requires Python venv with faster-whisper and kokoro.")
            }

            QQC2.CheckBox {
                id: voiceEnabledToggle
                Kirigami.FormData.label: behaviorPage.translate("Enable voice:")
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                checked: behaviorPage.cfg_voiceEnabled
                onCheckedChanged: behaviorPage.cfg_voiceEnabled = checked
                text: checked
                    ? behaviorPage.translate("Enabled — mic button appears in chat")
                    : behaviorPage.translate("Disabled")
            }

            QQC2.CheckBox {
                id: voiceTtsEnabledToggle
                visible: voiceEnabledToggle.checked
                Kirigami.FormData.label: behaviorPage.translate("Text-to-speech:")
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                checked: behaviorPage.cfg_voiceTtsEnabled
                onCheckedChanged: behaviorPage.cfg_voiceTtsEnabled = checked
                text: checked
                    ? behaviorPage.translate("Enabled — AI responses will be read aloud")
                    : behaviorPage.translate("Disabled")
            }

            QQC2.CheckBox {
                id: voiceAutoSendToggle
                visible: voiceEnabledToggle.checked
                Kirigami.FormData.label: behaviorPage.translate("Auto-send:")
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                checked: behaviorPage.cfg_voiceAutoSend
                onCheckedChanged: behaviorPage.cfg_voiceAutoSend = checked
                text: checked
                    ? behaviorPage.translate("Enabled — voice input sends automatically")
                    : behaviorPage.translate("Disabled — press Enter to send")
            }

            QQC2.Label {
                visible: voiceEnabledToggle.checked
                Kirigami.FormData.label: ""
                Layout.fillWidth: true
                Layout.maximumWidth: behaviorPage.fieldMaxWidth
                wrapMode: Text.Wrap
                opacity: 0.72
                font: Kirigami.Theme.smallFont
                text: behaviorPage.translate("Requires Python venv with faster-whisper, kokoro, sounddevice. Configure voice setup in the General settings page.")
            }

        } // end FormLayout

        // Bottom padding
        Item { Layout.preferredHeight: Kirigami.Units.gridUnit }
    }
}
