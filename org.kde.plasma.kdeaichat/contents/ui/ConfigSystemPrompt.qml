import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support 2.0 as P5Support

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
    property alias cfg_enableMemory: enableMemoryCheck.checked
    property alias cfg_userMemory: userMemoryArea.text


    
    property var sysInfo: ({})
    property int sysInfoPending: 0
    property var pendingSysInfoCommands: ({})

    function triggerPreviewUpdate() {
        var cmds = [];
        if (cfg_sysInfoOS)       cmds.push("cat /etc/os-release");
        if (cfg_sysInfoShell)    cmds.push("echo $SHELL");
        if (cfg_sysInfoHostname) cmds.push("hostname");
        if (cfg_sysInfoKernel)   cmds.push("uname -a");
        if (cfg_sysInfoDesktop)  cmds.push("echo $XDG_CURRENT_DESKTOP");
        if (cfg_sysInfoUser)     cmds.push("whoami");
        if (cfg_sysInfoCPU)      cmds.push("lscpu");
        if (cfg_sysInfoMemory)   cmds.push("free -h");
        if (cfg_sysInfoGPU)      cmds.push("bash -c \"lspci -nn | grep -iE 'vga|3d|display'\"");
        if (cfg_sysInfoDisk)     cmds.push("lsblk -o NAME,SIZE,TYPE,MOUNTPOINT");
        if (cfg_sysInfoNetwork)  cmds.push("ip -br addr show");
        if (cfg_sysInfoLocale)   cmds.push("echo $LANG");

        if (cmds.length === 0) {
            sysInfo = {};
            return;
        }

        var newPending = {};
        for (var i = 0; i < cmds.length; i++) {
            newPending[cmds[i]] = true;
            sysInfoDs.connectSource(cmds[i]);
        }
        pendingSysInfoCommands = newPending;
        sysInfoPending = cmds.length;
    }

    onCfg_sysInfoOSChanged: triggerPreviewUpdate()
    onCfg_sysInfoShellChanged: triggerPreviewUpdate()
    onCfg_sysInfoHostnameChanged: triggerPreviewUpdate()
    onCfg_sysInfoKernelChanged: triggerPreviewUpdate()
    onCfg_sysInfoDesktopChanged: triggerPreviewUpdate()
    onCfg_sysInfoUserChanged: triggerPreviewUpdate()
    onCfg_sysInfoCPUChanged: triggerPreviewUpdate()
    onCfg_sysInfoMemoryChanged: triggerPreviewUpdate()
    onCfg_sysInfoGPUChanged: triggerPreviewUpdate()
    onCfg_sysInfoDiskChanged: triggerPreviewUpdate()
    onCfg_sysInfoNetworkChanged: triggerPreviewUpdate()
    onCfg_sysInfoLocaleChanged: triggerPreviewUpdate()

    Component.onCompleted: triggerPreviewUpdate()



    P5Support.DataSource {
        id: sysInfoDs
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            var output = data["stdout"] ? data["stdout"].trim() : "";
            if (pendingSysInfoCommands[source]) {
                var pending = pendingSysInfoCommands;
                delete pending[source];
                pendingSysInfoCommands = pending;
                
                var info = Object.assign({}, sysInfo);
                
                switch (source) {
                    case "hostname": info.hostname = output; break;
                    case "uname -a": info.kernel = output; break;
                    case "whoami": info.user = output; break;
                    case "echo $SHELL": info.shell = output; break;
                    case "cat /etc/os-release":
                        var lines = output.split("\\n");
                        for (var i = 0; i < lines.length; i++) {
                            if (lines[i].indexOf("PRETTY_NAME=") === 0) {
                                info.osRelease = lines[i].replace("PRETTY_NAME=", "").replace(/"/g, "");
                                break;
                            }
                        }
                        if (!info.osRelease) info.osRelease = output.substring(0, 100);
                        break;
                    case "echo $XDG_CURRENT_DESKTOP": info.desktop = output; break;
                    case "lscpu":
                        var cpuLines = output.split("\\n");
                        var cpuInfo = {};
                        for (var j = 0; j < cpuLines.length; j++) {
                            var parts = cpuLines[j].split(":");
                            if (parts.length >= 2) {
                                var key = parts[0].trim();
                                var val = parts.slice(1).join(":").trim();
                                if (["Model name", "CPU(s)", "Architecture", "Thread(s) per core", "Core(s) per socket"].indexOf(key) !== -1) {
                                    cpuInfo[key] = val;
                                }
                            }
                        }
                        info.cpu = cpuInfo["Model name"] || "unknown";
                        info.cpuCores = (cpuInfo["CPU(s)"] || "?") + " threads, " + (cpuInfo["Core(s) per socket"] || "?") + " cores";
                        info.cpuArch = cpuInfo["Architecture"] || "";
                        break;
                    case "free -h": info.memory = output; break;
                    case "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT": info.disk = output; break;
                    case "bash -c \"lspci -nn | grep -iE 'vga|3d|display'\"": info.gpu = output || "unknown"; break;
                    case "ip -br addr show": info.network = output; break;
                    case "echo $LANG": info.locale = output; break;
                }
                
                sysInfo = info;
                sysInfoPending--;
                disconnectSource(source);
            }
        }
    }


    Kirigami.FormLayout {
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
            id: customPromptScroll
            Kirigami.FormData.label: "Custom Instructions:"
            Layout.fillWidth: true
            implicitHeight: Kirigami.Units.gridUnit * 6
            Layout.preferredHeight: Kirigami.Units.gridUnit * 6
            clip: true

            QQC2.TextArea {
                id: customPromptArea
                placeholderText: "Additional instructions for the LLM…"
                wrapMode: Text.Wrap
                width: customPromptScroll.width
            }
        }

        QQC2.ScrollView {
            id: previewScroll
            Kirigami.FormData.label: "System Prompt Preview:"
            Layout.fillWidth: true
            implicitHeight: Kirigami.Units.gridUnit * 6
            Layout.preferredHeight: Kirigami.Units.gridUnit * 6
            clip: true

            QQC2.TextArea {
                readOnly: true
                wrapMode: Text.Wrap
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: Api.buildSystemPrompt(configPage.sysInfo, configPage.cfg_systemPrompt, { sysInfoDateTime: configPage.cfg_sysInfoDateTime })
                width: previewScroll.width
            }
        }

        Kirigami.Heading {
            Kirigami.FormData.isSection: true
            text: "Memory"
            Layout.topMargin: Kirigami.Units.largeSpacing
        }

        QQC2.CheckBox {
            id: enableMemoryCheck
            text: "Enable user memory"
        }

        QQC2.ScrollView {
            id: userMemoryScroll
            visible: enableMemoryCheck.checked
            Kirigami.FormData.label: "Memory Content:"
            Layout.fillWidth: true
            implicitHeight: Kirigami.Units.gridUnit * 6
            Layout.preferredHeight: Kirigami.Units.gridUnit * 6
            clip: true

            QQC2.TextArea {
                id: userMemoryArea
                placeholderText: "Facts or preferences you want the assistant to remember across all chats..."
                wrapMode: Text.Wrap
                width: userMemoryScroll.width
            }
        }

        QQC2.ScrollView {
            id: memoryPreviewScroll
            visible: enableMemoryCheck.checked
            Kirigami.FormData.label: "Memory Preview:"
            Layout.fillWidth: true
            implicitHeight: Kirigami.Units.gridUnit * 4
            Layout.preferredHeight: Kirigami.Units.gridUnit * 4
            clip: true

            QQC2.TextArea {
                readOnly: true
                wrapMode: Text.Wrap
                font.family: "monospace"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                text: Api.buildMemoryBlock({ enableMemory: configPage.cfg_enableMemory, userMemory: configPage.cfg_userMemory })
                width: memoryPreviewScroll.width
            }
        }
    }
}

