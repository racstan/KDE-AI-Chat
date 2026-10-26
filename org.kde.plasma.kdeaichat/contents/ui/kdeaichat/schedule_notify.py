"""Desktop notifications for scheduled runs.

A finished run is announced by the widget when it is running: it merges the
run from the chat folder's inbox and shows "<name> is ready" through its own
notifier, whose click opens the popup at that chat (chat/ScheduleInbox.qml,
chat/Notifier.qml). When Plasma isn't running, or for a run that failed or
was skipped, the job itself sends the notification with ``notify-send``
(no click action: nothing could open the chat then).

Overrides for tests: ``KDEAICHAT_NOTIFY_SEND`` (the program) and
``KDEAICHAT_WIDGET_RUNNING`` ("1"/"0" instead of asking D-Bus).
"""
import json
import os
import re
import subprocess

APP_NAME = "KDE AI Chat"
ICON = "dialog-messages"


def plasma_running() -> bool:
    """True when plasmashell holds its D-Bus name (so the widget can merge and notify)."""
    override = os.environ.get("KDEAICHAT_WIDGET_RUNNING")
    if override in ("0", "1"):
        return override == "1"
    argv = [os.environ.get("KDEAICHAT_BUSCTL") or "busctl", "--user", "--json=short", "--timeout=5", "call",
            "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", "s", "org.kde.plasmashell"]
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=10)
        return result.returncode == 0 and json.loads(result.stdout)["data"][0] is True
    except (OSError, subprocess.SubprocessError, ValueError, KeyError, IndexError, TypeError):
        return False


def preview(text: str, limit: int = 140) -> str:
    """One plain line (Markdown markup removed), at most ``limit`` characters (Notifier.preview)."""
    s = re.sub(r"```[\s\S]*?```", " ", str(text or ""))
    s = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", s)
    s = re.sub(r"`([^`]*)`", r"\1", s)
    s = re.sub(r"^\s{0,3}(#{1,6}|>|[-*+]|\d+\.)\s+", "", s, flags=re.M)
    s = re.sub(r"[*_~]{1,3}([^*_~\n]+)[*_~]{1,3}", r"\1", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s[:limit - 1].strip() + "…" if len(s) > limit else s


def send(title: str, body: str, error: bool = False) -> bool:
    """Shows one notification; False if it couldn't be sent (never raises)."""
    argv = [os.environ.get("KDEAICHAT_NOTIFY_SEND") or "notify-send", "--app-name=" + APP_NAME,
            "--icon=" + ("dialog-error" if error else ICON), "--urgency=" + ("normal" if error else "low"),
            "--", title[:200], body[:500]]
    try:
        return subprocess.run(argv, capture_output=True, timeout=15).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False
