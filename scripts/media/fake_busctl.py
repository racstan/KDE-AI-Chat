#!/usr/bin/env python3
"""Stand-in for busctl in the docs media: no D-Bus is touched, nothing records or plays.

Speech Note looks idle and ready (State 3) and plasmashell is "running". Dictation: a listening task is
started and, when it is stopped, the monitor prints one decoded text (KDEAICHAT_FAKE_DICTATION), as the
real Speech Note service would. Every other call fails.
"""
import json
import os
import sys
import time

args = [a for a in sys.argv[1:] if not a.startswith("--")]
TEXT = os.environ.get("KDEAICHAT_FAKE_DICTATION", "Remind me what we decided about the trip budget")


def out(kind, data):
    print(json.dumps({"type": kind, "data": data}), flush=True)


if not args:
    sys.exit(1)
if args[0] == "get-property" and args[-1] == "State":
    out("u", 3)
elif args[0] == "get-property" and args[-1] == "CurrentTask":
    out("i", -1)
elif args[0] == "call" and "NameHasOwner" in args:
    out("b", [True])
elif args[0] == "call" and args[1] == "net.mkiol.Speech":
    member = args[4] if len(args) > 4 else ""
    out("i", [1] if member in ("SttStartListen", "KeepAliveTask", "KeepAliveService") else [0])
elif args[0] == "monitor":
    # ready() waits to see its KeepAliveService call go by; the text follows the SttStopListen call.
    print(json.dumps({"type": "method_call", "member": "KeepAliveService"}), flush=True)
    time.sleep(0.8)
    print(json.dumps({"type": "signal", "interface": "org.mkiol.Speech", "member": "SttTextDecoded",
                      "payload": {"data": [TEXT, "en", 1]}}), flush=True)
    time.sleep(5)
else:
    sys.exit(1)
