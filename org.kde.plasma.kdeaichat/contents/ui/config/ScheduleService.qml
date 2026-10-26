// The schedules (schedules.v2.json) through the helper's v2 commands:
// schedules_list, schedule_preview, schedule_save, schedule_delete and
// schedule_history. Used by Settings → Schedules and by the chat's
// "Schedule a message…" editor.
// Saving writes systemd user timers (kdeaichat/schedule_units.py).
import QtQuick
import "../store" as Store
import "ScheduleDraft.js" as Draft

Item {
    id: service
    visible: false

    property string helperPath: {
        var path = decodeURIComponent(String(Qt.resolvedUrl("../kde_ai_helper.py")).replace(/^file:\/\//, ""));
        return path.endsWith("/contents/ui/kde_ai_helper.py") ? path : "";
    }
    // run(command, payload, onDone(stdout, exitCode, stderr)); tests replace it.
    property var run: function(command, payload, onDone) {
        runner.run(command, payload, onDone);
    }

    property var schedules: []
    property bool loaded: false
    property bool busy: false
    property string error: ""

    Store.HelperRunner {
        id: runner
        helperPath: service.helperPath
    }

    // The helper's JSON answer, or {ok: false, error} when there is none.
    function _parse(stdout, stderr) {
        var text = String(stdout || "").trim();
        var lines = text.split("\n");
        for (var i = lines.length - 1; i >= 0; i--) {
            try {
                var data = JSON.parse(lines[i]);
                if (data && typeof data === "object")
                    return data;
            } catch (e) {
            }
        }
        var last = String(stderr || "").trim().split("\n").pop();
        return {"ok": false, "error": last || "the helper did not answer"};
    }

    function call(command, payload, onDone) {
        run(command, payload, function(stdout, code, stderr) {
            var data = service._parse(stdout, stderr);
            if (onDone)
                onDone(data);
        });
    }

    function refresh(onDone) {
        busy = true;
        call("schedules_list", {}, function(data) {
            busy = false;
            loaded = true;
            if (data.ok) {
                schedules = data.schedules || [];
                error = "";
            } else {
                error = data.error || "";
            }
            if (onDone)
                onDone(data);
        });
    }

    // onDone({ok, error?, summary, rules[], nextRuns[], warnings[]}).
    function preview(schedule, onDone) {
        call("schedule_preview", {"schedule": schedule, "count": 3}, onDone);
    }

    // onDone({ok, error?, schedule}); the list is reloaded after a save.
    function save(schedule, onDone) {
        call("schedule_save", {"schedule": schedule}, function(data) {
            if (data.ok)
                service.refresh();
            if (onDone)
                onDone(data);
        });
    }

    function setEnabled(item, enabled, onDone) {
        var draft = Draft.forSave(Draft.fromListItem(item));
        draft.enabled = enabled;
        save(draft, function(data) {
            if (!data.ok)
                service.error = data.error || "";
            if (onDone)
                onDone(data);
        });
    }

    function remove(id, onDone) {
        call("schedule_delete", {"id": id}, function(data) {
            service.refresh();
            if (onDone)
                onDone(data);
        });
    }

    // onDone({ok, runState: {history: [{at, scheduledFor, status, reason}], …}}).
    function history(id, onDone) {
        call("schedule_history", {"id": id}, onDone);
    }
}
