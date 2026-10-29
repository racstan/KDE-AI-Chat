// The spending log for finished replies. chat/ReplyEvents.qml calls recordReply on "done" for a reply that
// reported its token counts; the helper's usage_add (kdeaichat/usage.py) appends one line and says whether the
// reply took its provider past a budget level (once per provider, month and level). An alert shows as a short
// note in the composer of the chat it was spent in, and as a desktop notification while the popup is closed.
// Nothing waits for the helper and a failed write changes nothing: sending never depends on this.
// `chat` is the widget root (main.qml).
import QtQuick
import "../store" as Store
import "ChatStats.js" as Stats
import "Spending.js" as Spending

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

QtObject {
    id: spending

    property var chat: null
    // chat/Notifier.qml (desktop notifications), or null.
    property var notifierRef: null
    // function(command, payload, onDone): runs a helper command. Tests replace it.
    property var runHelper: function(command, payload, onDone) {
        helperRunner.helperPath = spending.chat && typeof spending.chat.getHelperPath === "function" ? spending.chat.getHelperPath() : "";
        helperRunner.run(command, payload, onDone);
    }
    property var runnerObject: Store.HelperRunner { id: helperRunner }

    // Logs one reply. `usage` is the reply's usage (chat.currentStreamUsage: provider, model, mode, input,
    // output, cacheRead and cost, where cost is undefined or a number when the provider reported one).
    function recordReply(usage, sessionId) {
        var u = usage || {};
        if (!spending.chat || !u.provider || (u.input === undefined && u.output === undefined))
            return;
        var config = (spending.chat.plasmoid && spending.chat.plasmoid.configuration) || ({});
        var entry = {"at": Date.now(), "provider": String(u.provider), "model": String(u.model || ""), "mode": String(u.mode || ""),
                     "input": Number(u.input) || 0, "output": Number(u.output) || 0, "cacheRead": Number(u.cacheRead) || 0,
                     "cost": typeof u.cost === "number" && isFinite(u.cost) && u.cost >= 0 ? u.cost : null};
        spending.runHelper("usage_add", {"entry": entry, "budgets": Spending.parseBudgets(config.spendingBudgets),
                                         "alertPercent": config.spendingAlertPercent}, function(stdout, exitCode) {
            if (exitCode !== 0)
                return;  // the log is best effort; the reply is already shown
            var reply = Spending.parseReply(stdout);
            var alerts = reply && Array.isArray(reply.alerts) ? reply.alerts : [];
            alerts.forEach(function(alert) { spending.announce(alert, sessionId); });
        });
    }

    // One alert: the composer note only while its chat is the open one, and the desktop notification.
    function announce(alert, sessionId) {
        var name = spending.chat.providerDisplayName ? spending.chat.providerDisplayName(alert.provider) : String(alert.provider);
        var spent = Stats.formatCost(alert.spent);
        var budget = Stats.formatCost(alert.budget);
        var text = alert.percent >= 100
            ? i18n("%1: this month's budget of %2 is used up (%3 so far). Messages are still sent.", name, budget, spent)
            : i18n("%1: %2% of this month's budget is used (%3 of %4).", name, alert.percent, spent, budget);
        if (sessionId === spending.chat.currentSessionId && spending.chat.composerRef && typeof spending.chat.composerRef.showNotice === "function")
            spending.chat.composerRef.showNotice(text);
        if (spending.notifierRef && typeof spending.notifierRef.spendingAlert === "function")
            spending.notifierRef.spendingAlert(i18n("Budget alert"), text);
    }
}
