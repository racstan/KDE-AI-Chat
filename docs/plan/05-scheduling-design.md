# Phase 5 design note: schedules with several timing rules

Scope: data model, systemd mapping, migration and editor UI for Phase 5 (docs/plan/05-scheduling.md).
Research only; nothing in the repo was changed. systemd here is 261 (`systemd-analyze --version`).

## 1. What obsidian-ai-scheduler does (and what to take)

Cloned to /tmp/claude-1000/obsidian-ai-scheduler-study/repo (read only, nothing run). Files:

- **Model** (`src/types.ts:19-60`): a job has ONE `schedule` with a `kind`: once, daily, weekly, monthly,
  yearly, hourly, interval, **multi**, cron, event, after, meeting. `multi` is
  `rules: [{days:[0-6], times:["HH:MM",...]}]` (union of weekday×time pairs). It has no exception concept:
  "every day except Monday" is just a weekday set. Every N days/weeks/months use `everyDays/everyWeeks/
  everyMonths` anchored to `startAt` (`src/schedule.ts:55-150`), and every kind has `maxIterations`.
  Limit: multi only covers weekly days×times. A job can't mix "monthly on the 1st" with "Mondays".
- **Cron** (`src/cron/parse.ts`, `compute.ts`, `describe.ts`): a dependency-free 5-field parser with the
  vixie dom-OR-dow rule (`compute.ts:23-29`), DST-safe next/prev, and `describeCron` for plain language
  ("At 09:00, on Monday to Friday"). The prompts tell the AI to prefer simple kinds and use cron only as
  a last resort (`src/prompts.ts:50`).
- **Text form for multi** (`schedule.ts:209-251`, `ui/JobModal.ts:631-637`): one rule per line,
  `Mon-Fri = 09:00, 17:00`. You can type it, and it round-trips with `formatMultiRules`.
- **Live preview** (`ui/JobModal.ts:345-402`): it validates on every keystroke and shows
  "Next runs: a · b · c" (3 runs, `previewSchedule`, `schedule.ts:373`). If nothing will run, it says "No upcoming runs".
- **AI + cron**: the natural-language planner (`src/prompts.ts:25-51`) makes the AI return strict JSON
  `{title, prompt, schedule}`, with a worked `multi` example. A one-time time that has already passed is
  returned as asked, and the app then offers "move to tomorrow" (`src/planCheck.ts`). The AI can rewrite a job's schedule from a sentence ("AI edit",
  `prompts.ts:59-62`). Optionally the AI can append follow-up one-time jobs in `<assistant-scheduler>` tags
  (`prompts.ts:7`), which requires approval. Prompt variables include `{{date}}`, `{{weekday}}` and `{{last_run}}` (`src/variables.ts:32-45`).
- **Missed runs** (`src/engine.ts:34-72`): catch-up is off by default. When it is on, it runs only runs missed within
  `catchUpHours` (24) and marks older ones `missed`. Several missed slots collapse into one run. A crash mid-run counts
  as consumed, so the AI isn't billed twice (`engine.ts:77-97`). Its dispatcher also polls every 15 s, which we are removing.
  It also has a global pause and quiet hours (`main.ts:616`).

**Ideas to take**:
1. Rules as a list of `{days, times}`, generalised to any kind.
2. The one-line-per-rule text summary.
3. A "next 3 runs" preview that is always visible, plus "never runs" warnings.
4. Prefer structured kinds and use cron only for imported or advanced rules.
5. Later, an optional "describe when…" box where the chat's own model fills in the rules as JSON, and the user confirms them.
6. A catch-up window that collapses missed runs into a single run.
7. `{{date}}`/`{{weekday}}`/`{{last_run}}` in prompts. "Fetch latest news since {{last_run}}" is a good fit.

**Leave for later or skip**: event/after/meeting triggers, AI-created follow-up jobs, calendars/ICS, and multi-device.

## 2. Data model (schedules.json v2, written only by the widget)

