import re

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigSystemPrompt.qml", "r") as f:
    content = f.read()

# Add alias properties
prop_insert = """    property alias cfg_systemPrompt: customPromptArea.text
    property alias cfg_enableMemory: enableMemoryCheck.checked
    property alias cfg_userMemory: userMemoryArea.text
"""
content = content.replace("    property alias cfg_systemPrompt: customPromptArea.text", prop_insert)

# Update buildPreview
preview_old = """    function buildPreview() {
        return Api.buildSystemPrompt(sysInfo, cfg_systemPrompt, {
            sysInfoDateTime: cfg_sysInfoDateTime
        });
    }"""
preview_new = """    function buildPreview() {
        return Api.buildSystemPrompt(sysInfo, cfg_systemPrompt, {
            sysInfoDateTime: cfg_sysInfoDateTime,
            enableMemory: cfg_enableMemory,
            userMemory: cfg_userMemory
        });
    }"""
content = content.replace(preview_old, preview_new)

# Add UI components
ui_old = """        QQC2.TextArea {
            id: customPromptArea
            Kirigami.FormData.label: "Custom Instructions:"
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 6
            placeholderText: "Additional instructions for the LLM…"
            wrapMode: Text.Wrap
        }"""
ui_new = ui_old + """

        QQC2.CheckBox {
            id: enableMemoryCheck
            Kirigami.FormData.label: "Memory:"
            text: "Enable user memory"
        }

        QQC2.TextArea {
            id: userMemoryArea
            visible: enableMemoryCheck.checked
            Kirigami.FormData.label: "Memory Content:"
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 6
            placeholderText: "Facts or preferences you want the assistant to remember across all chats..."
            wrapMode: Text.Wrap
        }"""
content = content.replace(ui_old, ui_new)

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigSystemPrompt.qml", "w") as f:
    f.write(content)
