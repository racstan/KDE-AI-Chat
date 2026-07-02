import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

import "api.js" as Api

KCM.SimpleKCM {
    id: configPage

    property alias cfg_sysInfoOS: sysInfoOSCheck.checked
    property alias cfg_sysInfoShell: sysInfoShellCheck.checked
    property alias cfg_sysInfoHostname: sysInfoHostnameCheck.checked
    property alias cfg_sysInfoKernel: sysInfoKernelCheck.checked
    property alias cfg_sysInfoDesktop: sysInfoDesktopCheck.checked
    property alias cfg_sysInfoUser: sysInfoUserCheck.checked
    property alias cfg_sysInfoCPU: sysInfoCPUCheck.checked
    property alias cfg_sysInfoMemory: sysInfoMemoryCheck.checked
    property alias cfg_sysInfoGPU: sysInfoGPUCheck.checked
    property alias cfg_sysInfoDisk: sysInfoDiskCheck.checked
    property alias cfg_sysInfoNetwork: sysInfoNetworkCheck.checked
    property alias cfg_sysInfoLocale: sysInfoLocaleCheck.checked
    property alias cfg_sysInfoDateTime: sysInfoDateTimeCheck.checked
    property alias cfg_systemPrompt: customPromptArea.text

    function buildPreview() {
        var info = {};
        if (cfg_sysInfoOS)       info.osRelease  = "<OS name>";
        if (cfg_sysInfoShell)    info.shell      = "<shell>";
        if (cfg_sysInfoHostname) info.hostname   = "<hostname>";
        if (cfg_sysInfoKernel)   info.kernel     = "<kernel>";
        if (cfg_sysInfoDesktop)  info.desktop    = "<desktop>";
        if (cfg_sysInfoUser)     info.user       = "<username>";
        if (cfg_sysInfoCPU) {
            info.cpu      = "<CPU model>";
            info.cpuCores = "<cores>";
            info.cpuArch  = "<arch>";
        }
        if (cfg_sysInfoMemory)   info.memory  = "<memory>";
        if (cfg_sysInfoGPU)      info.gpu     = "<GPU name>";
        if (cfg_sysInfoDisk)     info.disk    = "<lsblk output>";
        if (cfg_sysInfoNetwork)  info.network = "<network>";
        if (cfg_sysInfoLocale)   info.locale  = "<locale>";
        return Api.buildSystemPrompt(info, cfg_systemPrompt, {
            sysInfoDateTime: cfg_sysInfoDateTime
        });
    }

    Kirigami.FormLayout {
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

        QQC2.TextArea {
            id: customPromptArea
            Kirigami.FormData.label: "Custom Instructions:"
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 6
            placeholderText: "Additional instructions for the LLM…"
            wrapMode: Text.Wrap
        }

        QQC2.TextArea {
            Kirigami.FormData.label: "Preview:"
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 14
            readOnly: true
            wrapMode: Text.Wrap
            font.family: "monospace"
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            text: configPage.buildPreview()
        }
    }
}
