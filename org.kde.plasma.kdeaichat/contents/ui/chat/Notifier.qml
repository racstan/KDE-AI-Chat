// Desktop notifications for the chat: a finished reply or a failed request
// while the popup is closed, a scheduled task that delivered its message, and
// "input needed" when the AI asks a question or for permission and the popup is
// closed (or shows another chat). Each kind has its own setting, bound by
// main.qml. Clicking a notification asks main.qml to open that chat (openChat).
// Tests replace `sender` and `inputSender`.
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

    // The widget root (main.qml): an answer on a notification goes through it, and the "input
    // needed" setting and the open chat are read from it.
    property var chat: null
    property bool inputEnabled: !chat || chat.plasmoid.configuration.notifyOnInput !== false
    property string visibleChatId: chat ? String(chat.currentSessionId) : ""
    // function(spec): shows one "input needed" notification (inputSpec) and returns it. Tests replace it.
    property var inputSender: notifier.showInput
    // Request id -> its notification, while it is open.
    property var openInputs: ({})

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

    // --- Input needed -------------------------------------------------------------

    // What the notification for a question_request or permission_request message
    // (backends/AgentEvents.js) shows: {kind, id, chatId, title, text, actions: [{label, value}], typed}.
    // Up to three answers become buttons, a typed answer uses Plasma's inline reply, a permission is Allow / Deny.
    function inputSpec(chatId, chatTitle, message) {
        var spec = {"chatId": String(chatId), "title": i18n("%1: input needed", chatName(chatTitle)), "actions": [], "typed": false};
        if (message.role === "permission_request") {
            var detail = (message.arguments || [])[0];
            spec.kind = "permission";
            spec.id = String(message.permissionId || "");
            spec.text = preview(i18n("%1 asks to use %2", message.model || "", String(message.tool || "") + (detail ? ": " + detail : "")), 240);
            spec.actions = [{"label": i18n("Allow"), "value": true}, {"label": i18n("Deny"), "value": false}];
            return spec;
        }
        var questions = message.questions || [];
        var first = questions[0] || {};
        var labels = questions.length === 1 ? (first.options || []).map(function(o) { return String((o || {}).label || ""); }).filter(function(l) { return l !== ""; }) : [];
        spec.kind = "question";
        spec.id = String(message.questionId || "");
        spec.text = preview(first.question || first.header || message.content, 240) + (labels.length > 0 ? "\n" + preview(labels.join(" · "), 120) : "");
        spec.actions = labels.slice(0, 3).map(function(l) { return {"label": l.length > 40 ? l.substring(0, 39) + "…" : l, "value": l}; });
        spec.typed = questions.length === 1 && message.allowCustom !== false;
        return spec;
    }

    // Returns true when a notification was sent.
    function inputNeeded(chatId, chatTitle, message) {
        if (!inputEnabled || (popupOpen && String(chatId) === visibleChatId))
            return false;
        var spec = inputSpec(chatId, chatTitle, message);
        if (spec.id === "" || openInputs[spec.id])
            return false;
        openInputs[spec.id] = inputSender(spec) || true;
        return true;
    }

    // An answer given on the notification goes where the card's answer goes.
    function answerInput(spec, value) {
        delete openInputs[spec.id];
        if (!chat || String(chat.currentSessionId) !== spec.chatId) {
            openChat(spec.chatId);
            return false;
        }
        if (spec.kind === "permission")
            chat.respondToPermission(spec.id, value === true, false);
        else
            chat.respondToQuestion(spec.id, String(value), false);
        return true;
    }

    function closeInput(id) {
        var shown = openInputs[id];
        delete openInputs[id];
        if (shown && shown.close)
            shown.close();
    }

    // A card answered in the widget (or by the agent) closes its notification.
    function closeAnswered() {
        var ids = Object.keys(openInputs);
        for (var n = 0; n < ids.length && chat; n++) {
            for (var i = chat.messages.length - 1; i >= 0; i--) {
                var m = chat.messages[i];
                if ((m.questionId || m.permissionId) === ids[n]) {
                    if (m.status !== "pending")
                        closeInput(ids[n]);
                    break;
                }
            }
        }
    }

    Connections {
        target: notifier.chat
        ignoreUnknownSignals: true
        function onMessagesChanged() {
            if (Object.keys(notifier.openInputs).length > 0)
                notifier.closeAnswered();
        }
    }

    function showInput(spec) {
        var n = inputComponent.createObject(notifier, {"title": spec.title, "text": spec.text, "chatId": spec.chatId});
        if (!n)
            return null;
        var actions = [];
        spec.actions.forEach(function(a) {
            var action = actionComponent.createObject(n, {"label": a.label});
            action.activated.connect(function() { notifier.answerInput(spec, a.value); });
            actions.push(action);
        });
        n.actions = actions;
        if (spec.typed) {
            n.replyAction.label = i18n("Reply…");
            n.replyAction.placeholderText = i18n("Type your answer…");
            n.replyAction.submitButtonText = i18n("Send");
            n.replyAction.fallbackBehavior = NotificationReplyAction.UseRegularAction;
            n.replyAction.replied.connect(function(text) {
                if (String(text).trim() !== "")
                    notifier.answerInput(spec, String(text).trim());
            });
            n.replyAction.activated.connect(function() { notifier.openChat(spec.chatId); });
        }
        n.closed.connect(function() {
            if (notifier.openInputs[spec.id] === n)
                delete notifier.openInputs[spec.id];
        });
        n.sendEvent();
        return n;
    }

    function showNotification(title, text, chatId, isError) {
        var n = notificationComponent.createObject(notifier, {"title": title, "text": text, "chatId": chatId,
                                                              "iconName": isError ? "dialog-error" : "dialog-messages"});
        if (n)
            n.sendEvent();
    }

    Component {
        id: actionComponent
        NotificationAction {}
    }

    // Stays until it is answered or closed: the AI is waiting for it.
    Component {
        id: inputComponent
        Notification {
            property string chatId: ""
            componentName: "plasma_workspace"
            eventId: "notification"
            iconName: "dialog-question"
            flags: Notification.Persistent
            autoDelete: true
            defaultAction: NotificationAction {
                label: i18n("Open chat")
                onActivated: notifier.openChat(chatId)
            }
        }
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
