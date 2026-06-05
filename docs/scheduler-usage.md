# Scheduled AI Prompts — User Guide

KDE AI Chat includes a scheduling system that allows you to automate AI prompts at specific times or intervals. This is useful for daily briefings, recurring queries, timed notifications, and automated check-ins.

## Overview

The scheduling system consists of:

- **Scheduler Daemon** (`kde-ai-scheduler.py`): A Python script that runs as a systemd user service, checks cron expressions every 5 seconds, and triggers scheduled messages.
- **Schedule Dialog** (`ScheduleDialog.qml`): The UI for creating, editing, and managing schedules within the widget.
- **File-based IPC**: The daemon writes trigger files to `~/.local/share/kdeaichat/pending/` which the widget picks up.

## Installation

The scheduler daemon is installed automatically when you run:

```bash
./install.sh
```

This will:
1. Copy `kde-ai-scheduler.py` to `~/.local/share/kdeaichat/`
2. Create the `pending/` directory
3. Install a systemd user service unit
4. Create an empty `schedules.json` file

### Starting the Daemon

After installation, start the daemon:

```bash
systemctl --user start kde-ai-scheduler.service
```

To have it start automatically at login:

```bash
systemctl --user enable kde-ai-scheduler.service
```

### Checking Daemon Status

```bash
systemctl --user status kde-ai-scheduler.service
journalctl --user -u kde-ai-scheduler.service -f
```

## Creating a Schedule

### Method 1: Via the Schedule Dialog

1. Click the **Schedule** button (clock icon) in the chat toolbar, or type `/schedule` in the chat input.
2. Click **New Schedule**.
3. Fill in the details:
   - **Name**: A descriptive name for the schedule.
   - **Target Chat**: Which chat session to send the message to.
   - **Message**: The prompt to send at the scheduled time.
   - **Task Type**: Choose **Single Run** (one-time) or **Recurring** (repeatable).
   - **Date & Time**: When to run (for single) or start date (for recurring).
   - **Repeat Interval**: Every N minutes/hours/days/weeks/months (for recurring).
   - **Execution Limit**: Optionally limit the number of runs.
4. Click **Save**.

### Method 2: Via the `/schedule` Command

Type `/schedule` in any chat to open the schedule dialog with the current chat pre-selected as the target.

## Understanding Schedule Types

### Single Run

Executes once at the specified date and time. After execution, the schedule is automatically disabled.

### Recurring (Repeatable)

Repeats at the specified interval. Available repeat types:

| Type | Example | Description |
|------|---------|-------------|
| **Minutes** | Every 30 minutes | Runs every N minutes |
| **Hours** | Every 2 hours | Runs every N hours at the top of the hour |
| **Days** | Every day at 09:00 | Runs every N days at the specified time |
| **Weeks** | Every Mon, Wed, Fri at 09:00 | Runs on selected days every N weeks |
| **Months** | Every 1st of the month at 09:00 | Runs on the specified day every N months |

### Execution Limits

For recurring schedules, you can set an execution limit (e.g., "run 5 times only"). Once the limit is reached, the schedule is automatically disabled.

## Managing Schedules

### Active Tab

Shows all currently active schedules. From here you can:

- **Toggle** on/off using the switch.
- **Edit** the schedule details.
- **Archive** the schedule (moves to Archived tab).
- **Remove** the schedule permanently.

### Archived Tab

Shows archived schedules. You can:

- **Restore** to the Active list.
- **Delete** permanently.

### History Tab

Shows a log of all executed runs, including:

- Schedule name and target chat
- Execution timestamp
- Success/error status
- The message that was sent

You can **Clear History** to remove all logged entries.

## How It Works

1. **Daemon Tick Loop**: The daemon wakes up every 15 seconds.
2. **Cron Matching**: For each enabled schedule, the daemon checks if the current time matches the cron expression.
3. **Trigger File**: If matched, a JSON trigger file is written to `~/.local/share/kdeaichat/pending/`.
4. **Widget Polling**: The widget checks the `pending/` directory every few seconds.
5. **Message Injection**: When a trigger file is found, the message is injected into the target chat and sent to the AI.
6. **Notification**: A desktop notification is shown for triggered schedules.

## Troubleshooting

### Daemon Not Running

```bash
systemctl --user restart kde-ai-scheduler.service
systemctl --user status kde-ai-scheduler.service
```

### Schedule Not Triggering

1. Check the daemon is running: `systemctl --user status kde-ai-scheduler.service`
2. Check the daemon logs: `journalctl --user -u kde-ai-scheduler.service`
3. Verify the schedule has a valid cron expression.
4. Ensure **Scheduler Enabled** is toggled on in the main widget settings.
5. Ensure **Auto-start Scheduler Daemon** is enabled in settings.

### Manually Reload Schedules

Send SIGHUP to the daemon to reload schedules without restarting:

```bash
pkill -HUP -f kde-ai-scheduler.py
```

## File Locations

| Path | Purpose |
|------|---------|
| `~/.local/share/kdeaichat/schedules.json` | Schedule definitions and run history |
| `~/.local/share/kdeaichat/pending/` | Pending trigger files (daemon → widget) |
| `~/.local/share/kdeaichat/kde-ai-scheduler.py` | The daemon script |
| `~/.config/systemd/user/kde-ai-scheduler.service` | systemd service unit |
