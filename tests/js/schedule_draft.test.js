// Tests for config/ScheduleDraft.js (the schedule editor's draft), run by tests/test_schedule_ui_js.py.
"use strict";
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const path = require("path");

const src = fs.readFileSync(path.join(__dirname, "../../org.kde.plasma.kdeaichat/contents/ui/config/ScheduleDraft.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const ctx = {};
vm.runInNewContext(src + "\nthis.D = this;", ctx);
const D = ctx.D;
const plain = v => JSON.parse(JSON.stringify(v));
const NOW = new Date(2026, 9, 26, 8, 20);   // Mon 26 Oct 2026

const tests = {
    times_are_normalised() {
        assert.strictEqual(D.normalizeTime("9"), "09:00");
        assert.strictEqual(D.normalizeTime("9:30"), "09:30");
        assert.strictEqual(D.normalizeTime("0930"), "09:30");
        assert.strictEqual(D.normalizeTime("16.05"), "16:05");
        assert.strictEqual(D.normalizeTime(" 23:59 "), "23:59");
        for (const bad of ["24:00", "9:60", "nine", "", "12:345"])
            assert.strictEqual(D.normalizeTime(bad), "", bad);
    },
    dates_are_checked() {
        assert.strictEqual(D.normalizeDate("2026-2-3"), "2026-02-03");
        assert.strictEqual(D.normalizeDate("2026-02-30"), "");
        assert.strictEqual(D.normalizeDate("tomorrow"), "");
    },
    a_new_weekly_rule_ticks_the_free_weekdays() {
        const mon = {kind: "weekly", days: [1], times: ["16:00"]};
        const next = D.defaultRule("weekly", [mon], NOW);
        assert.deepStrictEqual(plain(next.days), [0, 2, 3, 4, 5, 6]);
        // all covered: weekdays
        const all = {kind: "weekly", days: [0, 1, 2, 3, 4, 5, 6], times: ["09:00"]};
        assert.deepStrictEqual(plain(D.defaultRule("weekly", [all], NOW).days), [1, 2, 3, 4, 5]);
    },
    every_kind_has_a_default() {
        for (const kind of D.KINDS) {
            const rule = D.defaultRule(kind, [], NOW);
            assert.strictEqual(rule.kind, kind);
            assert.strictEqual(D.ruleProblem(rule), "", kind);
        }
        assert.strictEqual(D.defaultRule("once", [], NOW).at, "2026-10-27T09:00");
    },
    changing_kind_keeps_the_times() {
        const weekly = {kind: "weekly", days: [1], times: ["16:00", "18:30"]};
        assert.deepStrictEqual(plain(D.changeKind(weekly, "daily", [weekly], NOW).times), ["16:00", "18:30"]);
        assert.strictEqual(D.changeKind(weekly, "once", [weekly], NOW).at, "2026-10-27T16:00");
        const once = {kind: "once", at: "2026-11-03T14:30"};
        assert.deepStrictEqual(plain(D.changeKind(once, "monthly", [once], NOW).times), ["14:30"]);
    },
    days_and_times_edit_without_mutating() {
        const rule = {kind: "weekly", days: [1, 3], times: ["09:00"]};
        const toggled = D.toggleDay(rule, 3);
        assert.deepStrictEqual(plain(toggled.days), [1]);
        assert.deepStrictEqual(plain(D.toggleDay(toggled, 0).days), [0, 1]);
        assert.deepStrictEqual(rule.days, [1, 3]);
        assert.deepStrictEqual(plain(D.setDays(rule, "weekends").days), [0, 6]);
        const more = D.addTime(rule);
        assert.deepStrictEqual(plain(more.times), ["09:00", "10:00"]);
        assert.deepStrictEqual(plain(D.removeTime(more, 0).times), ["10:00"]);
        assert.deepStrictEqual(plain(D.setTime(rule, 0, "7").times), ["07:00"]);
        assert.deepStrictEqual(plain(D.setTime(rule, 0, "7pm").times), ["7pm"]);
    },
    problems_are_found_per_rule() {
        assert.strictEqual(D.ruleProblem({kind: "weekly", days: [], times: ["09:00"]}), "no-days");
        assert.strictEqual(D.ruleProblem({kind: "daily", times: []}), "no-times");
        assert.strictEqual(D.ruleProblem({kind: "daily", times: ["7pm"]}), "bad-time");
        assert.strictEqual(D.ruleProblem({kind: "minutes", everyMinutes: 5}), "too-often");
        assert.strictEqual(D.ruleProblem({kind: "cron", expr: "0 9 *"}), "bad-cron");
        assert.strictEqual(D.ruleProblem({kind: "once", at: "soon"}), "bad-time");
    },
    for_save_keeps_only_definition_keys() {
        const item = {id: "a", name: " News ", chatId: "c", message: "m", rules: [], summary: "x", nextRuns: [],
                      runState: {}, warnings: [], startDate: "2026-11-1", endDate: "", limitCount: "0"};
        const out = D.forSave(D.fromListItem(item));
        assert.strictEqual(out.name, "News");
        assert.strictEqual(out.summary, undefined);
        assert.strictEqual(out.runState, undefined);
        assert.strictEqual(out.startDate, "2026-11-01");
        assert.strictEqual(out.endDate, null);
        assert.strictEqual(out.limitCount, null);
        assert.strictEqual(D.forSave(D.newSchedule("c", NOW)).id, undefined);
    },
    a_migrated_draft_opens_ready_to_finish() {
        const draft = D.fromListItem({id: "m", needsReview: true, enabled: false, rules: [], chatId: "", message: "hi"});
        assert.strictEqual(draft.enabled, true);
        assert.strictEqual(draft.rules.length, 1);
        assert.deepStrictEqual(plain(D.missingParts({rules: [], chatId: "", message: "hi"})), ["chat", "time"]);
        assert.deepStrictEqual(plain(D.missingParts({rules: [{}], chatId: "x", message: ""})), ["message"]);
    },
    chat_choices_skip_archived_chats_but_keep_the_target() {
        const sessions = [{value: "a", text: "News"}, {value: "b", text: "", archived: true}, {value: "c", text: "Old", archived: true}];
        assert.deepStrictEqual(plain(D.chatChoices(sessions, "c")), [{id: "a", title: "News"}, {id: "c", title: "Old"}]);
        assert.strictEqual(D.chatTitle(sessions, "b"), "New Chat");
        assert.strictEqual(D.chatTitle(sessions, "zzz"), "");
    },
    last_result_reads_the_run_state() {
        assert.strictEqual(D.lastResult(null).state, "none");
        assert.strictEqual(D.lastResult({lastStatus: "ok", lastRunAt: "2026-10-26T09:00:00"}).state, "ok");
        const err = D.lastResult({lastStatus: "error: HTTP 401", lastRunAt: "x"});
        assert.strictEqual(err.state, "error");
        assert.strictEqual(err.text, "HTTP 401");
        assert.strictEqual(D.lastResult({lastStatus: "missed", lastScheduledFor: "y"}).at, "y");
        assert.strictEqual(D.lastResult({lastStatus: "due-not-run"}).state, "pending");
        assert.strictEqual(D.lastResult({finished: true, finishedAt: "z"}).state, "finished");
        assert.strictEqual(D.lastResult({lastStatus: "skipped: wallet locked"}).state, "skipped");
    },
    day_offsets() {
        assert.strictEqual(D.dayOffset(D.parseLocal("2026-10-26T16:00:00"), NOW), 0);
        assert.strictEqual(D.dayOffset(D.parseLocal("2026-10-27T15:00"), NOW), 1);
        assert.strictEqual(D.dayOffset(D.parseLocal("2026-10-29T15:00"), NOW), null);
        assert.strictEqual(D.parseLocal("nope"), null);
    },
};

let failed = 0;
for (const [name, fn] of Object.entries(tests)) {
    try {
        fn();
        console.log("ok   " + name);
    } catch (e) {
        failed++;
        console.log("FAIL " + name + "\n" + e.stack);
    }
}
process.exit(failed ? 1 : 0);
