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
    // Static system prompt: identity + sysinfo + custom instructions.
    // Memory is intentionally NOT included here so it can be sent as a
    // separate (per-turn, non-cached) system block in the API payload.
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

function buildMemoryBlock(options) {
    // Returns the per-turn memory block as a string, or "" when memory
    // is disabled / empty. Callers add this as a separate system message
    // (or system array entry) so providers with prompt caching can cache
    // the static prompt and re-send only the memory.
    if (!options || !options.enableMemory)
        return "";
    var mem = (options.userMemory || "").trim();
    if (mem === "")
        return "";
    return "## User Memory\n" +
           "The following are important facts or preferences the user wants you to remember:\n" +
           mem;
}

function buildFullSystemPrompt(sysInfo, customAdditions, options) {
    // Settings-page preview only. The actual API payload uses
    // buildSystemPrompt() and buildMemoryBlock() separately, so the
    // static prompt can be cached and the memory is re-sent per turn.
    // We render both blocks with clear visual dividers so the user can
    // see what will be sent as two distinct system messages.
    var prompt = buildSystemPrompt(sysInfo, customAdditions, options);
    var mem = buildMemoryBlock(options);
    if (mem === "")
        return prompt;
    return "═════ System Prompt (sent every request, provider-cached) ═════\n" +
           prompt + "\n" +
           "═════ User Memory (sent every turn, fresh each request) ═════\n" +
           mem + "\n";
}
