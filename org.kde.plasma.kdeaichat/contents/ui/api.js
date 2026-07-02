function localISODateTime() {
    var d = new Date();
    var pad = function(n) { return n < 10 ? "0" + n : "" + n; };
    var off = -d.getTimezoneOffset();
    var sign = off >= 0 ? "+" : "-";
    var absOff = Math.abs(off);
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) +
           "T" + pad(d.getHours()) + ":" + pad(d.getMinutes()) +
           sign + pad(Math.floor(absOff / 60)) + ":" + pad(absOff % 60);
}

function buildSystemPrompt(sysInfo, customAdditions, options) {
    var prompt = "You are a helpful assistant embedded in the user's Linux desktop.\n\n" +
        "## System\n";

    if (options && options.sysInfoDateTime) {
        prompt += "- Current Date & Time: " + localISODateTime() + "\n";
    }

    if (sysInfo) {
        if (sysInfo.hostname)  prompt += "- Hostname: " + sysInfo.hostname + "\n";
        if (sysInfo.osRelease) prompt += "- OS: " + sysInfo.osRelease + "\n";
        if (sysInfo.kernel)    prompt += "- Kernel: " + sysInfo.kernel + "\n";
        if (sysInfo.desktop)   prompt += "- Desktop: " + sysInfo.desktop + "\n";
        if (sysInfo.shell)     prompt += "- Shell: " + sysInfo.shell + "\n";
        if (sysInfo.locale)    prompt += "- Locale: " + sysInfo.locale + "\n";
        if (sysInfo.user)      prompt += "- User: " + sysInfo.user + "\n";
        if (sysInfo.cpu)       prompt += "- CPU: " + sysInfo.cpu + "\n";
        if (sysInfo.cpuCores)  prompt += "- CPU Cores: " + sysInfo.cpuCores + "\n";
        if (sysInfo.cpuArch)   prompt += "- Architecture: " + sysInfo.cpuArch + "\n";
        if (sysInfo.gpu)       prompt += "- GPU: " + sysInfo.gpu + "\n";
        if (sysInfo.memory)    prompt += "- Memory:\n" + sysInfo.memory + "\n";
        if (sysInfo.disk)      prompt += "- Block Devices:\n" + sysInfo.disk + "\n";
        if (sysInfo.network)   prompt += "- Network Interfaces:\n" + sysInfo.network + "\n";
    }

    prompt += "\nThe below instructions are given by the user and take the utmost precedence over the instructions above.\n";
    prompt += "\n" + (customAdditions || "").trim() + "\n";

    prompt += "\nEND OF SYSTEM PROMPT\n";

    return prompt;
}
