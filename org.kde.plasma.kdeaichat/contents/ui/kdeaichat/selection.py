"""The text selected in another app, for "Ask about the selected text" (scripts/kdeaichat-ask --selection).

The selection is the *primary selection* (what is highlighted, no Ctrl+C needed): ``wl-paste --primary``
on Wayland, ``xclip`` or ``xsel`` on X11. When nothing is selected the clipboard is used instead, and the
caller is told so (``source == "clipboard"``) so it can say it. Nothing here keeps or logs the text: it is
returned to the caller and goes straight into the ask inbox (kdeaichat/ask_inbox.py).
Tools are found on PATH; KDEAICHAT_SELECTION_PATH replaces the PATH used (tests use fake tools).
"""
import os
import shutil
import subprocess
from typing import List, Optional, Tuple

TIMEOUT = 3
MAX_BYTES = 150000  # well below the inbox limit (ask_inbox.MAX_TEXT), the quote markers add a little


def _tools(primary: bool) -> List[List[str]]:
    wayland = [["wl-paste", "--primary", "--no-newline"] if primary else ["wl-paste", "--no-newline"]]
    x11 = [["xclip", "-o", "-selection", "primary" if primary else "clipboard"],
           ["xsel", "-p" if primary else "-b"]]
    return wayland + x11 if os.environ.get("WAYLAND_DISPLAY") else x11 + wayland


def _read(primary: bool) -> str:
    path = os.environ.get("KDEAICHAT_SELECTION_PATH") or None
    for command in _tools(primary):
        exe = shutil.which(command[0], path=path)
        if not exe:
            continue
        try:
            done = subprocess.run([exe] + command[1:], capture_output=True, timeout=TIMEOUT, check=False,
                                  stdin=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError):
            continue
        text = done.stdout[:MAX_BYTES].decode("utf-8", errors="ignore") if done.returncode == 0 else ""
        if text.strip():
            return text
    return ""


def read_selection() -> Tuple[str, Optional[str]]:
    """(text, "selection" | "clipboard"), or ("", None) when both are empty or no tool exists."""
    text = _read(True)
    if text:
        return text, "selection"
    text = _read(False)
    return (text, "clipboard") if text else ("", None)


def quote(text: str) -> str:
    """The text as a "> " block, followed by a blank line where the user types the question."""
    lines = text.strip("\n").replace("\r\n", "\n").split("\n")
    return "\n".join(("> " + line).rstrip() for line in lines) + "\n\n"
