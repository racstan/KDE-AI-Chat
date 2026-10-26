.pragma library

// Settings → Personality: who you are and who the AI is. Builds the short
// block that goes at the start of a direct-mode system prompt
// (chat/DirectRequest.qml), and the names and avatar the chat view and the
// export show. Only filled-in fields are used; with nothing set, block() is
// exactly "" and the labels are empty, so everything looks as before.
//
// Plain JavaScript on purpose (tested with node): no QML globals, no .import.
// `cfg` is plasmoid.configuration (or any object with the same keys):
//   userName, userAbout, userTone, userLanguage, userNotes,
//   aiName, aiPersonality, aiPersonalityCustom, aiAvatar

// Field lengths: longer text is cut (settings are free text, the prompt must stay short).
var LIMITS = {
    "userName": 60, "userAbout": 600, "userLanguage": 60, "userNotes": 800,
    "aiName": 40, "aiPersonalityCustom": 800, "aiAvatar": 1024
};

// Preset ids → the line the model gets. "" (the default) sends nothing.
var TONES = {
    "friendly": "friendly and warm",
    "professional": "professional and to the point",
    "concise": "short and direct, without filler",
    "playful": "light and playful, with some humour"
};
var TONE_IDS = ["", "friendly", "professional", "concise", "playful"];

var PERSONALITIES = {
    "friendly": "Friendly and encouraging: warm, patient and positive.",
    "professional": "Professional: clear, precise and neutral, like an expert colleague.",
    "witty": "Witty: helpful first, with a dry sense of humour where it fits.",
    "mentor": "A mentor: explain the why, check understanding and help the user learn rather than only giving answers.",
    "concise": "Concise: the shortest complete answer, no small talk."
};
var PERSONALITY_IDS = ["", "friendly", "professional", "witty", "mentor", "concise", "custom"];

var IMAGE_EXT = /\.(png|jpe?g|gif|webp|svgz?|bmp)$/i;

// One field as safe, bounded text: no control characters (newlines kept when
// `multiLine`), trimmed, cut at `max` characters with "…".
function clamp(value, max, multiLine) {
    var s = String(value === undefined || value === null ? "" : value).replace(/\r\n?/g, "\n");
    s = s.replace(multiLine ? /[\u0000-\u0009\u000b-\u001f\u007f]/g : /[\u0000-\u001f\u007f]+/g, multiLine ? "" : " ");
    s = s.replace(/\n{3,}/g, "\n\n").trim();
    if (s.length > max)
        s = s.substring(0, max - 1).replace(/\s+$/, "") + "…";
    return s;
}

function _field(cfg, key, multiLine) {
    return clamp(cfg ? cfg[key] : "", LIMITS[key], multiLine);
}

// The user's name for the chat view and exports ("" = show "You").
function userLabel(cfg) {
    return _field(cfg, "userName", false);
}

// The AI's name ("" = show the model, as before).
function aiLabel(cfg) {
    return _field(cfg, "aiName", false);
}

// True for an absolute path (or file:// URL) to an image file, without "..".
function isImagePath(value) {
    var v = String(value || "").trim();
    if (v.indexOf("file://") === 0)
        v = v.substring(7);
    if (v.charAt(0) !== "/" || /[\u0000-\u001f]/.test(v) || v.split("/").indexOf("..") >= 0)
        return false;
    return IMAGE_EXT.test(v);
}

// The AI's avatar: {kind: "" | "icon" | "image", source}. An image is a
// file:// URL; an icon is a theme icon name. Anything else is no avatar.
function avatar(cfg) {
    var v = String((cfg && cfg.aiAvatar) || "").trim();
    if (!v || v.length > LIMITS.aiAvatar)
        return {"kind": "", "source": ""};
    if (v.charAt(0) === "/" || v.indexOf("file://") === 0) {
        if (!isImagePath(v))
            return {"kind": "", "source": ""};
        return {"kind": "image", "source": v.indexOf("file://") === 0 ? v : "file://" + v};
    }
    return /^[A-Za-z0-9._+-]+$/.test(v) ? {"kind": "icon", "source": v} : {"kind": "", "source": ""};
}

// The personality line: a preset's text, or the user's own ("custom").
function personalityText(cfg) {
    var id = String((cfg && cfg.aiPersonality) || "");
    if (id === "custom")
        return _field(cfg, "aiPersonalityCustom", true);
    return PERSONALITIES[id] || "";
}

// The prompt block, from filled-in fields only; "" when nothing is set.
function block(cfg) {
    var user = [];
    var name = userLabel(cfg);
    if (name)
        user.push("Name: " + name);
    var about = _field(cfg, "userAbout", true);
    if (about)
        user.push("About them: " + about);
    var tone = TONES[String((cfg && cfg.userTone) || "")];
    if (tone)
        user.push("Preferred tone: " + tone + ".");
    var language = _field(cfg, "userLanguage", false);
    if (language)
        user.push("Reply in " + language + ", whatever language they write in.");
    var notes = _field(cfg, "userNotes", true);
    if (notes)
        user.push("Always / never:\n" + notes);

    var persona = [];
    var aiName = aiLabel(cfg);
    if (aiName)
        persona.push("Your name is " + aiName + ".");
    var personality = personalityText(cfg);
    if (personality)
        persona.push("Personality: " + personality);

    var parts = [];
    if (user.length > 0)
        parts.push("## About the user\n" + user.join("\n"));
    if (persona.length > 0)
        parts.push("## Your persona\n" + persona.join("\n"));
    return parts.join("\n\n");
}
