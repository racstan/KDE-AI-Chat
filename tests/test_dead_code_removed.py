"""Guards for code removed as dead (docs/plan/dead-code.md): it must not come back unnoticed."""
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UI = os.path.join(REPO, "org.kde.plasma.kdeaichat", "contents", "ui")
MAIN_XML = os.path.join(REPO, "org.kde.plasma.kdeaichat", "contents", "config", "main.xml")

REMOVED_COMMANDS = (
    "toggle_schedule", "update_schedule_history_status", "migrate_history", "write_history", "read_history",
    "delete_schedule", "add_schedule", "get_memory_usage", "get_voice_token", "setup_voice_services",
    "delete_voice_setup", "delete_venv_setup", "privacy_report", "opencode_server_status", "pi_bridge_stop",
    # Phase 5: the polling scheduler daemon and its trigger files are gone (schedules are systemd timers).
    "poll_pending_triggers", "setup_scheduler_service", "save_all_schedules",
)
REMOVED_ENTRIES = ("schedulerAutoStart", "preselectedChatId", "preselectedChatName", "voiceTtsModel")


def test_removed_helper_commands_are_unknown():
    for name in REMOVED_COMMANDS:
        out = subprocess.run([sys.executable, os.path.join(UI, "kde_ai_helper.py"), name, "e30="],
                             capture_output=True, text=True, timeout=15)
        assert out.returncode != 0 and "Unknown command" in out.stdout, name


def test_polling_scheduler_files_are_gone():
    for path in ("contents/scripts/kde-ai-scheduler.py", "contents/scripts/kde-ai-scheduler.service",
                 "contents/ui/chat/SchedulerPoller.qml"):
        assert not os.path.exists(os.path.join(REPO, "org.kde.plasma.kdeaichat", path)), path


def test_removed_settings_are_not_declared():
    with open(MAIN_XML, encoding="utf-8") as f:
        declared = set(re.findall(r'<entry name="([A-Za-z0-9_]+)"', f.read()))
    assert not declared & set(REMOVED_ENTRIES)