```json
{ "version": 2, "settings": {"historyLimit": 50},
  "schedules": [{
    "id": "8c1f…", "name": "Latest news", "enabled": true, "archived": false,
    "chatId": "…", "message": "Fetch the latest news since {{last_run}}", "notify": true,
    "rules": [
      {"kind": "weekly", "days": [1],             "times": ["16:00"]},
      {"kind": "weekly", "days": [2,3,4,5,6,0],   "times": ["15:00"]}
    ],
    "startDate": "2026-10-27", "endDate": null, "limitCount": null,
    "catchUp": {"enabled": true, "withinHours": 12},
    "editedAt": "2026-10-26T08:20:00", "createdAt": "…" }]}
```

Rule kinds. Days are 0=Sun…6=Sat as in today's `schedDays` and JS `getDay()`. Times are local `HH:MM`, and there can be several.
| kind | fields | notes |
|---|---|---|
| `once` | `at: "2026-11-03T14:30"` | local, naive |
| `daily` | `times[]`, `everyDays` (1) | `everyDays>1` is anchored on `startDate` (or `createdAt`) |
| `weekly` | `days[]`, `times[]`, `everyWeeks` (1) | the workhorse. "Except Monday" means unticking Mon |
| `monthly` | `day: 1-31 \| "last"`, `times[]`, `everyMonths` (1) | 29-31: see open questions |
| `hourly` | `everyHours` (1), `minute`, optional `from`/`to` hour | e.g. every 2 h at :30, 08-18 |
| `minutes` | `everyMinutes` (≥15?) | kept only for migrated schedules |
| `cron` | `expr` | advanced and imported. Shown with a describe text, not editable fields |

- A schedule fires at the **union** of its rules. Duplicate instants run once.
- **Exceptions** are just weekday sets in a `weekly` rule. That covers the owner's case without an `except` concept.
  A schedule-level `skipDates: []` (holidays) can come later as a guard (section 3).
- **The owner's example** ("Mondays at 4 pm, and the rest of the days at 3 pm") is two weekly rules:
  `Mon 16:00` + `Tue–Sun 15:00`.
  "every other day" in plain English could also mean alternate days. That would be
  `{"kind":"daily","everyDays":2,"times":["15:00"]}`. The UI's summary line makes it clear which one the user built.
- **Run state is in a separate file** (only the job writes it): `~/.local/share/kdeaichat/schedule-runs/<id>.json`
  holds `{lastRunAt, lastScheduledFor, runCount, lastStatus, finished, history[]}`. The history is trimmed to `historyLimit`.
  Using one file per schedule avoids a shared lock between the widget and the jobs.

## 3. Mapping rules to systemd

The man page (`systemd.timer(5)`) confirms: "OnCalendar= may be specified more than once, in which case the timer unit
will trigger whenever any of the specified expressions elapse." So **one timer per schedule, with one or more
OnCalendar= lines per rule**, is exactly a union.

```ini
# ~/.config/systemd/user/kdeaichat-sched-<id>.timer      (<id> validated ^[A-Za-z0-9-]{1,64}$)
[Timer]
OnCalendar=Mon *-*-* 16:00:00
OnCalendar=Tue..Sun *-*-* 15:00:00
Persistent=true
AccuracySec=30s
Unit=kdeaichat-run@<id>.service
[Install]
WantedBy=timers.target
# ~/.config/systemd/user/kdeaichat-run@.service   (ONE template; the helper path lives in one place)
[Service]
Type=oneshot
ExecStart=/usr/bin/python3 <plasmoid>/contents/ui/kde_ai_helper.py run_schedule %i
```

**Main principle: systemd wakes the job and Python decides.** `run_schedule <id>` computes the latest occurrence ≤ now
of the schedule's rules, including the guards systemd can't express. It runs only if that occurrence is
`> max(lastScheduledFor, editedAt)`, is not before `startDate` or after `endDate`, and is within the catch-up window.
Otherwise it records "skipped" or "missed" and exits. This gives:
- **every N weeks/days/months**: the timer fires on every candidate day, and the guard checks
  `(isoWeek(occ) - isoWeek(anchor)) % N == 0` and the matching day or month count.
  Because the check runs on the *scheduled occurrence*, not "now", a run caught up on Tuesday for a missed
  on-week Monday is still correct.
