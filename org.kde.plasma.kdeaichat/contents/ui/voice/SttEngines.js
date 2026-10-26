.pragma library

// The dictation (speech-to-text) engines as Settings → Voice shows them:
// names, notes, and the options of the engines that need no special panel
// (config/TtsOption.qml draws them; faster-whisper has its own panel,
// config/FasterWhisperPanel.qml). The engine rows themselves come from the
// helper's `stt_engines` (kdeaichat/stt_engines.py), which knows what is
// installed. Plain JS (tested with node): no QML imports.

function I18N_NOOP(text) {
    return text;
}

var engines = [
    {id: "faster-whisper", label: I18N_NOOP("faster-whisper (on this computer)"),
     note: I18N_NOOP("Whisper models run by a small service that starts when you dictate and stops when idle. Needs a one-time install."),
     options: []},
    {id: "whisper-cpp", label: I18N_NOOP("whisper.cpp"),
     note: I18N_NOOP("Your own whisper.cpp program (whisper-cli) with a ggml model, or a running whisper.cpp server. No Python."),
     options: [
         {key: "sttWhisperCppBinary", type: "file", label: I18N_NOOP("Program"), def: "", filter: "*",
          placeholder: I18N_NOOP("whisper-cli (found automatically)"),
          help: I18N_NOOP("The whisper.cpp program on your computer. Leave empty to have it found automatically.")},
         {key: "sttWhisperCppModel", type: "file", label: I18N_NOOP("Model file"), def: "", filter: "*.bin *.ggml",
          placeholder: "~/whisper.cpp/models/ggml-base.bin",
          help: I18N_NOOP("The speech model file whisper.cpp uses (ending in .bin). Bigger files understand better but are slower.")},
         {key: "sttWhisperCppServer", type: "url", label: I18N_NOOP("Or server URL"), def: "",
          placeholder: "http://127.0.0.1:8080",
          help: I18N_NOOP("Instead of the program: the address of a whisper.cpp server that is already running. Leave empty to use the program.")}]},
    {id: "remote", label: I18N_NOOP("Speech server (OpenAI-compatible)"),
     note: I18N_NOOP("Any server with /audio/transcriptions: a local Whisper server, Groq, OpenAI…"),
     options: [
         {key: "sttRemoteUrl", type: "url", label: I18N_NOOP("Server URL"), def: "", placeholder: "http://localhost:8000/v1",
          help: I18N_NOOP("The web address of the speech server, from its documentation (often ending in /v1).")},
         {key: "sttRemoteModel", type: "text", label: I18N_NOOP("Model"), def: "whisper-1", placeholder: "whisper-1",
          help: I18N_NOOP("The speech model the server should use, as named by the server (for example whisper-1).")},
         {type: "secret", entry: "stt-remote", label: I18N_NOOP("API key"),
          hint: I18N_NOOP("Saved in KWallet. Leave empty for a server on this computer."),
          help: I18N_NOOP("The password-like code the speech service gives you, so it knows the requests are yours.")}]},
    {id: "command", label: I18N_NOOP("Custom command"),
     note: I18N_NOOP("Your own program: {wav} is replaced by the recording (16 kHz mono WAV) and {lang} by the language; it prints the text."),
     options: [
         {key: "sttCommand", type: "command", label: I18N_NOOP("Command"), def: "",
          placeholder: "my-stt --language {lang} {wav}",
          help: I18N_NOOP("For experts: a program of your own that turns a recording into text. Leave empty if you don't have one.")}]}
];

var defaultEngine = "faster-whisper";

var languages = [
    {value: "auto", text: I18N_NOOP("Detect automatically")}, {value: "en", text: I18N_NOOP("English")},
    {value: "de", text: I18N_NOOP("German")}, {value: "es", text: I18N_NOOP("Spanish")},
    {value: "fr", text: I18N_NOOP("French")}, {value: "it", text: I18N_NOOP("Italian")},
    {value: "pt", text: I18N_NOOP("Portuguese")}, {value: "nl", text: I18N_NOOP("Dutch")},
    {value: "pl", text: I18N_NOOP("Polish")}, {value: "ru", text: I18N_NOOP("Russian")},
    {value: "uk", text: I18N_NOOP("Ukrainian")}, {value: "tr", text: I18N_NOOP("Turkish")},
    {value: "hi", text: I18N_NOOP("Hindi")}, {value: "ja", text: I18N_NOOP("Japanese")},
    {value: "ko", text: I18N_NOOP("Korean")}, {value: "zh", text: I18N_NOOP("Chinese")}
];

var devices = [
    {value: "auto", text: I18N_NOOP("Automatic (NVIDIA GPU when there is one)")},
    {value: "cpu", text: I18N_NOOP("Processor (CPU)")},
    {value: "cuda", text: I18N_NOOP("NVIDIA GPU (CUDA)")}
];

function engine(id) {
    for (var i = 0; i < engines.length; i++)
        if (engines[i].id === id)
            return engines[i];
    return null;
}

// Splits the helper's engine rows: `choices` can be picked here (working, or
// finished on this page: installing faster-whisper, entering a URL or a
// command), `unavailable` can't, with the reason. Unknown ids are dropped.
function split(rows) {
    var out = {"choices": [], "unavailable": []};
    for (var i = 0; i < (rows || []).length; i++) {
        var row = rows[i];
        if (!engine(row.id))
            continue;
        if (row.available || row.selectable)
            out.choices.push(row);
        else
            out.unavailable.push(row);
    }
    return out;
}

// "484 MB" / "1.5 GB".
function size(mb) {
    mb = Number(mb) || 0;
    if (mb >= 1000)
        return (Math.round(mb / 100) / 10) + " GB";
    return Math.max(0, Math.round(mb)) + " MB";
}

// True when sttModel is a folder rather than a faster-whisper model name.
function isFolder(model) {
    return String(model || "").indexOf("/") >= 0;
}
