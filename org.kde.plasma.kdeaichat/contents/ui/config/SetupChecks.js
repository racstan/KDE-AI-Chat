.pragma library

// "Check setup": what the current settings need, in plain words with the fix.
//
// Two halves make the list (config/SetupCheck.qml runs both):
// - directChecks() here, from the provider list and the KWallet state the
//   widget already has (no key is read for it: only whether one is there);
// - the helper's `setup_check` (kdeaichat/diagnostics.py) for what needs the
//   computer: local servers, OpenCode, Pi, attachment tools, voice, schedules.
//   helperPayload() builds its payload from the settings (never a secret).
// Both give rows {id, area, status: ok|warn|error, code, args}; MESSAGES turns
// a code into a sentence and a one-line fix, with %1… filled from args. The
// texts are marked with I18N_NOOP and the QML shows them through i18n().
// Plain JavaScript, so tests run it in node.

function I18N_NOOP(text) {
    return text;
}

var MESSAGES = {
    // KWallet and the provider list (directChecks)
    "wallet-ready": [I18N_NOOP("KWallet is open, so API keys can be read."), ""],
    "wallet-disabled": [I18N_NOOP("KWallet is turned off, so API keys can't be read."),
                        I18N_NOOP("Turn it on in System Settings → KDE Wallet.")],
    "wallet-denied": [I18N_NOOP("KWallet is locked or refused access."),
                      I18N_NOOP("Unlock the wallet when it asks, or allow KDE AI Chat in KWallet Manager.")],
    "wallet-unavailable": [I18N_NOOP("KWallet isn't running, so API keys can't be read."),
                           I18N_NOOP("Check that KDE Wallet (kwalletd6) is installed and running.")],
    "wallet-unknown": [I18N_NOOP("KWallet hasn't answered yet."), I18N_NOOP("Check again in a moment.")],
    "no-providers": [I18N_NOOP("No provider is set up."), I18N_NOOP("Add one under Settings → Connection.")],
    "provider-ok": [I18N_NOOP("%1 is set up."), ""],
    "key-missing": [I18N_NOOP("%1 has no API key."), I18N_NOOP("Add the key in Settings → Connection; it is kept in KWallet.")],
    "url-bad": [I18N_NOOP("The address of %1 isn't a valid web address: %2"),
                I18N_NOOP("Correct it in the provider's settings; it starts with https:// or http://.")],
    "url-placeholder": [I18N_NOOP("The address of %1 still contains a placeholder."),
                        I18N_NOOP("Replace YOUR_ACCOUNT_ID in the address with your account id.")],
    "model-missing": [I18N_NOOP("%1 has no model chosen."), I18N_NOOP("Pick one in the provider's settings.")],
    // Local servers
    "local-ok": [I18N_NOOP("%1 answers at %2."), ""],
    "local-needs-key": [I18N_NOOP("%1 answers at %2 and asks for a key."), ""],
    "local-refused": [I18N_NOOP("Nothing answers at %2, so %1 isn't running there."),
                      I18N_NOOP("Start %1 (for Ollama: ollama serve), or correct the address.")],
    "local-timeout": [I18N_NOOP("%1 at %2 didn't answer in time."),
                      I18N_NOOP("Check that the computer at that address is on and the server isn't stuck.")],
    "local-not-found": [I18N_NOOP("%1 answers at %2, but has no model list there (HTTP 404)."),
                        I18N_NOOP("Check the address: it usually ends in /v1.")],
    "local-http": [I18N_NOOP("%1 at %2 answered with an error (HTTP %3)."), I18N_NOOP("Check the address and the server's log.")],
    "local-no-host": [I18N_NOOP("The computer named in %2 can't be found."), I18N_NOOP("Correct the address of %1.")],
    "local-unreachable": [I18N_NOOP("%1 can't be reached at %2: %3"), I18N_NOOP("Check the address and your network.")],
    // OpenCode
    "opencode-running": [I18N_NOOP("OpenCode answers at %1 (version %2)."), ""],
    "opencode-running-plain": [I18N_NOOP("OpenCode answers at %1."), ""],
    "opencode-starts": [I18N_NOOP("OpenCode is installed (%2) and starts by itself at %1 when you send."), ""],
    "opencode-starts-plain": [I18N_NOOP("OpenCode is installed and starts by itself at %1 when you send."), ""],
    "opencode-missing": [I18N_NOOP("OpenCode isn't installed: there is no opencode program."),
                         I18N_NOOP("Install it (see opencode.ai), then check again.")],
    "opencode-unreachable": [I18N_NOOP("Nothing answers at %1."),
                             I18N_NOOP("Start opencode serve there, or correct the server address above.")],
    "opencode-timeout": [I18N_NOOP("OpenCode at %1 didn't answer in time."), I18N_NOOP("Check that the server isn't stuck.")],
    "opencode-not-server": [I18N_NOOP("Something answers at %1, but it isn't an OpenCode server (HTTP %2)."),
                            I18N_NOOP("Check the port in the server address.")],
    "opencode-bad-url": [I18N_NOOP("The OpenCode server address isn't valid: %1"),
                         I18N_NOOP("Use an address like http://127.0.0.1:4096.")],
    // Pi
    "pi-ok": [I18N_NOOP("Pi is installed (%2)."), ""],
    "pi-ok-plain": [I18N_NOOP("Pi is installed."), ""],
    "pi-missing": [I18N_NOOP("Pi isn't installed: there is no pi program."),
                   I18N_NOOP("Install the Pi coding agent, then check again.")],
    "pi-bridge-running": [I18N_NOOP("The Pi bridge is running."), ""],
    "pi-bridge-starts": [I18N_NOOP("The Pi bridge starts by itself when you send."), ""],
    "pi-bridge-broken": [I18N_NOOP("The Pi bridge can't start: %1."),
                         I18N_NOOP("Reinstall the widget, or see pi-bridge.log in ~/.local/share/kdeaichat.")],
    // Attachments
    "pdf-ok": [I18N_NOOP("PDF files can be attached."), ""],
    "pdf-missing": [I18N_NOOP("PDF files can't be read: pdftotext is missing."),
                    I18N_NOOP("Install poppler-utils (Arch: poppler).")],
    "docx-ok": [I18N_NOOP("Word files can be attached."), ""],
    "docx-basic": [I18N_NOOP("Word files are read with a simpler built-in reader: pandoc is missing."),
                   I18N_NOOP("Install pandoc for better results.")],
    // Dictation
    "stt-bad-settings": [I18N_NOOP("A dictation setting isn't valid: %1"), I18N_NOOP("Correct it in Settings → Voice.")],
    "stt-recorder-ok": [I18N_NOOP("The microphone is recorded with %1."), ""],
    "stt-no-recorder": [I18N_NOOP("There is no recording program (pw-record, parecord or arecord)."),
                        I18N_NOOP("Install PipeWire's tools (pipewire-tools or pipewire-utils).")],
    "stt-fw-missing": [I18N_NOOP("%1 isn't installed."),
                       I18N_NOOP("Install it in Settings → Voice; the download size is shown first.")],
    "stt-no-venv": [I18N_NOOP("%1 can't be installed: Python's venv module is missing."),
                    I18N_NOOP("Install python3-venv, or pick another dictation engine.")],
    "stt-model-missing": [I18N_NOOP("The speech model %1 isn't downloaded yet."), I18N_NOOP("Download it in Settings → Voice.")],
    "stt-model-folder-missing": [I18N_NOOP("The speech model folder %1 doesn't exist."), I18N_NOOP("Pick another model in Settings → Voice.")],
    "stt-whispercpp-missing": [I18N_NOOP("whisper.cpp isn't installed: there is no whisper-cli program."),
                               I18N_NOOP("Install whisper.cpp, or enter its program in Settings → Voice.")],
    "stt-whispercpp-model": [I18N_NOOP("whisper.cpp has no model file."), I18N_NOOP("Pick a ggml model file in Settings → Voice.")],
    "stt-remote-url": [I18N_NOOP("Dictation has no speech server address."), I18N_NOOP("Enter it in Settings → Voice.")],
    "stt-command-bad": [I18N_NOOP("The dictation command can't run: %1"), I18N_NOOP("Correct it in Settings → Voice.")],
    "stt-ready": [I18N_NOOP("Dictation with %1 is ready."), ""],
    // Read aloud
    "tts-piper-missing": [I18N_NOOP("Piper isn't installed: there is no piper program."),
                          I18N_NOOP("Install Piper, or pick another read-aloud engine in Settings → Voice.")],
    "tts-piper-voice": [I18N_NOOP("The Piper voice file isn't there: %1"), I18N_NOOP("Pick a voice file in Settings → Voice.")],
    "tts-remote-url": [I18N_NOOP("Read aloud has no valid speech server address."), I18N_NOOP("Enter it in Settings → Voice.")],
    "tts-command-bad": [I18N_NOOP("The read-aloud command's program isn't found."), I18N_NOOP("Correct it in Settings → Voice.")],
    "tts-speechd-missing": [I18N_NOOP("Speech Dispatcher isn't installed, so the system voices may be silent."),
                            I18N_NOOP("Install speech-dispatcher and espeak-ng.")],
    "tts-qt-engine": [I18N_NOOP("Read aloud uses the %1 speech plugin; Settings → Voice lists the voices it finds."), ""],
    "tts-ready": [I18N_NOOP("Read aloud with %1 is ready."), ""],
    // Schedules
    "sched-none": [I18N_NOOP("No schedule is waiting to run."), ""],
    "sched-ok": [I18N_NOOP("%1 schedules have their timers."), ""],
    "sched-unreadable": [I18N_NOOP("The schedule file can't be read."), I18N_NOOP("Open Settings → Schedules to see what's wrong.")],
    "sched-no-systemd": [I18N_NOOP("systemd's user service manager isn't available, so schedules can't run."),
                         I18N_NOOP("Schedules need systemctl --user (a systemd session).")],
    "sched-timers-missing": [I18N_NOOP("%1 schedules are missing their timer, so they won't run."),
                             I18N_NOOP("Press Recreate timers.")],
    "check-failed": [I18N_NOOP("One check failed: %1"), ""]
};

