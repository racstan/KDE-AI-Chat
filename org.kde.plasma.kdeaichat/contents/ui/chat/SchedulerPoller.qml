// Scheduled tasks: while the scheduler is on, polls the helper for triggers
// the scheduler daemon dropped in ~/.local/share/kdeaichat/pending and adds
// each to its target chat as a queued message (sent when the widget is idle).
// `chat` is the widget root (main.qml).
import QtQuick
import QtCore
import org.kde.plasma.plasma5support as P5Support
import "../Security.js" as Sec
import "TimeFormat.js" as TimeFormat

P5Support.DataSource {
    id: poller
    engine: "executable"
    connectedSources: []

    property var chat: null
    property var notifierRef: null  // chat/Notifier.qml
    property bool pollInFlight: false

    // Adds a trigger's message to its chat's queue; false if the chat is gone.
    function enqueueSchedulerTrigger(trigger) {
        if (!trigger || !trigger.chatId || !trigger.message)
            return false;
        var idx = chat.sessionIndexById(String(trigger.chatId));
        if (idx < 0) {
            console.warn("Scheduler trigger: chatId not found in sessions:", trigger.chatId);
            return false;
        }
        if (!chat.schedulerResumeSessionId && chat.currentSessionId !== String(trigger.chatId))
            chat.schedulerResumeSessionId = chat.currentSessionId;
        var updated = chat.sessions.slice();
        var session = Object.assign({}, updated[idx]);
        var messages = session.value === chat.currentSessionId ? chat.messages.slice() : (session.messages || []).slice();
        var ts = Date.now();
        messages.push({
            "role": "queued",
            "content": String(trigger.message),
            "time": TimeFormat.nowTime(ts),
            "at": ts,
            "model": "",
            "queueId": ++chat.queueCounter,
            "attachments": [],
            "scheduled": true,
            "scheduleName": String(trigger.name || "Scheduled task")
        });
        session.messages = messages;
        session.updatedAt = ts;
        updated[idx] = session;
        chat.sessions = updated;
        if (session.value === chat.currentSessionId)
            chat.messages = messages;
        chat.persistSessions();
        return true;
    }

    function poll() {
        // Don't poll until sessions are loaded so sessionIndexById works
        if (!chat._initialLoadDone || poller.pollInFlight)
            return;

        let localShare = String(StandardPaths.writableLocation(StandardPaths.GenericDataLocation));
        if (localShare.indexOf("file://") === 0) {
            localShare = localShare.substring(7);
        }
        localShare = decodeURIComponent(localShare);
        let pendingDir = localShare + "/kdeaichat/pending";
        let helper = chat.getHelperPath();
        if (!helper) return;
        let cmd = "[ -d " + Sec.quoteForShell(pendingDir) + " ] && [ \"$(ls -A " + Sec.quoteForShell(pendingDir) + " 2>/dev/null)\" ] && python3 " + Sec.quoteForShell(helper) + " poll_pending_triggers";
        poller.pollInFlight = true;
        poller.pollTimeout.restart();
        poller.connectSource("sh -c " + Sec.rawShellSnippetQuote(cmd) + " #poll_pending_triggers-" + Date.now());
    }

    property Timer pollTimeout: Timer {
        interval: 10000
        repeat: false
        onTriggered: poller.pollInFlight = false
    }

    property Timer pollTimer: Timer {
        interval: 3000
        repeat: true
        // Only the scheduler daemon writes pending triggers, so don't spawn a
        // shell every few seconds while the scheduler is switched off.
        running: !!poller.chat && poller.chat.plasmoid.configuration.schedulerEnabled === true
        onTriggered: poller.poll()
    }

    onNewData: function(sourceName, data) {
        let out = data["stdout"] ? data["stdout"] : "";
        if (sourceName.indexOf("poll_pending_triggers") >= 0) {
            poller.pollInFlight = false;
            poller.pollTimeout.stop();
        }

        poller.disconnectSource(sourceName);

        if (out.trim() === "")
            return;

        if (sourceName.indexOf("poll_pending_triggers") >= 0) {
            try {
                let parsed = JSON.parse(out);
                let pending = parsed.pending || [];
                for (let i = 0; i < pending.length; i++) {
                    let p = pending[i];
                    if (poller.enqueueSchedulerTrigger(p)) {
                        console.log("Scheduler trigger:", p.name, "-> chatId:", p.chatId);
                        if (p.notify) {
                            chat.triggerNotificationSound();
                            poller.notifierRef.scheduledRan(p.chatId, p.name, p.message);
                        }
                    }
                }
                if (!chat.loading)
                    chat.processNextQueuedMessage();
            } catch (e) {
                console.warn("Failed to parse pending triggers JSON:", e);
            }
        }
    }
}
