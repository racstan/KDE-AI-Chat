#!/usr/bin/env python3
"""A fake `busctl --user --json=short call ...` for kwalletd6 that keeps entries in the JSON file FAKE_WALLET_FILE
({folder: {entry: value}}); FAKE_WALLET=open|closed|down (closed: isOpen says no, but open() still works, as after an unlock)."""
import json
import os
import sys

args = sys.argv[1:]
call = args[args.index("call") + 1:]
method, params = call[3], call[5:]
state = os.environ.get("FAKE_WALLET", "open")
if state == "down":
    sys.exit(1)
path = os.environ["FAKE_WALLET_FILE"]
try:
    with open(path) as f:
        data = json.load(f)
except OSError:
    data = {}


def out(kind, value):
    print(json.dumps({"type": kind, "data": [value]}))


def save():
    with open(path, "w") as f:
        json.dump(data, f)


if method == "networkWallet":
    out("s", "kdewallet")
elif method == "isOpen":
    out("b", state == "open")
elif method == "open":
    out("i", 7)
elif method == "hasFolder":
    out("b", params[1] in data)
elif method == "createFolder":
    data.setdefault(params[1], {})
    save()
    out("b", True)
elif method == "hasEntry":
    out("b", params[2] in data.get(params[1], {}))
elif method == "readPassword":
    out("s", data.get(params[1], {}).get(params[2], ""))
elif method == "writePassword":
    data.setdefault(params[1], {})[params[2]] = params[3]
    save()
    out("i", 0)
elif method == "removeEntry":
    data.get(params[1], {}).pop(params[2], None)
    save()
    out("i", 0)
elif method == "close":
    out("i", 0)
else:
    sys.exit(1)
