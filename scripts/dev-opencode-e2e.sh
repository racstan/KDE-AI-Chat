#!/usr/bin/env bash
# OpenCode mode end to end, without a real model: runs the widget in the dev
# sandbox against scripts/dev-opencode-mock.py, sends one message (typed
# by the widget itself, DEV_SEND_MESSAGE) and prints the saved chat and the requests the widget made.
#
# Usage: scripts/dev-opencode-e2e.sh [port]   (default 4921)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${1:-4921}"
SANDBOX="$ROOT/build/dev-run/sandbox"
LOG="$ROOT/build/dev-run/opencode-mock.log"

python3 "$ROOT/scripts/dev-opencode-mock.py" "$PORT" > "$LOG" 2>&1 &
MOCK=$!
trap 'kill $MOCK 2>/dev/null || true' EXIT

rm -rf "$SANDBOX"
"$ROOT/scripts/dev-run.sh" 8 >/dev/null || true

python3 - "$SANDBOX" "$PORT" <<'PY'
import json, os, re, sys
sandbox, port = sys.argv[1:]
path = f"{sandbox}/data/kdeaichat/chats/applet-4/index.ini"
index = open(path, encoding="utf-8").read()
match = re.search(r"^sessions=(.*)$", index, re.M)
raw = match.group(1)
if raw.startswith('"'):
    raw = raw[1:-1].replace('\\"', '"').replace("\\\\", "\\")
sessions = json.loads(raw)
sessions[0]["source"] = "opencode"
encoded = json.dumps(sessions, separators=(",", ":")).replace("\\", "\\\\").replace('"', '\\"')
open(path, "w", encoding="utf-8").write(index.replace(match.group(0), 'sessions="' + encoded + '"'))
config = f"{sandbox}/config/plasmawindowedrc"
text = open(config, encoding="utf-8").read()
group = "[Applets][4][Configuration][General]\n"
text = text.replace(group, group + f"useOpenCode=true\nopenCodeUrl=http://127.0.0.1:{port}\nopenCodeWorkspaceCwd=/tmp/kdeaichat-mock-work\n"
                    "openCodeProvider=mockprov\nopenCodeModel=mock-model\n")
open(config, "w", encoding="utf-8").write(text)
PY

DEV_KEEP=1 DEV_SEND_MESSAGE="Create hello.txt" "$ROOT/scripts/dev-run.sh" 20 | tail -1

echo "--- requests:"
python3 - "$LOG" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    try:
        o = json.loads(line)
    except ValueError:
        continue
    print(o["method"], o["path"], o["query"][:50], json.dumps(o.get("body"))[:110])
PY
echo "--- chat:"
python3 - "$SANDBOX" <<'PY'
import glob, json, sys
for path in glob.glob(f"{sys.argv[1]}/data/kdeaichat/chats/applet-4/chat-*.ini"):
    for line in open(path, encoding="utf-8"):
        if line.startswith("messages="):
            raw = line[len("messages="):].rstrip("\n")
            if raw.startswith('"'):
                raw = raw[1:-1].replace('\\"', '"').replace("\\\\", "\\")
            for m in json.loads(raw):
                print(f"[{m.get('role')}] {m.get('content', '')[:70]!r} status={m.get('status', '')} "
                      f"reasoning={m.get('reasoning', '')!r} context={m.get('contextItems')} tokens={m.get('tokens')}")
PY
