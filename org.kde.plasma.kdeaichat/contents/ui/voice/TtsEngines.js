.pragma library

// The read-aloud (text-to-speech) engines: what each one is called, how it
// speaks and which settings it has. Settings → Voice (config/TtsOptions.qml)
// builds its form from `options`, and voice/ReadAloud.qml runs the engine,
// so adding an engine means one entry here, its main.xml keys and (for a new
// `kind`) a runner; the page itself doesn't change.
//
// kind "qt":   QtTextToSpeech in the widget process (`plugin` is the Qt
//              engine), with stop and pause; voices come from the plugin.
// kind "file": the helper (kdeaichat/tts.py) writes a WAV per chunk and the
//              widget plays it (voice/FileSpeech.qml), with stop and pause.
//
// Option types: "language" and "voice" (lists from the Qt engine), "rate" and
// "pitch" (-1 … 1), "speed" (0.5 … 2), "int", "text", "url", "file" (a path,
// with `filter`), "command" (a template), "secret" (KWallet entry `entry`,
// never a setting). `key` is the main.xml entry; `def` its default.

// Marks text for translation (xgettext -kI18N_NOOP); the QML shows it
// through i18n().
function I18N_NOOP(text) {
    return text;
}

var engines = [
    {id: "system", kind: "qt", plugin: "speechd", label: I18N_NOOP("System voices"),
     note: I18N_NOOP("Speech Dispatcher: espeak-ng and any voice installed for it. Nothing to set up."),
     options: [
         {key: "voiceTtsSystemLanguage", type: "language", label: I18N_NOOP("Language"), def: "",
          help: I18N_NOOP("The language of the voices offered below. \"Engine default\" uses your system language.")},
         {key: "voiceTtsSystemVoice", type: "voice", label: I18N_NOOP("Voice"), def: "",
          help: I18N_NOOP("Which voice reads to you. Try a few with \"Say Hello\".")},
         {key: "voiceTtsSystemRate", type: "rate", label: I18N_NOOP("Speed"), def: 0,
          help: I18N_NOOP("How fast the voice talks. The middle is normal speed.")},
         {key: "voiceTtsSystemPitch", type: "pitch", label: I18N_NOOP("Pitch"), def: 0,
          help: I18N_NOOP("How high or deep the voice sounds. The middle is its normal pitch.")}]},
    {id: "kokoro", kind: "qt", plugin: "kokoro", label: I18N_NOOP("Kokoro"),
     note: I18N_NOOP("Neural voices from the Kokoro speech plugin."),
     options: [
         {key: "voiceTtsKokoroLanguage", type: "language", label: I18N_NOOP("Language"), def: "",
          help: I18N_NOOP("The language of the voices offered below. \"Engine default\" uses your system language.")},
         {key: "voiceTtsKokoroVoice", type: "voice", label: I18N_NOOP("Voice"), def: "",
          help: I18N_NOOP("Which voice reads to you. Try a few with \"Say Hello\".")},
         {key: "voiceTtsKokoroRate", type: "rate", label: I18N_NOOP("Speed"), def: 0,
          help: I18N_NOOP("How fast the voice talks. The middle is normal speed.")}]},
    {id: "flite", kind: "qt", plugin: "flite", label: I18N_NOOP("Flite"),
     note: I18N_NOOP("Small built-in English voices."),
     options: [
         {key: "voiceTtsFliteVoice", type: "voice", label: I18N_NOOP("Voice"), def: "",
          help: I18N_NOOP("Which voice reads to you. Try a few with \"Say Hello\".")},
         {key: "voiceTtsFliteRate", type: "rate", label: I18N_NOOP("Speed"), def: 0,
          help: I18N_NOOP("How fast the voice talks. The middle is normal speed.")},
         {key: "voiceTtsFlitePitch", type: "pitch", label: I18N_NOOP("Pitch"), def: 0,
          help: I18N_NOOP("How high or deep the voice sounds. The middle is its normal pitch.")}]},
    {id: "piper", kind: "file", needs: "piper", label: I18N_NOOP("Piper"),
     note: I18N_NOOP("Fast local neural voices. Pick a downloaded .onnx voice (its .onnx.json must be next to it)."),
     options: [
         {key: "voiceTtsPiperModel", type: "file", found: "piper", label: I18N_NOOP("Voice file"), def: "", filter: "*.onnx",
          placeholder: "~/.local/share/piper/en_US-lessac-medium.onnx",
          help: I18N_NOOP("A Piper voice is a file you download once (ending in .onnx). Pick one found on this computer, or choose the file yourself.")},
         {key: "voiceTtsPiperSpeaker", type: "int", label: I18N_NOOP("Speaker number"), def: 0,
          hint: I18N_NOOP("Only for voices with several speakers."),
          help: I18N_NOOP("Some voice files hold several people's voices; this picks one of them. Leave at 0 otherwise.")},
         {key: "voiceTtsPiperSpeed", type: "speed", label: I18N_NOOP("Speed"), def: 1,
          help: I18N_NOOP("How fast the voice talks; 1× is normal speed.")}]},
    {id: "remote", kind: "file", label: I18N_NOOP("Speech server (OpenAI-compatible)"),
     note: I18N_NOOP("Any server with /audio/speech: Kokoro-FastAPI, openedai-speech, OpenAI…"),
     options: [
         {key: "voiceTtsRemoteUrl", type: "url", label: I18N_NOOP("Server URL"), def: "http://localhost:8880/v1",
          placeholder: "http://localhost:8880/v1",
          help: I18N_NOOP("The web address of the speech server, from its documentation (often ending in /v1).")},
         {key: "voiceTtsRemoteModel", type: "text", label: I18N_NOOP("Speech model"), def: "tts-1", placeholder: "tts-1",
          help: I18N_NOOP("The speech model the server should use, as named by the server (for example tts-1).")},
         {key: "voiceTtsRemoteVoice", type: "text", label: I18N_NOOP("Voice"), def: "alloy", placeholder: "alloy",
          help: I18N_NOOP("The voice name the server should use (for example alloy).")},
         {key: "voiceTtsRemoteSpeed", type: "speed", label: I18N_NOOP("Speed"), def: 1,
          help: I18N_NOOP("How fast the voice talks; 1× is normal speed.")},
         {type: "secret", entry: "tts-remote", label: I18N_NOOP("API key"), hint: I18N_NOOP("Saved in KWallet. Leave empty for a local server."),
          help: I18N_NOOP("The password-like code the speech service gives you, so it knows the requests are yours.")}]},
    {id: "command", kind: "file", label: I18N_NOOP("Custom command"),
     note: I18N_NOOP("Your own program: it gets the text on standard input and writes a WAV to standard output, or to {output} if the command contains it."),
     options: [
         {key: "voiceTtsCommand", type: "command", label: I18N_NOOP("Command"), def: "",
          placeholder: "espeak-ng --stdin -v en -w {output}",
          help: I18N_NOOP("For experts: a program of your own that turns text into speech. Leave empty if you don't have one.")}]}
];