// Rows with an action button: the action's id (config/SetupCheck.qml runs it).
var ACTIONS = {"sched-timers-missing": "sync-schedules"};

function row(id, area, status, code, args) {
    return {"id": id, "area": area, "status": status, "code": code, "args": (args || []).map(String)};
}

function _validUrl(url) {
    var value = String(url || "").trim();
    if (!/^https?:\/\/[^\s\/?#@<>"'`]+/i.test(value) || /[\s\u0000-\u001f\u007f]/.test(value))
        return false;
    return true;
}

// entries: the chat providers [{id, name, baseUrl, model, local}] (image
// services left out); walletStatus/walletKeys: store/Wallet.qml status and keys;
// defaultId: the default provider, the only one whose missing model is
// mentioned (chats pick their own model). Local providers' addresses are
// checked by the helper (helperPayload).
function directChecks(entries, walletStatus, walletKeys, defaultId) {
    var out = [];
    var list = entries || [];
    if (list.length === 0)
        return [row("providers", "connection", "error", "no-providers")];
    var needsWallet = list.some(function(e) { return !e.local; });
    var walletUsable = walletStatus === "ready";
    if (needsWallet) {
        var walletCode = {"ready": "wallet-ready", "disabled": "wallet-disabled", "denied": "wallet-denied",
                          "unavailable": "wallet-unavailable"}[walletStatus] || "wallet-unknown";
        out.push(row("wallet", "connection", walletUsable ? "ok" : (walletCode === "wallet-unknown" ? "warn" : "error"), walletCode));
    }
    list.forEach(function(e) {
        var id = "provider:" + e.id;
        if (/YOUR_ACCOUNT_ID/.test(e.baseUrl || ""))
            out.push(row(id, "connection", "error", "url-placeholder", [e.name]));
        else if (!_validUrl(e.baseUrl))
            out.push(row(id, "connection", "error", "url-bad", [e.name, e.baseUrl || ""]));
        else if (!e.local && walletUsable && !(walletKeys || {})[e.id])
            out.push(row(id, "connection", "error", "key-missing", [e.name]));
        else if (!String(e.model || "").trim() && e.id === defaultId)
            out.push(row(id, "connection", "warn", "model-missing", [e.name]));
        else if (!e.local)
            out.push(row(id, "connection", "ok", "provider-ok", [e.name]));
    });
    return out;
}

// The helper's payload. mode: direct|opencode|pi; cfg: plasmoid.configuration
// (or a plain object with the same names); entries as in directChecks.
var STT_KEYS = ["sttEnabled", "sttEngine", "sttModel", "sttDevice", "sttLanguage", "sttWhisperCppBinary",
                "sttWhisperCppModel", "sttWhisperCppServer", "sttRemoteUrl", "sttRemoteModel", "sttCommand"];
var TTS_KEYS = ["voiceTtsEnabled", "voiceTtsEngine", "voiceTtsPiperModel", "voiceTtsRemoteUrl", "voiceTtsCommand"];

function _pick(cfg, keys) {
    var out = {};
    keys.forEach(function(k) {
        var v = cfg ? cfg[k] : undefined;
        if (v !== undefined && v !== null)
            out[k] = typeof v === "boolean" ? v : String(v);
    });
    return out;
}

function helperPayload(mode, cfg, entries, openCodeUrl) {
    var endpoints = mode === "direct" ? (entries || []).filter(function(e) { return e.local && _validUrl(e.baseUrl); })
        .map(function(e) { return {"id": e.id, "name": e.name, "url": e.baseUrl}; }) : [];
    return {"mode": mode, "openCodeUrl": String(openCodeUrl !== undefined ? openCodeUrl : (cfg && cfg.openCodeUrl) || ""),
            "endpoints": endpoints, "stt": _pick(cfg, STT_KEYS), "tts": _pick(cfg, TTS_KEYS)};
}

// [text template, fix template] for a row; unknown codes show the code.
function message(r) {
    return MESSAGES[r.code] || [r.code + " %1 %2", ""];
}

function counts(rows) {
    var c = {"ok": 0, "warn": 0, "error": 0};
    (rows || []).forEach(function(r) { c[r.status] = (c[r.status] || 0) + 1; });
    return c;
}

// The helper's stdout -> rows (a "check-failed" row when it can't be read).
function parseHelper(stdout, exitCode) {
    try {
        var data = JSON.parse(String(stdout || "").trim().split("\n").pop());
        if (exitCode === 0 && data && Array.isArray(data.checks))
            return data.checks.filter(function(r) { return r && typeof r.code === "string"; });
    } catch (e) {
    }
    return [row("helper", "other", "warn", "check-failed", [String(stdout || "").trim().substring(0, 200) || "helper"])];
}
