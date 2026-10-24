#!/usr/bin/env bash
# Pi mode end to end: runs the widget in the dev sandbox in Pi mode, sends one
# message (as a scheduler trigger) and prints what Pi was asked and the saved
# chat. By default `pi` is scripts/dev-pi-mock.py replaying a real capture
# (KDEAICHAT_PI_MOCK_FIXTURE picks another); PI_E2E_REAL=1 uses the installed
# `pi` instead (point PI_CODING_AGENT_DIR at a test config to keep yours out).
#
# Usage: scripts/dev-pi-e2e.sh [message] [provider] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MESSAGE="${1:-Create hello.txt containing hi, then say done.}"
SANDBOX="$ROOT/build/dev-run/sandbox"
WORK="$ROOT/build/dev-run/pi-work"
export KDEAICHAT_PI_MOCK_LOG="$ROOT/build/dev-run/pi-mock.log"

if [ "${PI_E2E_REAL:-0}" != "1" ]; then
    mkdir -p "$ROOT/build/dev-run/pi-bin"
    ln -sf "$ROOT/scripts/dev-pi-mock.py" "$ROOT/build/dev-run/pi-bin/pi"
    export PATH="$ROOT/build/dev-run/pi-bin:$PATH"
fi
rm -rf "$SANDBOX" "$WORK" "$KDEAICHAT_PI_MOCK_LOG"
mkdir -p "$WORK"
stop_bridge() {
    XDG_DATA_HOME="$SANDBOX/data" python3 "$ROOT/org.kde.plasma.kdeaichat/contents/ui/kde_ai_helper.py" pi_bridge_stop >/dev/null || true
}
trap stop_bridge EXIT
"$ROOT/scripts/dev-run.sh" 8 >/dev/null || true

python3 - "$SANDBOX" "$WORK" "$MESSAGE" "${2:-}" "${3:-}" <<'PY'
import json, os, re, sys
sandbox, work, message, provider, model = sys.argv[1:]
path = f"{sandbox}/data/kdeaichat/chats/applet-4/index.ini"
index = open(path, encoding="utf-8").read()
match = re.search(r"^sessions=(.*)$", index, re.M)
raw = match.group(1)
if raw.startswith('"'):
    raw = raw[1:-1].replace('\\"', '"').replace("\\\\", "\\")
sessions = json.loads(raw)
sessions[0]["source"] = "pi"
encoded = json.dumps(sessions, separators=(",", ":")).replace("\\", "\\\\").replace('"', '\\"')
open(path, "w", encoding="utf-8").write(index.replace(match.group(0), 'sessions="' + encoded + '"'))
config = f"{sandbox}/config/plasmawindowedrc"
text = open(config, encoding="utf-8").read()
group = "[Applets][4][Configuration][General]\n"
text = text.replace(group, group + f"usePi=true\nopenCodeWorkspaceCwd={work}\npiProvider={provider}\npiModel={model}\nschedulerEnabled=true\n")
open(config, "w", encoding="utf-8").write(text)
os.makedirs(f"{sandbox}/data/kdeaichat/pending", exist_ok=True)
with open(f"{sandbox}/data/kdeaichat/pending/e2e.json", "w") as f:
    json.dump({"chatId": sessions[0]["value"], "message": message, "name": "e2e"}, f)
PY

DEV_KEEP=1 "$ROOT/scripts/dev-run.sh" "${PI_E2E_SECONDS:-20}" | tail -1

if [ -f "$KDEAICHAT_PI_MOCK_LOG" ]; then
    echo "--- pi was asked:"
    cut -c1-160 "$KDEAICHAT_PI_MOCK_LOG"
fi
echo "--- folder: $(ls "$WORK" | tr '\n' ' ')"
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
                print(f"[{m.get('role')}] {m.get('content', '')[:90]!r} model={m.get('model', '')!r} status={m.get('status', '')} "
                      f"reasoning={len(m.get('reasoning') or '')} chars context={m.get('contextItems')} files={m.get('filesChanged')} tokens={m.get('tokens')}")
PY
