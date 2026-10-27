"""The KRunner runner: type "ai <question>" in KRunner, press Enter, and the question goes to the widget.

KRunner talks to "D-Bus runners" (the interface ``org.kde.krunner1``) described by a .desktop file in
``~/.local/share/krunner/dbusplugins/`` (installed by desktop_integration.py when the switch is on). The
service is started on demand by D-Bus (an activation file in ``~/.local/share/dbus-1/services/``) and exits
when nobody asked for a minute. Methods:

  Match(query)    -> a(sssuda{sv})  one match "Ask KDE AI Chat: <question>" when the query starts with the
                                    prefix (default "ai"), nothing otherwise
  Actions()       -> a(sss)         one extra action: ask in a new chat
  Run(match, action)               leaves the question in the ask inbox (ask_inbox.py); the widget opens
  Teardown()                       nothing to do

The prefix lives in the desktop-integration state file (written by the widget's settings). The question
arrives over D-Bus and goes to a private file, never to a command line. Plain stdlib (minidbus.py).
"""
import json
import os
import sys
import time
from typing import Any, List, Optional, Tuple

from kdeaichat import ask_inbox, minidbus

SERVICE = "org.kde.kdeaichat.runner"
PATH = "/runner"
INTERFACE = "org.kde.krunner1"
IDLE_SECONDS = 60
EXACT_MATCH = 100
ICON = "dialog-messages"
DEFAULT_PREFIX = "ai"
MAX_QUERY = 20000

INTROSPECTION = """<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
 <interface name="org.kde.krunner1">
  <method name="Match"><arg name="query" type="s" direction="in"/><arg name="matches" type="a(sssuda{sv})" direction="out"/></method>
  <method name="Actions"><arg name="matches" type="a(sss)" direction="out"/></method>
  <method name="Run"><arg name="matchId" type="s" direction="in"/><arg name="actionId" type="s" direction="in"/></method>
  <method name="Teardown"/>
 </interface>
 <interface name="org.freedesktop.DBus.Peer"><method name="Ping"/></interface>
</node>
"""


def state_path() -> str:
    override = os.environ.get("KDEAICHAT_DESKTOP_STATE")
    if override:
        return override
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(base, "kdeaichat", "desktop-integration.json")


def read_prefix(path: Optional[str] = None) -> str:
    """The word that triggers the runner (the "ai" in "ai how do I…"), from the settings."""
    try:
        with open(path or state_path(), encoding="utf-8") as f:
            value = json.load(f).get("prefix", DEFAULT_PREFIX)
    except (OSError, ValueError, AttributeError):
        return DEFAULT_PREFIX
    value = value.strip() if isinstance(value, str) else ""
    return value if value and len(value) <= 24 and " " not in value else DEFAULT_PREFIX


def question_of(query: str, prefix: str) -> str:
    """The question in "<prefix> <question>" (the prefix in any letter case), "" when the query isn't one."""
    query = query.strip()
    head = prefix + " "
    if query[:len(head)].lower() != head.lower():
        return ""
    return query[len(head):].strip()


def match(query: str, prefix: str) -> List[Tuple[Any, ...]]:
    question = question_of(query[:MAX_QUERY], prefix)
    if not question:
        return []
    shown = question if len(question) <= 80 else question[:79] + "…"
    return [("ask:" + question, "Ask KDE AI Chat: " + shown, ICON, EXACT_MATCH, 1.0,
             {"subtext": ("s", "Sends the question to the KDE AI Chat widget and opens it")})]


def actions() -> List[Tuple[str, str, str]]:
    return [("new-chat", "Ask in a new chat", "list-add")]


def run(match_id: str, action_id: str) -> bool:
    """Leaves the question for the widget; False when the match isn't ours."""
    if not match_id.startswith("ask:"):
        return False
    ask_inbox.write_item(match_id[4:].strip(), [], new_chat=(action_id == "new-chat"), send=True)
    return True


def _handle(conn: minidbus.Connection, call: minidbus.Message) -> None:
    iface, member = call.interface, call.member
    if iface == "org.freedesktop.DBus.Peer" and member == "Ping":
        conn.reply(call)
    elif iface == "org.freedesktop.DBus.Introspectable" and member == "Introspect":
        conn.reply(call, "s", (INTROSPECTION,))
    elif call.path == PATH and iface == INTERFACE and member == "Match" and call.body:
        conn.reply(call, "a(sssuda{sv})", (match(str(call.body[0]), read_prefix()),))
    elif call.path == PATH and iface == INTERFACE and member == "Actions":
        conn.reply(call, "a(sss)", (actions(),))
    elif call.path == PATH and iface == INTERFACE and member == "Run" and len(call.body) >= 2:
        try:
            ok = run(str(call.body[0]), str(call.body[1]))
        except (ValueError, OSError) as error:
            conn.reply_error(call, "org.kde.kdeaichat.Error", str(error))
            return
        if ok:
            conn.reply(call)
        else:
            conn.reply_error(call, "org.freedesktop.DBus.Error.InvalidArgs", "not a KDE AI Chat match")
    elif call.path == PATH and iface == INTERFACE and member in ("Teardown", "Config", "SetupMatchSession", "MatchSessionFinished"):
        conn.reply(call)
    else:
        conn.reply_error(call, "org.freedesktop.DBus.Error.UnknownMethod", "unknown method " + member)


def serve(service: str = SERVICE, idle: float = IDLE_SECONDS, address: Optional[str] = None) -> int:
    """Answers calls until nothing has been asked for ``idle`` seconds. Returns an exit code."""
    conn = minidbus.Connection(address)
    try:
        if not conn.request_name(service):
            return 1  # another runner is already serving
        last = time.monotonic()
        while time.monotonic() - last < idle:
            message = conn.read(1.0)
            if message is None or message.type != minidbus.METHOD_CALL:
                continue
            last = time.monotonic()
            _handle(conn, message)
    finally:
        conn.close()
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    return serve(argv[0] if argv else SERVICE)

