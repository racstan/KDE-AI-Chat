# Phase 5: Scheduling

**Goal:** "run this prompt every weekday at 9" works reliably, even after suspend or with the widget closed, costs nothing when idle, and puts the answer in the right chat with a notification.

Paths are relative to `org.kde.plasma.kdeaichat/contents/`.

## Audit findings

**How it works today:**
1. `ScheduleDialog.qml` builds a cron string (`buildCron`, :104-129; one-time tasks get an empty cron).
2. `save_all_schedules` replaces the whole list in `~/.local/share/kdeaichat/schedules.json`.
3. A Python daemon wakes **every 5 s** (`scripts/kde-ai-scheduler.py:49,733`) and writes `pending/sched-<id>-<ts>.json` when a rule matches.
4. The widget forks a shell every 3 s to look for those files (since 1.4.0, only while the scheduler is on).
5. The widget then injects the prompt as a queued message.

**Broken or fragile:**
- The **prompt only runs while the widget is open.** It's sent by the widget, so closed-widget triggers pile up until next start, at most 50 at a time. A trigger for a deleted chat is dropped silently.
- The **helper deletes trigger files before the widget has handled them** (`ui/kde_ai_helper.py:367-375`), so a crash in between loses them.
- **Sending a scheduled message switches the visible chat** and back (`ui/main.qml:2546-2567`).
- It **uses whatever mode is active when delivered** (direct/OpenCode/Pi), not the chat's own mode.
- **Saving from settings can re-fire a one-time task.** Settings write back a stale list that overwrites the daemon's `runCount`/`lastRunAt` (`ui/ConfigOther.qml:209-213`).
- **Deleted history entries come back**, because both writers merge.
- **Missed-run catch-up doesn't cover suspend:** it only runs when the file is reloaded. One-time tasks ignore the setting.
- **Cron generation bugs:** "every N weeks" is ignored, step values reset at period boundaries, and hourly schedules ignore the start minute (`ui/ScheduleDialog.qml:113-127`).
- **The installed daemon is a stale copy:** setup never restarts it after copying a new version.
- **Unused code and files:**
  - The shipped `scripts/kde-ai-scheduler.service` (a different unit is written inline).
  - `results/`.
  - 4 dead helper commands.
- On the dev machine nothing is installed and `schedules.json` is `[]`.

## Design: systemd timers + headless run

- **One systemd user timer per schedule:** `kdeaichat-sched-<id>.timer` + `.service`.
  - Cron → `OnCalendar=`. Cron's "day-of-month OR day-of-week" becomes two `OnCalendar=` lines.
  - One-time tasks get an absolute date.
  - "Run missed tasks" = `Persistent=true`, which also covers suspend.
  - **Nothing runs between triggers.** The 5 s daemon and its polling are deleted.
- **The job runs the prompt itself (headless).** `kde_ai_helper.py run_schedule <id>`:
  1. Checks `startDate`/`limitCount`; disables its own timer when the limit is reached.
  2. Runs the prompt in the chat's own mode:
     - direct API: the helper calls the provider, with the key read from KWallet over D-Bus;
     - OpenCode: `opencode run` or the server API;
     - Pi: `pi -p` in the chat's folder.
  3. Appends the prompt and answer to the chat file (Phase 1 store), using an atomic write.
  4. Appends a history entry, trimmed to a retention limit.
  5. Sends a desktop notification ("Daily news is ready"); clicking it opens the chat.
- **The widget doesn't poll.** It watches the chats directory with `FolderListModel`, so the open chat refreshes when a schedule writes to it.
- **One writer per field.** Schedule definitions are written only by the widget; run state (`lastRunAt`, `runCount`, history) only by the job, in a separate file. That fixes the overwrite and resurrection bugs.
- The next run is shown from `systemctl --user show -p NextElapseUSecRealtime`.

**Owner decision needed:** running headless means a scheduled direct-API prompt needs KWallet to be unlocked at that time (it normally is while logged in). If it's locked, the job records "skipped: wallet locked" and notifies. The alternative is the current "deliver to widget" model, which only runs while the widget is open.

## Steps

1. Run-state file and atomic helpers; fix the cron builder (or store schedules in `OnCalendar` form directly).
2. Unit writer/remover in the helper; migration of existing `schedules.json` entries into timers.
3. `run_schedule` for each mode; notifications.
4. Chat-directory watching in the widget; remove the poll, daemon, `.service` file, dead commands and `results/`.
5. Simplified UI: a list of schedules (name, chat, when, next run, last result) with add/edit/delete/enable and per-schedule history. One master switch; no auto-start toggle, restart buttons or memory panel.

## Tests

- pytest: cron → `OnCalendar` conversion table (including OR semantics, steps and one-time tasks); `run_schedule` with fake backends, the limit, the start date and a locked wallet; migration.
- Manual: create a schedule 2 minutes out, suspend and resume across it, and check that the run, notification and chat update all happen.

## Done when

- No process is running and nothing polls when no schedule is due.
- Schedules fire with the widget closed and after suspend, in the chat's own mode.
