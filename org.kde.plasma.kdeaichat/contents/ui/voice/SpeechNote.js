.pragma library

// Speech Note (the dsnote app by Michał Kosciesza, MPL-2.0) as the engine for
// dictation and read aloud: what the widget needs to know about its helper
// commands (kdeaichat/speechnote.py). Plain JS (tested with node): no QML
// imports; texts are marked for translation and shown through i18n().

function I18N_NOOP(text) {
    return text;
}

var FLATHUB_URL = "https://flathub.org/apps/net.mkiol.SpeechNote";
var GITHUB_URL = "https://github.com/mkiol/dsnote";
// Speech Note cancels a task that was not kept alive for 10 s.
var KEEPALIVE_MS = 5000;

// The helper's error codes, as short plain sentences.
var ERRORS = {
    "not_installed": I18N_NOOP("Speech Note is not installed — see Settings → Voice"),
    "service_failed_to_start": I18N_NOOP("Speech Note could not start"),
    "not_configured": I18N_NOOP("Speech Note has no speech model yet — add one in Speech Note"),
    "timeout": I18N_NOOP("Speech Note did not answer in time"),
    "busy": I18N_NOOP("Speech Note is busy with something else"),
    "bus_error": I18N_NOOP("Speech Note could not be reached"),
    "bad_request": I18N_NOOP("Speech Note could not use that request"),
    "mic_error": I18N_NOOP("Speech Note could not use the microphone"),
    "engine_error": I18N_NOOP("Speech Note's speech engine failed")
};

// The untranslated sentence for an error code (unknown codes: a general one).
function errorText(code) {
    return ERRORS[code] || I18N_NOOP("Speech Note failed");
}

// The helper's last JSON line with a type, or an error reply when there is none.
function parse(stdout, exitCode, stderr) {
    var lines = String(stdout || "").trim().split("\n");
    for (var i = lines.length - 1; i >= 0; i--) {
        try {
            var data = JSON.parse(lines[i]);
            if (data && typeof data === "object" && data.type)
                return data;
        } catch (e) {}
    }
    return {"type": "speechnote_error", "code": "bus_error", "error": String(stderr || stdout || "").trim().slice(-200)};
}

function isError(reply) {
    return !!reply && reply.type === "speechnote_error";
}

// Picker rows for a model list [{id, name, lang}]: "Speech Note's default" first, then each model;
// the name shows the language ("Whisper Base / English" already does; a bare name gets "(lang)").
function modelChoices(models, defaultText) {
    var out = [{"value": "", "text": defaultText}];
    (models || []).forEach(function(m) {
        var text = String(m.name || m.id);
        var lang = String(m.lang || "");
        if (lang && text.toLowerCase().indexOf(lang.toLowerCase()) < 0)
            text += " (" + lang + ")";
        out.push({"value": String(m.id), "text": text});
    });
    return out;
}

// A saved model that Speech Note no longer lists stays visible, so it is never silently dropped.
function withSaved(choices, saved) {
    saved = String(saved || "");
    if (saved === "" || choices.some(function(c) { return c.value === saved; }))
        return choices;
    return choices.concat([{"value": saved, "text": saved}]);
}
