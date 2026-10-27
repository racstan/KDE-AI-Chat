// The look, layout and behaviour customisations as the chat uses them
// (main.qml's `prefs`; the settings and their defaults are in Prefs.js).
// With the defaults every value here is what the chat did before the
// options existed, so the widget looks and behaves like the rest of Plasma.
//
// Also does the two behaviours that aren't a look: a new chat each time the
// popup opens, and asking before a chat is deleted.
import QtQuick
import QtQuick.Controls as QQC2
import "Prefs.js" as Prefs

QtObject {
    id: prefs

    // The widget root (main.qml), or a stand-in.
    property var chat: null
    // plasmoid.configuration (a stand-in in tests).
    property var config: null

    function get(key) { return Prefs.value(prefs.config, key); }

    // Chat look.
    readonly property real fontFactor: Prefs.fontFactor(get("chatFontScale"))
    readonly property string density: get("chatDensity")
    readonly property real densityFactor: Prefs.densityFactor(density)
    readonly property bool bubbles: get("chatStyle") === "bubbles"
    // null: the Plasma colours.
    readonly property var codeTheme: Prefs.codeTheme(get("codeTheme"))
    // "" = the Plasma accent colour.
    readonly property string accent: Prefs.accent(get("accentColor"))

    // Layout.
    readonly property bool historyOnRight: get("historySide") === "right"
    readonly property bool showWorkspaceBar: get("showWorkspaceBar")
    readonly property bool showHistoryButton: get("headerShowHistory")
    readonly property bool showPinButton: get("headerShowPin")
    readonly property bool showSettingsButton: get("headerShowSettings")
    readonly property bool showNewChatButton: get("headerShowNewChat")
    readonly property bool showInfoButton: get("headerShowInfo")

    // Behaviour.
    readonly property string sendKey: get("sendKey")
    readonly property bool autoScroll: get("autoScroll")
    readonly property string timeFormat: get("timeFormat")
    readonly property bool confirmDelete: get("confirmDeleteChat")
    readonly property bool newChatOnOpen: get("newChatOnOpen")

    // `base` (a theme font) at the chosen text size; `base` itself at 100 %.
    function scaledFont(base) {
        if (prefs.fontFactor === 1 || !base)
            return base;
        var props = {"family": base.family, "bold": base.bold, "italic": base.italic, "weight": base.weight};
        if (base.pixelSize > 0)
            props.pixelSize = Math.max(6, Math.round(base.pixelSize * prefs.fontFactor));
        else
            props.pointSize = Math.max(5, base.pointSize * prefs.fontFactor);
        return Qt.font(props);
    }

    // A spacing at the chosen density (the spacing itself at "normal").
    function spaced(size) {
        return prefs.densityFactor === 1 ? size : Math.round(size * prefs.densityFactor);
    }

    // Whether this key event sends the message (the other Enter adds a line).
    function sendsMessage(event) {
        return Prefs.sends(prefs.sendKey, event.key === Qt.Key_Return || event.key === Qt.Key_Enter ? "return" : "",
                           (event.modifiers & Qt.ControlModifier) !== 0, (event.modifiers & Qt.ShiftModifier) !== 0);
    }

    // A message's time: "" keeps the chat's own (the format it always had).
    function formatTime(ts) {
        if (prefs.timeFormat === "system")
            return ts ? new Date(ts).toLocaleTimeString(Qt.locale(), Locale.ShortFormat) : "";
        return prefs.timeFormat === "24h" ? "" : Prefs.formatTime(ts, prefs.timeFormat);
    }

    // Deletes a chat, asking first when the user wants that (ChatDeleteConfirm.qml
    // over `host`). Returns the question, or null when it was deleted at once.
    function deleteChat(sessionId, title, host) {
        if (!prefs.confirmDelete || !host) {
            prefs.chat.deleteSession(sessionId);
            return null;
        }
        var popup = prefs._confirm.createObject(host, {"chat": prefs.chat, "sessionId": sessionId, "title": title || ""});
        if (popup)
            (popup as QQC2.Popup).open();
        return popup;
    }

    // Each time the popup opens: a new chat, unless the open one is still
    // empty or a reply is being written into it.
    function popupOpened() {
        if (!prefs.newChatOnOpen || !prefs.chat || prefs.chat.loading)
            return false;
        if ((prefs.chat.messages || []).length === 0)
            return false;
        prefs.chat.createSession(true);
        return true;
    }

    property Component _confirm: Component {
        ChatDeleteConfirm {}
    }

    property Connections _opened: Connections {
        target: prefs.chat
        ignoreUnknownSignals: true
        function onExpandedChanged() {
            // After main.qml has loaded the chats (onExpandedChanged there).
            if (prefs.chat.expanded)
                Qt.callLater(prefs.popupOpened);
        }
    }
}
