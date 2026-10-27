"""Stand-in helper for tst_helper_runner.qml: reports what it was given.

Any command prints one JSON line: its argv, whether the payload file existed
when it started, the decoded payload and whether the file was gone after
reading. `stat_file` / `unlink_file` (payload {path}) inspect and remove a
file the real helper wrote.
"""
import json
import os
import sys

UI = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI)
import kde_ai_helper  # noqa: E402

raw = sys.argv[2] if len(sys.argv) > 2 else ""
folder = os.environ.get("XDG_RUNTIME_DIR") or "/tmp/runtime-" + os.environ.get("USER", "")
existed = raw.startswith("@") and os.path.exists(os.path.join(folder, raw[1:]))
payload = kde_ai_helper._decode_payload(raw)
gone = not raw.startswith("@") or not os.path.exists(os.path.join(folder, raw[1:]))
result = {"argv": sys.argv[1:], "existed": existed, "gone": gone, "payload": payload}
if sys.argv[1] == "stat_file":
    result["size"] = os.path.getsize(payload["path"]) if os.path.exists(payload["path"]) else -1
if sys.argv[1] == "unlink_file" and os.path.exists(payload["path"]):
    os.unlink(payload["path"])
print(json.dumps(result))
