import re

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigSystemPrompt.qml", "r") as f:
    content = f.read()

# Replace the entire Kirigami.FormLayout block
form_old = re.search(r'    Kirigami.FormLayout \{.*\}', content, re.DOTALL).group(0)

form_new = """    Kirigami.FormLayout {
        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            text: "System Prompt"
        }

        GridLayout {
            Kirigami.FormData.label: "System Info:"
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: 0

            QQC2.CheckBox { id: sysInfoOSCheck; text: "OS" }
            QQC2.CheckBox { id: sysInfoShellCheck; text: "Shell" }
            QQC2.CheckBox { id: sysInfoHostnameCheck; text: "Hostname" }
            QQC2.CheckBox { id: sysInfoKernelCheck; text: "Kernel" }
            QQC2.CheckBox { id: sysInfoDesktopCheck; text: "Desktop" }
            QQC2.CheckBox { id: sysInfoUserCheck; text: "User" }
            QQC2.CheckBox { id: sysInfoCPUCheck; text: "CPU" }
            QQC2.CheckBox { id: sysInfoMemoryCheck; text: "Memory" }
            QQC2.CheckBox { id: sysInfoGPUCheck; text: "GPU" }
            QQC2.CheckBox { id: sysInfoDiskCheck; text: "Block Devices" }
            QQC2.CheckBox { id: sysInfoNetworkCheck; text: "Network" }
            QQC2.CheckBox { id: sysInfoLocaleCheck; text: "Locale" }
            QQC2.CheckBox { id: sysInfoDateTimeCheck; text: "Date/Time" }
        }

        QQC2.ScrollView {
            Kirigami.FormData.label: "Custom Instructions:"
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 6
            Layout.maximumHeight: Kirigami.Units.gridUnit * 6

            QQC2.TextArea {
                id: customPromptArea
                placeholderText: "Additional instructions for the LLM…"
                wrapMode: Text.Wrap
            }
        }

        QQC2.ScrollView {
            Kirigami.FormData.label: "Preview:"
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 10
            Layout.maximumHeight: Kirigami.Units.gridUnit * 10

            QQC2.TextArea {
                readOnly: true
                wrapMode: Text.Wrap
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: configPage.buildPreview()
            }
        }

        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            text: "Memory"
        }

        QQC2.CheckBox {
            id: enableMemoryCheck
            Kirigami.FormData.label: "Enable:"
            text: "Enable user memory"
        }

        QQC2.ScrollView {
            visible: enableMemoryCheck.checked
            Kirigami.FormData.label: "Memory Content:"
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 6
            Layout.maximumHeight: Kirigami.Units.gridUnit * 6

            QQC2.TextArea {
                id: userMemoryArea
                placeholderText: "Facts or preferences you want the assistant to remember across all chats..."
                wrapMode: Text.Wrap
            }
        }
    }
}
"""

content = content.replace(form_old, form_new)

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigSystemPrompt.qml", "w") as f:
    f.write(content)
