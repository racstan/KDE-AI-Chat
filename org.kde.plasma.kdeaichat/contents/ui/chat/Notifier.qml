// Desktop notifications for the chat: a finished reply or a failed request
// while the popup is closed, and a scheduled task that delivered its message.
// Each kind has its own setting, bound by main.qml. Clicking a notification
// asks main.qml to open that chat (openChat). Tests replace `sender`.
import QtQuick
import org.kde.notification
import org.kde.plasma.plasma5support 2.0 as P5Support

// i18n() is provided by Plasma at runtime; sendEvent() is on the created Notification.
// qmllint disable unqualified
// qmllint disable missing-property

Item {
    id: notifier

    property bool popupOpen: false
    property bool replyEnabled: true
    property bool errorEnabled: true
    property bool scheduledEnabled: true
    // function(title, text, chatId, isError): shows one notification.
    property var sender: notifier.showNotification

    // The sound is separate from notifications: it also plays with the popup open.
    property bool soundEnabled: true
    // function(): plays the sound. Tests replace it.
    property var soundPlayer: notifier.runSoundCommand

    signal openChat(string chatId)

    function playSound() {
        if (!soundEnabled)
            return false;
        soundPlayer();
        return true;
    }

    function runSoundCommand() {
        soundDs.connectSource("pw-play /usr/share/sounds/ocean/stereo/message-new-instant.oga || paplay /usr/share/sounds/ocean/stereo/message-new-instant.oga || aplay /usr/share/sounds/freedesktop/stereo/bell.oga || canberra-gtk-play -i message-new-instant");
    }

    P5Support.DataSource {
        id: soundDs
        engine: "executable"
        connectedSources: []
        // Disconnect so the same command runs again next time.
        onNewData: function(sourceName) { disconnectSource(sourceName); }
    }

    // Plain one-line text: no Markdown markup, at most `limit` characters.
    function preview(text, limit) {
        var s = String(text || "");
        s = s.replace(/```[\s\S]*?```/g, " ").replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
             .replace(/`([^`]*)`/g, "$1").replace(/^\s{0,3}(#{1,6}|>|[-*+]|\d+\.)\s+/gm, "")
             .replace(/[*_~]{1,3}([^*_~\n]+)[*_~]{1,3}/g, "$1").replace(/\s+/g, " ").trim();
        var max = limit || 140;
        return s.length > max ? s.substring(0, max - 1).trim() + "…" : s;
    }

    function chatName(chatTitle) {
        return String(chatTitle || "").trim() || "KDE AI Chat";
    }

    // Each returns true when a notification was sent.
    function replyFinished(chatId, chatTitle, text) {
        if (!replyEnabled || popupOpen)
            return false;
        sender(chatName(chatTitle), preview(text) || i18n("The reply is ready."), String(chatId), false);
        return true;
    }

    function failed(chatId, chatTitle, message) {
        if (!errorEnabled || popupOpen)
            return false;
        sender(i18n("%1: request failed", chatName(chatTitle)), preview(message) || i18n("Something went wrong."), String(chatId), true);
        return true;
    }

    // Scheduled tasks deliver their message whether or not the popup is open.
    function scheduledRan(chatId, taskName, message) {
        if (!scheduledEnabled)
            return false;
        sender(String(taskName || "") || i18n("Scheduled task"), preview(message), String(chatId), false);
        return true;
    }

    function showNotification(title, text, chatId, isError) {
        var n = notificationComponent.createObject(notifier, {"title": title, "text": text, "chatId": chatId,
                                                              "iconName": isError ? "dialog-error" : "dialog-messages"});
        if (n)
            n.sendEvent();
    }

    Component {
        id: notificationComponent
        Notification {
            property string chatId: ""
            componentName: "plasma_workspace"
            eventId: "notification"
            autoDelete: true
            defaultAction: NotificationAction {
                label: i18n("Open chat")
                onActivated: notifier.openChat(chatId)
            }
        }
    }
}
