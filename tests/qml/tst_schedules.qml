// Settings → Schedules and the schedule editor, offscreen with a fake helper
// (no real command, no systemd) and a fake network for "Describe when".
// Screenshots: build/qml-screens/schedules-*.png.
import QtQuick
import QtQuick.Controls as QQC2
import QtTest

Item {
    id: root
    width: 820
    height: 1100

    property QtObject plasmoid: QtObject {
        property string id: ""
        property QtObject configuration: QtObject {
            property string chatSessionsJson: JSON.stringify([
                {"value": "chat-news", "text": "News"}, {"value": "chat-work", "text": "Work notes"},
                {"value": "chat-old", "text": "Old", "archived": true}])
            property string provider: "nvidia"
            property string providersJson: JSON.stringify([{"id": "nvidia", "name": "NVIDIA NIM", "type": "openai-compat",
                "baseUrl": "https://integrate.api.nvidia.com/v1", "model": "nvidia/nemotron-3.5-bolt-e4b"}])
        }
    }
    function i18n(text) {
        for (var i = 1; i < arguments.length; i++)
            text = text.replace("%" + i, arguments[i]);
        return text;
    }
    function i18np(singular, plural, count) {
        var text = count === 1 ? singular : plural;
        for (var i = 2; i < arguments.length; i++)
            text = text.replace("%" + (i - 1), arguments[i]);
        return text.replace("%1", count);
    }

    HarnessTestCase {
        id: t
        name: "Schedules"

        readonly property url uiDir: Qt.resolvedUrl("../../org.kde.plasma.kdeaichat/contents/ui/")
        property var page: null
        property var calls: []
        property var saveReply: null
        property var xhrReplies: []
        property var xhrSent: []

        readonly property var owner: [{"kind": "weekly", "days": [1], "times": ["16:00"], "everyWeeks": 1},
                                      {"kind": "weekly", "days": [0, 2, 3, 4, 5, 6], "times": ["15:00"], "everyWeeks": 1}]
        readonly property var listed: [
            {"id": "news", "name": "Latest news", "enabled": true, "chatId": "chat-news", "message": "Fetch the latest news",
             "rules": owner, "summary": "Mon 16:00; Tue–Sun 15:00", "nextRuns": ["2099-10-26T16:00:00"], "warnings": [],
             "runState": {"lastStatus": "ok", "lastRunAt": "2026-10-25T15:00:05", "runCount": 3}},
            {"id": "report", "name": "Weekly report", "enabled": false, "chatId": "chat-work", "message": "Write the report",
             "rules": [{"kind": "weekly", "days": [5], "times": ["17:00"]}], "summary": "Fri 17:00", "nextRuns": [],
             "warnings": [], "runState": {"lastStatus": "error: HTTP 401", "lastRunAt": "2026-10-23T17:00:02"}},
            {"id": "legacy-1", "name": "Old reminder", "enabled": false, "needsReview": true, "chatId": "", "message": "Stand up",
             "rules": [], "summary": "", "nextRuns": [], "warnings": [], "runState": {}}
        ]

        // The helper's summary of a rule (subset of kdeaichat/schedule_text.py).
        function ruleText(r) {
            var key = JSON.stringify([r.kind, r.days, r.times]);
            var known = {};
            known[JSON.stringify(["weekly", [1], ["16:00"]])] = "Mon 16:00";
            known[JSON.stringify(["weekly", [0, 2, 3, 4, 5, 6], ["15:00"]])] = "Tue–Sun 15:00";
            known[JSON.stringify(["weekly", [1, 2, 3, 4, 5], ["09:00"]])] = "Mon–Fri 09:00";
            known[JSON.stringify(["weekly", [0], ["12:00"]])] = "Sun 12:00";
            known[JSON.stringify(["daily", undefined, ["15:00"]])] = "Every 2 days at 15:00";
            return known[key] || (r.kind + " rule");
        }

        function fakeRun(command, payload, onDone) {
            t.calls.push({"command": command, "payload": JSON.parse(JSON.stringify(payload))});
            var reply = {"ok": true};
            if (command === "schedules_list")
                reply = {"ok": true, "schedules": t.listed, "settings": {"historyLimit": 50}};
            else if (command === "schedule_preview") {
                var rules = payload.schedule.rules || [];
                var bad = rules.some(function(r) { return r.kind === "minutes" && r.everyMinutes < 15; });
                reply = bad ? {"ok": false, "error": "schedules can run at most every 15 minutes"}
                    : {"ok": true, "summary": rules.map(ruleText).join("; "), "rules": rules.map(ruleText),
                       "nextRuns": ["2099-10-26T16:00:00", "2099-10-27T15:00:00", "2099-10-28T15:00:00"],
                       "warnings": rules.some(function(r) { return r.kind === "monthly"; }) ? ["Months without a day 31 are skipped."] : []};
            } else if (command === "schedule_save")
                reply = t.saveReply || {"ok": true, "schedule": payload.schedule};
            else if (command === "schedule_history")
                reply = {"ok": true, "runState": {"runCount": 2, "history": [
                    {"at": "2026-10-24T15:00:03", "scheduledFor": "2026-10-24T15:00:00", "status": "ok", "reason": "due"},
                    {"at": "2026-10-25T09:12:00", "scheduledFor": "2026-10-25T15:00:00", "status": "missed", "reason": "missed-no-catchup"}]}};
            Qt.callLater(function() { onDone(JSON.stringify(reply), 0, ""); });
        }

        function fakeXhr() {
            var x = {"headers": {}};
            x.setRequestHeader = function(k, v) { x.headers[k] = v; };
            x.open = function(method, url) { x.url = url; };
            x.send = function(body) {
                t.xhrSent.push(JSON.parse(body));
                var content = t.xhrReplies.shift();
                Qt.callLater(function() {
                    x.status = 200;
                    x.readyState = 4;
                    x.responseText = JSON.stringify({"choices": [{"message": {"content": content}}]});
                    x.onreadystatechange();
                });
            };
            return x;
        }

        function open(extra) {
            calls = [];
            saveReply = null;
            xhrSent = [];
            var component = Qt.createComponent(uiDir + "ConfigSchedules.qml");
            verify(component.status === Component.Ready, component.errorString());
            page = component.createObject(root, Object.assign({"width": root.width, "height": root.height,
                "runHelper": fakeRun, "xhrFactory": fakeXhr, "wallet": {"keys": {"nvidia": "test-key"}, "status": "ready"}}, extra || {}));
            verify(page !== null);
            tryVerify(function() { return findChildren(page, "scheduleRow").length === 3; }, 3000);
            return page;
        }

        function cleanup() {
            if (page)
                page.destroy();
            page = null;
            wait(200);
        }

        function find(item, test) {
            if (!item)
                return null;
            if (test(item))
                return item;
            var kids = item.children || [];
            for (var i = 0; i < kids.length; i++) {
                var found = find(kids[i], test);
                if (found) return found;
            }
            return null;
        }
        function visibleChild(item, name) {
            return find(item, function(i) { return i.objectName === name && i.visible; });
        }
        function lastCall(command) {
            for (var i = calls.length - 1; i >= 0; i--)
                if (calls[i].command === command)
                    return calls[i];
            return null;
        }
        function rows() {
            return findChildren(page, "scheduleRow");
        }
        function editor() {
            return find(page, function(i) { return i.hasOwnProperty("rulesValid") && i.hasOwnProperty("describer"); });
        }
        function waitPreview(count) {
            tryVerify(function() { return calls.filter(function(c) { return c.command === "schedule_preview"; }).length >= count; }, 3000);
            wait(50);
        }

        function test_list_shows_schedules_and_migrated_drafts() {
            open();
            var news = rows()[0];
            compare(findChild(news, "scheduleChat").text, "In “News”");
            compare(findChild(news, "scheduleSummary").text, "Mon 16:00; Tue–Sun 15:00");
            verify(findChild(news, "scheduleNext").text.indexOf("Next: ") === 0, findChild(news, "scheduleNext").text);
            verify(findChild(news, "scheduleNext").text.indexOf("Sent ") > 0);
            verify(findChild(news, "scheduleEnabled").checked);
            var report = rows()[1];
            verify(!findChild(report, "scheduleEnabled").checked);
            verify(findChild(report, "scheduleNext").text.indexOf("Failed") > 0);
            var legacy = rows()[2];
            verify(findChild(legacy, "scheduleReview").visible);
            compare(findChild(legacy, "scheduleReview").text, "Brought over from the old scheduler. Needs a chat and a time.");
            verify(!findChild(legacy, "scheduleEnabled").enabled, "a draft can't be switched on before it is finished");
            verify(!findChild(legacy, "scheduleSummary").visible);
            screenshot(page, "schedules-list");
        }

        function test_master_switch_pauses_everything() {
            open();
            var master = findChild(page, "masterSwitch");
            verify(master.checked);
            mouseClick(master);
            compare(lastCall("schedules_settings").payload.paused, true);
        }

        function test_switching_a_schedule_saves_only_its_definition() {
            open();
            mouseClick(findChild(rows()[1], "scheduleEnabled"));
            var saved = lastCall("schedule_save").payload.schedule;
            compare(saved.id, "report");
            compare(saved.enabled, true);
            verify(saved.summary === undefined && saved.runState === undefined && saved.nextRuns === undefined);
        }

        function test_delete_asks_first() {
            open();
            var row = rows()[0];
            mouseClick(findChild(row, "scheduleDelete"));
            verify(findChild(row, "scheduleConfirm").visible);
            verify(lastCall("schedule_delete") === null);
            mouseClick(findChild(row, "scheduleConfirmDelete"));
            compare(lastCall("schedule_delete").payload.id, "news");
        }

        function test_history_view() {
            open();
            mouseClick(findChild(rows()[0], "scheduleHistory"));
            compare(lastCall("schedule_history").payload.id, "news");
            tryVerify(function() { return findChildren(page, "historyEntry").length === 2; });
            compare(page.view, "history");
            screenshot(page, "schedules-history");
            mouseClick(findChild(page, "historyClose"));
            compare(page.view, "list");
        }

        function test_owner_example_in_the_editor() {
            open();
            mouseClick(findChild(page, "newSchedule"));
            compare(page.view, "edit");
            var ed = editor();
            compare(ed.draft.chatId, "chat-news", "the first chat is preselected");
            // Rule 1: Mondays at 16:00 (the new rule starts as Mon–Fri 09:00).
            for (var d of [2, 3, 4, 5])
                mouseClick(visibleChild(ed, "dayChip" + d));
            var time = visibleChild(ed, "ruleTime");
            time.text = "16:00";
            time.editingFinished();
            compare(JSON.stringify(ed.draft.rules[0].days), "[1]");
            compare(ed.draft.rules[0].times[0], "16:00");
            // Add rule: Tue–Sun are ticked already.
            mouseClick(findChild(ed, "addRule"));
            compare(JSON.stringify(ed.draft.rules[1].days), "[0,2,3,4,5,6]");
            var times = findChildren(ed, "ruleTime").filter(function(f) { return f.visible; });
            times[1].text = "15";
            times[1].editingFinished();
            compare(ed.draft.rules[1].times[0], "15:00");
            findChild(ed, "scheduleName").text = "Latest news";
            findChild(ed, "scheduleName").textEdited();
            findChild(ed, "scheduleMessage").text = "Fetch the latest news";
            var before = calls.length;
            tryVerify(function() {
                var c = lastCall("schedule_preview");
                return c && c.payload.schedule.rules.length === 2 && c.payload.schedule.rules[1].times[0] === "15:00";
            }, 3000);
            tryCompare(findChild(ed, "previewSummary"), "text", "Mon 16:00; Tue–Sun 15:00");
            verify(findChild(ed, "previewNext").text.indexOf("Next runs: ") === 0);
            var summaries = findChildren(ed, "ruleSummary").filter(function(l) { return l.visible; }).map(function(l) { return l.text; });
            compare(JSON.stringify(summaries), JSON.stringify(["Mon 16:00", "Tue–Sun 15:00"]));
            screenshot(page, "schedules-editor-owner");
            mouseClick(findChild(page, "saveSchedule"));
            var saved = lastCall("schedule_save").payload.schedule;
            compare(saved.name, "Latest news");
            compare(saved.message, "Fetch the latest news");
            compare(saved.rules.length, 2);
            verify(saved.id === undefined);
            tryCompare(page, "view", "list");
        }

        function test_each_rule_kind_shows_its_fields() {
            open();
            mouseClick(findChild(page, "newSchedule"));
            var ed = editor();
            var fields = {"weekly": "dayChip1", "daily": "everyN", "monthly": "monthDay", "once": "onceDate",
                          "hourly": "everyHours", "minutes": "everyN", "cron": "cronExpr"};
            var kinds = ["weekly", "daily", "monthly", "once", "hourly", "minutes", "cron"];
            for (var i = 0; i < kinds.length; i++) {
                var combo = visibleChild(ed, "ruleKind");
                combo.currentIndex = i;
                combo.activated(i);
                compare(ed.draft.rules[0].kind, kinds[i]);
                verify(visibleChild(ed, fields[kinds[i]]) !== null, kinds[i] + " shows " + fields[kinds[i]]);
                compare(visibleChild(ed, "ruleProblem"), null, kinds[i] + " starts valid");
                if (kinds[i] === "monthly") {
                    mouseClick(visibleChild(ed, "lastDay"));
                    compare(ed.draft.rules[0].day, "last");
                }
            }
            // A bad time is flagged on the rule and blocks Save.
            var combo2 = visibleChild(ed, "ruleKind");
            combo2.currentIndex = 1;
            combo2.activated(1);
            var time = visibleChild(ed, "ruleTime");
            time.text = "7pm";
            time.editingFinished();
            verify(visibleChild(ed, "ruleProblem") !== null);
            verify(!findChild(page, "saveSchedule").enabled);
            screenshot(page, "schedules-editor-bad-time");
        }

        function test_helper_errors_are_shown_inline() {
            open();
            mouseClick(findChild(page, "newSchedule"));
            var ed = editor();
            // The preview's error (a rule the helper rejects).
            ed.setRules([{"kind": "minutes", "everyMinutes": 5}]);
            tryVerify(function() { var e = visibleChild(ed, "previewError"); return e !== null; }, 3000);
            compare(visibleChild(ed, "previewError").text, "Not valid yet: schedules can run at most every 15 minutes");
            // schedule_save's error: shown, the editor stays open.
            ed.setRules(owner);
            saveReply = {"ok": false, "error": "write the message to send"};
            mouseClick(findChild(page, "saveSchedule"));
            tryVerify(function() { return visibleChild(page, "saveError") !== null; });
            compare(visibleChild(page, "saveError").text, "Not saved: write the message to send");
            compare(page.view, "edit");
            screenshot(page, "schedules-editor-save-error");
        }

        function test_finishing_a_migrated_draft() {
            open();
            mouseClick(findChild(rows()[2], "scheduleEdit"));
            var ed = editor();
            compare(ed.draft.id, "legacy-1");
            compare(ed.draft.enabled, true);
            compare(ed.draft.rules.length, 1);
            compare(findChild(ed, "scheduleChat").displayText, "Choose a chat…");
            compare(findChild(ed, "scheduleMessage").text, "Stand up");
        }

        function startDescribe(text) {
            mouseClick(findChild(page, "newSchedule"));
            var ed = editor();
            var field = findChild(ed, "describeField");
            field.text = text;
            mouseClick(findChild(ed, "describeButton"));
            return ed;
        }

        function test_describe_fills_rules_for_review() {
            open();
            xhrReplies = ['{"rules":[{"kind":"weekly","days":[1,2,3,4,5],"times":["09:00"]},{"kind":"weekly","days":[0],"times":["12:00"]}]}'];
            var ed = startDescribe("weekdays at 9 and Sunday at noon");
            tryVerify(function() { return ed.draft.rules.length === 2 && ed.draft.rules[1].days[0] === 0; }, 3000);
            compare(xhrSent[0].model, "nvidia/nemotron-3.5-bolt-e4b");
            compare(xhrSent[0].messages[0].role, "system");
            compare(xhrSent[0].messages[1].content, "weekdays at 9 and Sunday at noon");
            verify(visibleChild(ed, "describeFilled") !== null);
            verify(lastCall("schedule_save") === null, "never saved automatically");
            tryCompare(findChild(ed, "previewSummary"), "text", "Mon–Fri 09:00; Sun 12:00");
        }

        function test_describe_asks_then_fills() {
            open();
            xhrReplies = ['{"question":"By \\"every other day\\", do you mean the remaining weekdays or alternate days?","options":["Tuesday to Sunday","Every 2 days"]}',
                          '{"rules":[{"kind":"weekly","days":[1],"times":["16:00"]},{"kind":"daily","times":["15:00"],"everyDays":2}]}'];
            var ed = startDescribe("Mondays at 4 pm and every other day at 3 pm");
            tryVerify(function() { return visibleChild(ed, "describeQuestion") !== null; }, 3000);
            compare(findChild(ed, "describeQuestionText").text, "By \"every other day\", do you mean the remaining weekdays or alternate days?");
            var options = findChildren(ed, "describeOption");
            compare(options.length, 2);
            screenshot(page, "schedules-describe-question");
            mouseClick(options[1]);
            tryVerify(function() { return ed.draft.rules.length === 2 && ed.draft.rules[1].kind === "daily"; }, 3000);
            var second = xhrSent[1].messages;
            compare(second.map(function(m) { return m.role; }).join(","), "system,user,assistant,user");
            compare(second[3].content, "Every 2 days");
            compare(ed.draft.rules[1].everyDays, 2);
        }

        function test_describe_bad_answer_is_a_friendly_error() {
            open();
            xhrReplies = ["Sorry, I can only help with recipes."];
            var ed = startDescribe("every morning");
            tryVerify(function() { return visibleChild(ed, "describeError") !== null; }, 3000);
            compare(visibleChild(ed, "describeError").text, "The model's answer was not usable. Try again, or put it differently.");
            compare(ed.draft.rules.length, 1, "the rules are left alone");
        }

        function test_describe_needs_a_direct_provider() {
            var cfg = root.plasmoid.configuration;
            var provider = cfg.provider;
            cfg.provider = "";
            open();
            mouseClick(findChild(page, "newSchedule"));
            var ed = editor();
            verify(visibleChild(ed, "describeHint") !== null);
            verify(!findChild(ed, "describeField").enabled);
            verify(!findChild(ed, "describeButton").enabled);
            cfg.provider = provider;
        }
    }
}
