.pragma library
// The look, layout and behaviour customisations (Settings → Appearance and
// Chat), with their defaults. Every default reproduces the widget as it was
// before these options existed and follows the Plasma theme, so nothing
// changes until the user picks something else. contents/config/main.xml has
// the same defaults (tests/test_prefs.py checks they match).

var defaults = {
    // Chat look (Appearance).
    "chatFontScale": 100,          // percent of the system font, for the messages and the input
    "chatDensity": "normal",       // "compact", "normal", "roomy"
    "chatStyle": "plain",       // "plain" (no boxes) or "bubbles"
    "codeTheme": "system",         // "system" or a name in codeThemes
    "accentColor": "",             // "" = the Plasma accent colour, else "#rrggbb"
    // Layout (Appearance).
    "customPopupWidth": 760,
    "customPopupHeight": 760,
    "historySide": "left",         // "left" or "right"
    "showWorkspaceBar": true,
    "headerShowHistory": true,
    "headerShowPin": true,
    "headerShowSettings": true,
    "headerShowNewChat": true,
    "headerShowInfo": true,
    // Behaviour (Chat).
    "sendKey": "enter",            // "enter" (Shift+Enter: new line) or "ctrlEnter" (Enter: new line)
    "autoScroll": true,
    "timeFormat": "24h",           // "24h" (as before), "12h" or "system"
    "confirmDeleteChat": false,
    "newChatOnOpen": false
};

// The keys each settings page owns (for its "Reset this page").
var lookKeys = ["chatFontScale", "chatDensity", "chatStyle", "codeTheme", "accentColor"];
var layoutKeys = ["customPopupWidth", "customPopupHeight", "historySide", "showWorkspaceBar",
                  "headerShowHistory", "headerShowPin", "headerShowSettings", "headerShowNewChat", "headerShowInfo"];
var behaviourKeys = ["sendKey", "autoScroll", "timeFormat", "confirmDeleteChat", "newChatOnOpen"];

var minFontScale = 50;
var maxFontScale = 200;
var minPopupWidth = 500;
var minPopupHeight = 620;

// Colours for code blocks. "system" (not listed) uses the Plasma colours.
var codeThemes = {
    "light": {"background": "#f6f8fa", "border": "#d0d7de", "text": "#24292f", "label": "#57606a"},
    "dark": {"background": "#1e1e1e", "border": "#3c3c3c", "text": "#d4d4d4", "label": "#9d9d9d"},
    "solarizedLight": {"background": "#fdf6e3", "border": "#eee8d5", "text": "#657b83", "label": "#93a1a1"},
    "solarizedDark": {"background": "#002b36", "border": "#073642", "text": "#93a1a1", "label": "#839496"},
    "highContrast": {"background": "#000000", "border": "#ffffff", "text": "#ffffff", "label": "#ffff00"}
};

// The value of `key` in `config` (plasmoid.configuration), or its default
// when it's missing or of the wrong kind.
function value(config, key) {
    var fallback = defaults[key];
    var v = config ? config[key] : undefined;
    if (v === undefined || v === null || typeof v !== typeof fallback)
        return fallback;
    return v;
}

function isDefault(key, v) {
    return v === defaults[key];
}

// The font size factor (1 = the system size).
function fontFactor(scale) {
    var n = Number(scale);
    if (!isFinite(n) || n <= 0)
        return 1;
    return Math.max(minFontScale, Math.min(maxFontScale, Math.round(n))) / 100;
}

// How much of the normal spacing a density uses.
function densityFactor(name) {
    return name === "compact" ? 0.5 : name === "roomy" ? 1.5 : 1;
}

// A code theme's colours, or null for the Plasma colours.
function codeTheme(name) {
    return Object.prototype.hasOwnProperty.call(codeThemes, name) ? codeThemes[name] : null;
}

// "#rrggbb" when `text` is a colour the user may pick, else "".
function accent(text) {
    var t = String(text || "").trim().toLowerCase();
    if (/^#[0-9a-f]{6}$/.test(t))
        return t;
    if (/^#[0-9a-f]{3}$/.test(t))
        return "#" + t[1] + t[1] + t[2] + t[2] + t[3] + t[3];
    return "";
}

// Whether a key press sends the message. `key` is "return" for Return or
// Enter, `ctrl`/`shift` the modifiers held. The other Enter adds a line.
function sends(sendKey, key, ctrl, shift) {
    if (key !== "return")
        return false;
    if (sendKey === "ctrlEnter")
        return ctrl && !shift;
    return !shift;
}

function pad2(v) {
    return v < 10 ? ("0" + v) : String(v);
}

// A message's time in the chosen format; "" for "system" (the caller uses
// the locale's own format) or when there is no timestamp.
function formatTime(ts, format) {
    if (!ts || format === "system")
        return "";
    var d = new Date(ts);
    if (isNaN(d.getTime()))
        return "";
    if (format === "12h") {
        var h = d.getHours() % 12;
        return (h === 0 ? 12 : h) + ":" + pad2(d.getMinutes()) + (d.getHours() < 12 ? " AM" : " PM");
    }
    return pad2(d.getHours()) + ":" + pad2(d.getMinutes());
}

// The other settings on the Appearance and Chat pages (main.xml defaults),
// for the pages' "Reset this page". The prompt templates are the user's own
// writing and are not reset.
var appearancePageDefaults = {
    "appDisplayName": "KDE AI Chat", "customIcon": "dialog-messages",
    "panelIconMode": "icon", "panelIconFile": "", "panelIconHoverOnly": false,
    "notifyOnReply": true, "notifyOnError": true, "notifyOnScheduled": true, "notifyOnInput": true,
    "playNotificationSound": true
};
var chatPageDefaults = {
    "contextMessageLimit": -1, "autoNameChats": true, "allowAskUser": true,
    "openCodeWorkspaceCwd": "", "perChatModelSettings": false, "perChatPriority": "chat",
    "warnModelSwitchCache": true
};

// Sets each `cfg_<key>` of `page` to its value in `values`.
function resetPage(page, values) {
    for (var key in values) {
        if (Object.prototype.hasOwnProperty.call(values, key) && ("cfg_" + key) in page)
            page["cfg_" + key] = values[key];
    }
}
