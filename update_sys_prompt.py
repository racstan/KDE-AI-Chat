import re

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigSystemPrompt.qml", "r") as f:
    content = f.read()

# Add import
content = content.replace("import org.kde.kcmutils as KCM\n", "import org.kde.kcmutils as KCM\nimport org.kde.plasma.plasma5support 2.0 as P5Support\n")

# Replace buildPreview
new_build_preview = """
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
        if (cfg_sysInfoGPU)      cmds.push("bash -c \\\"lspci -nn | grep -iE 'vga|3d|display'\\\"");
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

    function buildPreview() {
        return Api.buildSystemPrompt(sysInfo, cfg_systemPrompt, {
            sysInfoDateTime: cfg_sysInfoDateTime
        });
    }

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
                    case "bash -c \\\"lspci -nn | grep -iE 'vga|3d|display'\\\"": info.gpu = output || "unknown"; break;
                    case "ip -br addr show": info.network = output; break;
                    case "echo $LANG": info.locale = output; break;
                }
                
                sysInfo = info;
                sysInfoPending--;
                disconnectSource(source);
            }
        }
    }
"""

content = re.sub(r'function buildPreview\(\) \{.*?\n    \}', new_build_preview, content, flags=re.DOTALL)

with open("org.kde.plasma.kdeaichat/contents/ui/ConfigSystemPrompt.qml", "w") as f:
    f.write(content)
