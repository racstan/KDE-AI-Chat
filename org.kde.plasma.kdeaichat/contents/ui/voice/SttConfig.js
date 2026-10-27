.pragma library
// Dictation (speech-to-text) settings: the helper payload built from the
// plasmoid config, and the one-time copy of the old voice* settings.
// Plain JS (tested with node): no QML imports.

var KEYS = ["sttEnabled", "sttEngine", "sttModel", "sttParakeetModel", "sttDevice", "sttLanguage", "sttWhisperCppBinary",
            "sttWhisperCppModel", "sttWhisperCppServer", "sttRemoteUrl", "sttRemoteModel", "sttCommand",
            "sttIdleMinutes"];

var DEFAULTS = {"sttEnabled": false, "sttEngine": "parakeet", "sttModel": "small",
                "sttParakeetModel": "parakeet-unified-en-0.6b", "sttDevice": "auto",
                "sttLanguage": "auto", "sttRemoteModel": "whisper-1", "sttIdleMinutes": 5};

// The stt* settings the helper's stt_* commands take (never a key: that is read from KWallet).
function payload(cfg) {
    var out = {};
    for (var i = 0; i < KEYS.length; i++) {
        var key = KEYS[i];
        var value = cfg ? cfg[key] : undefined;
        if (value === undefined || value === null || value === "")
            value = DEFAULTS.hasOwnProperty(key) ? DEFAULTS[key] : "";
        out[key] = key === "sttEnabled" ? value === true : key === "sttIdleMinutes" ? Number(value) : String(value);
    }
    return out;
}

// Changes that carry the pre-1.4 voice settings over, once: dictation stays on
// for people who had voice on, with their model, model folder, language and GPU
// choice. Someone who had picked a Whisper model keeps faster-whisper (Parakeet
// is the default otherwise). {} when already done.
function migration(cfg) {
    if (!cfg || cfg.sttSettingsMigrated === true)
        return {};
    var changes = {"sttSettingsMigrated": true};
    if (cfg.voiceEnabled === true && cfg.sttEnabled !== true)
        changes.sttEnabled = true;
    var folder = String(cfg.voiceSttModelPath || "").trim();
    var model = String(cfg.voiceSttModel || "").trim();
    if (folder)
        changes.sttModel = folder;
    else if (model)
        changes.sttModel = model;
    if (folder || model)
        changes.sttEngine = "faster-whisper";
    var language = String(cfg.voiceLanguage || "").trim();
    if (language)
        changes.sttLanguage = language;
    if (cfg.voiceGpuEnabled === true)
        changes.sttDevice = "cuda";
    return changes;
}

function applyMigration(cfg) {
    var changes = migration(cfg);
    for (var key in changes) {
        try {
            cfg[key] = changes[key];
        } catch (e) {}   // a stand-in configuration without that key (tests)
    }
    return changes;
}
