.pragma library

// The dictation (speech-to-text) engines as Settings → Voice shows them:
// names, notes, and the options of the speech server (config/TtsOption.qml
// draws them). Speech Note has its own panel (config/SpeechNotePanel.qml).
// Plain JS (tested with node): no QML imports.

function I18N_NOOP(text) {
    return text;
}

var engines = [
    {id: "speechnote", label: I18N_NOOP("Speech Note (any language, recommended)"),
     note: I18N_NOOP("Speech Note, a separate app, listens and writes down what you say in any language, with the speech models you download in it, using your graphics card when it can. It starts when you dictate and stops when idle."),
     options: []},
    {id: "remote", label: I18N_NOOP("Speech server (OpenAI-compatible)"),
     note: I18N_NOOP("Any server with /audio/transcriptions: a local Whisper server, Groq, OpenAI… The recording is sent to that server."),
     options: [
         {key: "sttRemoteUrl", type: "url", label: I18N_NOOP("Server URL"), def: "", placeholder: "http://localhost:8000/v1",
          help: I18N_NOOP("The web address of the speech server, from its documentation (often ending in /v1).")},
         {key: "sttRemoteModel", type: "text", label: I18N_NOOP("Model"), def: "whisper-1", placeholder: "whisper-1",
          help: I18N_NOOP("The speech model the server should use, as named by the server (for example whisper-1).")},
         {type: "secret", entry: "stt-remote", label: I18N_NOOP("API key"),
          hint: I18N_NOOP("Saved in KWallet. Leave empty for a server on this computer."),
          help: I18N_NOOP("The password-like code the speech service gives you, so it knows the requests are yours.")}]}
];

var defaultEngine = "speechnote";

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

function engine(id) {
    for (var i = 0; i < engines.length; i++)
        if (engines[i].id === id)
            return engines[i];
    return null;
}
