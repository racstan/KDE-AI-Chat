.pragma library
// Dictation (speech-to-text) settings: the helper payload built from the
// plasmoid config, and the one-time changes that carry older settings over.
// Plain JS (tested with node): no QML imports.

var KEYS = ["sttEnabled", "sttEngine", "sttLanguage", "sttRemoteUrl", "sttRemoteModel", "sttSpeechNoteModel"];

// The dictation engines that exist: Speech Note (the default) and an OpenAI-compatible speech server.
var ENGINES = ["speechnote", "remote"];

var DEFAULTS = {"sttEnabled": false, "sttEngine": "speechnote", "sttLanguage": "auto", "sttRemoteModel": "whisper-1"};

// The engine a saved id means now: Speech Note for every engine that was removed
// (faster-whisper, Parakeet, whisper.cpp, the custom command).
function migratedEngine(id) {
    id = String(id || "");
    return ENGINES.indexOf(id) >= 0 ? id : DEFAULTS.sttEngine;
}

// The stt* settings the helper's stt_* commands take (never a key: that is read from KWallet).
function payload(cfg) {
    var out = {};
    for (var i = 0; i < KEYS.length; i++) {
        var key = KEYS[i];
        var value = cfg ? cfg[key] : undefined;
        if (value === undefined || value === null || value === "")
            value = DEFAULTS.hasOwnProperty(key) ? DEFAULTS[key] : "";
        out[key] = key === "sttEnabled" ? value === true : key === "sttEngine" ? migratedEngine(value) : String(value);
    }
    return out;
}

// Changes that carry older settings over: always an engine that no longer exists
// becomes Speech Note; and once, the pre-1.4 voice settings (dictation stays on for
// people who had voice on, with their language). {} when there is nothing to do.
function migration(cfg) {
    if (!cfg)
        return {};
    var changes = {};
    if (cfg.sttEngine !== undefined && migratedEngine(cfg.sttEngine) !== String(cfg.sttEngine))
        changes.sttEngine = migratedEngine(cfg.sttEngine);
    if (cfg.sttSettingsMigrated === true)
        return changes;
    changes.sttSettingsMigrated = true;
    if (cfg.voiceEnabled === true && cfg.sttEnabled !== true)
        changes.sttEnabled = true;
    var language = String(cfg.voiceLanguage || "").trim();
    if (language)
        changes.sttLanguage = language;
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