- **dedupe**: a Persistent catch-up firing together with a normal elapse never runs twice.
- **edits**: a Persistent timer computes its next elapse from its last-trigger stamp. After an edit it can fire at once for
  an occurrence of the *new* rules that lies in the past. The `editedAt` check turns that into a no-op skip. So there's no
  need for `systemctl --user clean --what=state` except on delete (which the man page recommends).
- One Python occurrence engine (stdlib, `kdeaichat/schedule_rules.py`) also serves the "next 3 runs" preview.
  A pytest cross-checks it against `systemd-analyze calendar --iterations=N` for every compiled line that has no guard.

Conversion table (checked locally with `TZ=Europe/Berlin systemd-analyze calendar --iterations=4 '<expr>'`, base time
2026-10-26 08:22):

| rule | OnCalendar line(s) | verified next elapses |
|---|---|---|
| weekly Mon 16:00 | `Mon *-*-* 16:00:00` | Mon 10-26 16:00, 11-02, 11-09 ✓ |
| weekly Tue–Sun 15:00 | `Tue..Sun *-*-* 15:00:00` | Tue 10-27, Wed 10-28, Thu 10-29 ✓ |
| weekly Mon–Fri 09:00 | `Mon..Fri *-*-* 09:00:00` | Mon, Tue, Wed… ✓ |
| weekly Mon,Wed 08:00+12:00 | `Mon,Wed *-*-* 08,12:00:00` (same minute) | Mon 12:00, Wed 08:00, Wed 12:00 ✓ |
| weekly Mon,Wed 08:00+12:30 | **two lines**: `Mon,Wed *-*-* 08:00:00`, `… 12:30:00` | see trap below |
| daily 15:00 | `*-*-* 15:00:00` | ✓ |
| daily every 2 days | `*-*-* 15:00:00` + guard | `*-*-01/2` is **wrong**: it gave Oct 29, Oct 31, **Nov 1** (resets each month, the existing bug) |
| monthly day 1 09:00 | `*-*-01 09:00:00` | Nov 1, Dec 1, Jan 1 ✓ |
| monthly last day 18:00 | `*-*~01 18:00:00` | Oct 31, Nov 30, Dec 31 ✓ (`*-*-~01` fails to parse) |
| every 3 months on day 15 | `*-*-15 09:00` + month guard (or `*-01/3-15` if anchored in Jan/Apr/Jul/Oct) | `*-01/3-15`: Jan 15, Apr 15, Jul 15 ✓ |
| first Monday of month | `Mon *-*-01..07 09:00:00` | Nov 2, Dec 7, Jan 4 ✓ (weekday AND date) |
| hourly every 3 h at :30 from 09 | `*-*-* 09/3:30:00` | 09:30, 12:30, 15:30, 18:30, then 09:30 next day (resets at midnight) |
| every 5 h | `*-*-* 00/5:00:00` | 10:00, 15:00, 20:00, **00:00** (gap of 4 h at midnight) |
| hourly 08–18 at :30 | `*-*-* 08..18:30:00` | 08:30, 09:30, 10:30 ✓ |
| every 15 min | `*:0/15` → `*-*-* *:00/15:00` | ✓ |
| once 2026-11-03 14:30 | `2026-11-03 14:30:00` | Tue 11-03 14:30 ✓ |
| cron `0 9 1 * 1` (dom OR dow) | `*-*-01 09:00:00` + `Mon *-*-* 09:00:00` | systemd ANDs a weekday with a date, so cron's OR **must** be split into two lines |
| cron `*/20 8-17 * * 1-5` | `Mon..Fri *-*-* 08..17:00/20:00` | 08:40, 09:00, 09:20 ✓ (expand each field to a list or range) |

**Traps found:**
- **Commas in the time part apply per field.** `Mon,Wed 08:00,12:30` gave **08:00:30 and 08:12:30**
  (the `12` was read as a minute and `30` as a second). Always emit one line per `HH:MM`, or merge times only when they share the minute.
