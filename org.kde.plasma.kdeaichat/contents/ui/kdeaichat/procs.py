"""Recognising processes the widget started itself.

A helper that starts a long-running process records its pid and argv; before
signalling it later, `is_ours` checks the pid still runs that exact command,
so a reused pid or a process the user started is never touched.
"""
import os
from typing import Any, Dict, List


def cmdline(pid: int) -> List[str]:
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return [part.decode("utf-8", "replace") for part in f.read().split(b"\0") if part]
    except OSError:
        return []


def is_ours(state: Dict[str, Any]) -> bool:
    """True if state["pid"] is still running the recorded state["argv"]."""
    pid = int(state.get("pid") or 0)
    argv = state.get("argv") or []
    running = cmdline(pid)
    # argv[0] may be a launcher (shell/node/python), so the process can show
    # an interpreter first; the arguments we passed must still end it exactly.
    return (pid > 0 and len(argv) > 1 and running[-(len(argv) - 1):] == argv[1:]
            and any(os.path.basename(argv[0]) in os.path.basename(part) for part in running))
