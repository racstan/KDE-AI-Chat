// Texts the schedule list and editor share: run times ("Today 16:00",
// "Wed 28 Oct 15:00") and last results, translated.
import QtQuick
import "ScheduleDraft.js" as Draft

// i18n() is provided by Plasma at runtime.
// qmllint disable unqualified

QtObject {
    // Tests set a fixed time.
    property var now: null

    function _now() {
        return now || new Date();
    }

    // A helper time ("2026-10-26T16:00:00") as a short local text.
    function when(text) {
        var date = Draft.parseLocal(text);
        if (!date)
            return "";
        var time = Qt.formatTime(date, "HH:mm");
        var offset = Draft.dayOffset(date, _now());
        if (offset === 0)
            return i18n("Today %1", time);
        if (offset === 1)
            return i18n("Tomorrow %1", time);
        if (offset === -1)
            return i18n("Yesterday %1", time);
        var sameYear = date.getFullYear() === _now().getFullYear();
        return Qt.formatDateTime(date, sameYear ? "ddd d MMM HH:mm" : "ddd d MMM yyyy HH:mm");
    }

    function runs(list) {
        return (list || []).map(when).join(" · ");
    }

    // {text, state} for the last result in a run state (Draft.lastResult).
    function result(runState) {
        var r = Draft.lastResult(runState);
        var at = when(r.at);
        switch (r.state) {
        case "ok": return {"state": r.state, "text": i18n("Sent %1", at)};
        case "error": return {"state": r.state, "text": i18n("Failed %1: %2", at, r.text)};
        case "missed": return {"state": r.state, "text": i18n("Missed %1", at)};
        case "pending": return {"state": r.state, "text": i18n("Due %1, not sent", at)};
        case "finished": return {"state": r.state, "text": i18n("Finished")};
        case "skipped": return {"state": r.state, "text": i18n("Skipped %1: %2", at, r.text)};
        }
        return {"state": "none", "text": i18n("Not run yet")};
    }

    // A history entry's status as text.
    function status(entry) {
        var s = String(entry && entry.status || "");
        if (s === "ok")
            return i18n("Sent");
        if (s === "missed")
            return i18n("Missed");
        if (s === "due-not-run")
            return i18n("Due, not sent");
        return s;
    }
}