- `*-02-30` gives "Next elapse: never". The writer must reject any line whose result is `never` (for `once`: one in the past).
- DST: a local time that doesn't exist is skipped. `*-*-* 02:30` from 2027-03-27 goes to **03-29** (03-28 is skipped),
  and `once 2027-03-28 02:30` gives `never`. The editor should warn about times between 02:00 and 03:00.
- Hour steps reset at midnight. The UI offers only every 1/2/3/4/6/8/12 hours (divisors of 24). Anything else goes through
  the guard.
- After suspend, calendar timers fire once on resume (man: "will only result in a single service activation").
  `Persistent=true` adds catch-up for time spent powered off or logged out. User timers only run while the user
  manager is up (logged in, or `loginctl enable-linger`).

**Validation:** the helper's `schedule_write` compiles the rules and runs `systemd-analyze calendar <line>` for each line
(argv list, no shell). It rejects the write on a parse failure or `never`. It writes the timer with an atomic write, then
runs `systemctl --user daemon-reload` and `enable --now`. Disabling the schedule runs `disable --now`. Deleting it runs
`disable --now` + `clean --what=state` and removes the file. When `limitCount` is reached, the job sets `finished` in
its *run-state* file and runs `disable --now` on its own timer.
Test: a pytest table of rule → lines → `systemd-analyze calendar --base-time=… --iterations=N`. Skip it if the binary
is missing; the CI arch-plasma container has systemd.

## 4. Migration (v1 → v2, once, held under the store lock)

v1 fields: `taskType` single|repeat, `schedType` minutes|hours|days|weeks|months, `schedEvery`, `schedDays`,
`schedDayOfMonth`, `startDate` (ISO; **`buildCron` takes the time from startDate**, not from `schedTime`),
`limitEnabled/limitCount`, `cron`, plus the daemon's `runCount/lastRunAt/nextRunAt` and top-level `history`.

1. Back up `schedules.json` → `schedules.v1.json`.
2. If `cron` ≠ `buildCron(fields)` (the JSON was hand-edited), migrate it to `{"kind":"cron","expr":cron}`.
   Otherwise migrate from the fields the user *picked*. This fixes the old bugs on purpose: "every N weeks" now gets
   `everyWeeks:N`, and hours keep the start minute.
   - single → `once {at: local(startDate)}`
   - minutes → `minutes {everyMinutes:n}`
   - hours → `hourly {everyHours:n, minute: startMinute}`
   - days → `daily {times:[HH:MM], everyDays:n}`
   - weeks → `weekly {days: schedDays, times:[HH:MM], everyWeeks:n}`
   - months → `monthly {day: schedDayOfMonth, times:[HH:MM], everyMonths:n}`
3. Map `limitEnabled ? limitCount : null` → `limitCount`. A `startDate` in the future is kept as `startDate`.
4. Move `runCount`, `lastRunAt` and the history entries for that schedule into `schedule-runs/<id>.json`. Drop `nextRunAt`
   and `humanReadable`. Set `editedAt = now`, so nothing fires immediately after the upgrade.
5. Run a v1 `once` that already ran (`lastRunAt` set) is marked `finished` and gets no timer.
6. Write timers for the enabled schedules, then stop, disable and remove `kde-ai-scheduler.service`, the daemon copy and `pending/`
   (after draining it into the chats one last time).

## 5. Rules editor (sketch)

```
┌ Schedule: Latest news ────────────────────────────────────────────┐
│ Chat [ News ▾ ]   Message [ Fetch the latest news since {{last_run}} ] │
│ When                                                              │
│  ┌ Rule 1 ─ [Weekly ▾]  (M) T W T F S S   at [16:00] [+ time]  [🗑] ┐ │
│  ┌ Rule 2 ─ [Weekly ▾]   M (T)(W)(T)(F)(S)(S) at [15:00] [+ time] [🗑] ┐ │
│  [+ Add rule]   presets: Every day · Weekdays · Weekends · Once…  │
│  ⚠ Mon is covered by rule 1 at 16:00 and rule 2 → fine (different │
│    times); shown only when two rules hit the same day             │
│ Summary: Mon 16:00; Tue–Sun 15:00                                 │
│ Next runs: Mon 26 Oct 16:00 · Tue 27 Oct 15:00 · Wed 28 Oct 15:00 │
│ ▸ More: start date · end date / stop after N runs · if missed:    │
│   [run once when back, within 12 h ▾] · Advanced: cron rule       │
└───────────────────────────────────────────────────────────────────┘
```
- Each kind gets its own small row: weekday chips + time list. Every-N weeks/days/months goes in a "Repeat every [1] week"
  spin box, shown only after a click on "every …". Monthly has a day spin box plus a "Last day" option.