var defaultEngine = "system";

function engine(id) {
    for (var i = 0; i < engines.length; i++)
        if (engines[i].id === id)
            return engines[i];
    return null;
}

// Every main.xml key the engines use, with its default.
function optionKeys() {
    var keys = {};
    for (var i = 0; i < engines.length; i++)
        for (var j = 0; j < engines[i].options.length; j++)
            if (engines[i].options[j].key)
                keys[engines[i].options[j].key] = engines[i].options[j].def;
    return keys;
}

// The engine's settings from `config` (plasmoid.configuration or the page),
// by option type: {voice, language, rate, pitch, speed, model, ...}.
function settingsFor(id, config) {
    var spec = engine(id);
    var out = {};
    if (!spec)
        return out;
    for (var i = 0; i < spec.options.length; i++) {
        var o = spec.options[i];
        if (!o.key)
            continue;
        var value = config ? config[o.key] : undefined;
        out[o.key] = value === undefined || value === null ? o.def : value;
    }
    return out;
}

// The engine's value for an option type ("voice", "rate", …), or `fallback`.
function valueOfType(id, config, type, fallback) {
    var spec = engine(id);
    if (!spec)
        return fallback;
    for (var i = 0; i < spec.options.length; i++) {
        var o = spec.options[i];
        if (o.type === type && o.key) {
            var v = config ? config[o.key] : undefined;
            return v === undefined || v === null || v === "" ? (o.def === undefined ? fallback : o.def) : v;
        }
    }
    return fallback;
}

// Plain text to speak from a message (Markdown): code blocks become a short
// mention, links keep their words, formatting marks and tables go.
function speakableText(markdown) {
    var text = String(markdown || "");
    text = text.replace(/```[\s\S]*?(```|$)/g, "\n(code block)\n");
    text = text.replace(/<think>[\s\S]*?(<\/think>|$)/g, "");
    text = text.replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1");
    text = text.replace(/\[([^\]]+)\]\([^)]*\)/g, "$1");
    text = text.replace(/https?:\/\/\S+/g, "link");
    text = text.replace(/`([^`]*)`/g, "$1");
    text = text.replace(/^\s{0,3}#{1,6}\s+/gm, "");
    text = text.replace(/^\s*>\s?/gm, "");
    text = text.replace(/^\s*[-*+]\s+/gm, "");
    text = text.replace(/^\s*\|?[\s:|-]+\|[\s:|-]*$/gm, "");
    text = text.replace(/\|/g, ", ");
    text = text.replace(/(\*\*|__|~~)(.*?)\1/g, "$2");
    text = text.replace(/(^|[\s(])[*_]([^*_\n]+)[*_](?=[\s).,!?:;]|$)/g, "$1$2");
    text = text.replace(/[ \t]+/g, " ");
    text = text.replace(/\n{2,}/g, "\n");
    return text.trim();
}

// Splits text into pieces of at most `limit` characters, at sentence ends
// where possible, so speech starts quickly and the spoken part can be shown.
function chunks(text, limit) {
    limit = limit || 300;
    var parts = String(text || "").replace(/([.!?…:;])\s+/g, "$1\n").split(/\n+/);
    var out = [];
    var current = "";
    for (var i = 0; i < parts.length; i++) {
        var part = parts[i].trim();
        while (part.length > limit) {
            var cut = part.lastIndexOf(" ", limit);
            if (cut < limit / 2)
                cut = limit;
            if (current) { out.push(current); current = ""; }
            out.push(part.substring(0, cut).trim());
            part = part.substring(cut).trim();
        }
        if (!part)
            continue;
        if (current && current.length + 1 + part.length > limit) {
            out.push(current);
            current = part;
        } else {
            current = current ? current + " " + part : part;
        }
    }
    if (current)
        out.push(current);
    return out;
}

// QtTextToSpeech rate/pitch are -1 … 1.
function clampUnit(value) {
    var v = Number(value);
    return isNaN(v) ? 0 : Math.max(-1, Math.min(1, v));
}

function clampSpeed(value) {
    var v = Number(value);
    return isNaN(v) || v <= 0 ? 1 : Math.max(0.5, Math.min(2, v));
}
