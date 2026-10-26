"""Files and folders of the Pi bridge (pi_bridge_server.py): each chat's own
working folder, its instructions file, and private atomic writes. Stdlib only."""
import os
import re


def instructions_file(chat_id, text):
    """The chat's instructions (its project's and its own) in a private file that Pi
    appends to its system prompt; "" when there are none. Not on the command line."""
    if not text.strip():
        return ""
    path = os.path.join(private_dir("pi-instructions"), chat_id + ".md")
    private_write(path, text)
    return path


def private_dir(*parts):
    """~/.local/share/kdeaichat/<parts> (honouring XDG_DATA_HOME), made 0700 if new."""
    path = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"), "kdeaichat", *parts)
    os.makedirs(path, mode=0o700, exist_ok=True)
    return path


def _has_home_history(chat_id, home):
    """True when Pi already keeps this chat's history for the home folder.

    Before 1.4.0 a chat without a workspace ran Pi in the home folder, and Pi
    files sessions by working folder (core/session-manager.js), so such a chat
    must stay there or Pi loses what was said."""
    agent_dir = os.environ.get("PI_CODING_AGENT_DIR") or os.path.expanduser("~/.pi/agent")
    folder = os.path.join(agent_dir, "sessions", "--" + re.sub(r"[/\\:]", "-", home.lstrip("/\\")) + "--")
    suffix = "_kde-ai-chat-" + chat_id + ".jsonl"
    try:
        return any(name.endswith(suffix) for name in os.listdir(folder))
    except OSError:
        return False


def default_directory(chat_id):
    """The folder of a chat that has no workspace: its own, never the user's home
    (except for a chat that already has history there, see _has_home_history)."""
    home = os.path.realpath(os.path.expanduser("~"))
    if _has_home_history(chat_id, home):
        return home
    return os.path.realpath(private_dir("pi-workspaces", chat_id))


def private_write(path, text):
    """Writes `text` to `path` (mode 0600) atomically."""
    tmp = path + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, path)