- Adding a rule starts as a weekly rule with the weekdays not yet covered pre-ticked. That turns the owner's flow
  (add Mon 16:00, then add rule → Tue–Sun are ticked) into a 2-click task, and is our answer to "except".
- The summary line comes from the rules (Python engine, or a small JS `ScheduleText.js` module tested with node).
  The next 3 runs come from the helper (`schedule_preview` = the same engine as `run_schedule`), debounced 300 ms.
  It shows "Never runs" in red, and the Save button is disabled while there are invalid rules.
- The schedules list shows: name · chat · summary · next run (`systemctl --user show -p NextElapseUSecRealtime`, or the
  engine) · last result. Each schedule has a history view. One master switch.

## 6. Risks and open questions for the owner

1. **"every other day"**: does it mean Tue–Sun (as in the brief) or alternate days? Both are supported. The summary makes it explicit.
2. **Headless + KWallet locked**: the plan's existing decision is still needed (skip + notify vs deliver-to-widget).
3. **Catch-up default**: run once if missed within N hours (proposed: 12 h), or never? Should one-time tasks run late
   ("late" marker) or be marked missed?
4. **Monthly day 29–31** in short months: skip them (cron/systemd behaviour), clamp to the last day (Obsidian plugin),
   or only offer "Last day"? Proposed: skip, with a warning and the "Last day" option next to it.
5. **Minimum interval**: allow every-N-minutes rules for AI prompts at all? Proposed minimum 15 min, kept for migrated schedules.
6. **Logged-out runs**: offer `loginctl enable-linger`? (Without it, nothing runs while logged out. With Persistent=true,
   one catch-up runs at login.)
7. **Unit path drift**: a system-wide install (`/usr/share/plasma/plasmoids`) and a user install have different
   helper paths. The widget rewrites `kdeaichat-run@.service` on start if the path differs.
8. **Two engines** (systemd's and our Python one) could disagree. Mitigations: the cross-check tests, and treating
   systemd only as the wake-up source.
9. **Holiday/skip-date exceptions and the "describe when → AI fills rules" box**: in Phase 5, or later?
10. **DST**: should times between 02:00 and 03:00 be allowed (they are skipped once a year)? Proposed: warn, don't block.

## Owner decisions (2026-10-26)

- **Background runs:** schedules run headless through systemd user timers, even with the widget closed. If KWallet is locked when a direct-mode prompt is due, the run is skipped and a notification says so.
- **Only while logged in:** no `loginctl enable-linger`.
- **Missed runs:** each schedule has a catch-up option. **Default: no catch-up**, and missed times are recorded as missed. With catch-up on, one run is made on wake for times missed within the window (12 h default).
- **Owner's example:** "Mondays at 4 pm, every other day at 3 pm" means Mon 16:00 + Tue–Sun 15:00 (two weekly rules). "Every N days" (alternate days) is also possible as its own rule kind.
- **AI "Describe when" box is in Phase 5.** The user types a sentence; their model returns the rules JSON. **When the AI is unsure (e.g. "every other day": the remaining weekdays or alternate days?), it must ask the user with options** before filling in rules, and the user always reviews the rules (summary + next runs) before saving.
- **Defaults picked by the main session** (open to change):
  - monthly days 29–31 skip months without that day, and the editor offers "Last day";
  - every-N-minutes rules have a 15-minute minimum;
  - times between 02:00 and 03:00 get a daylight-saving warning, not a block;
  - hour steps only offer 1/2/3/4/6/8/12.
