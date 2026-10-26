#!/usr/bin/env bash
# A scheduled prompt end to end with a real provider, all in the dev sandbox:
# `kde_ai_helper.py run_schedule <id>` (what the systemd timer starts) answers a
# direct-mode chat with no widget involved, while the dev widget is open; the
# widget then picks the run up from the chat folder's inbox (no polling).
# Prints the run state, the chat file and what is left in the inbox.
#
# Usage: scripts/dev-schedule-e2e.sh <provider-id> <model> [message]
#   e.g. scripts/dev-schedule-e2e.sh nvidia nvidia/nemotron-3.5-bolt-e4b
# DEV_TIMER=1 also fires a second schedule from a transient, test-named systemd
# user timer (kdeaichat-e2e-test-*), with the sandbox's folders in its
# environment; it is stopped and gone afterwards. Real schedules, units and
# chats are never touched: data, config and the unit folder are the sandbox's.
#
# The provider's key is copied from KWallet folder "KDEAIChat" into the dev
# folder "KDEAIChat-dev" inside D-Bus (never printed or put on a command line)
# and that folder is deleted afterwards, as scripts/dev-send.sh does.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="${1:?provider id, e.g. nvidia}"
MODEL="${2:?model}"
DEFAULT_MESSAGE='This is an automated test of a scheduled prompt. Today is {{weekday}} {{date}}. Reply with one short sentence naming the weekday.'
MESSAGE="${3:-$DEFAULT_MESSAGE}"
SANDBOX="$ROOT/build/dev-run/sandbox"
HELPER="$ROOT/org.kde.plasma.kdeaichat/contents/ui/kde_ai_helper.py"
TIMER_UNIT="kdeaichat-e2e-test-$$"

wallet() {  # wallet copy <provider> | wallet clean
    python3 - "$@" <<'PY'
import sys, dbus
w = dbus.Interface(dbus.SessionBus().get_object("org.kde.kwalletd6", "/modules/kwalletd6"), "org.kde.KWallet")
app = "org.kde.plasma.kdeaichat"
h = w.open(w.networkWallet(), dbus.Int64(0), app)
try:
    if sys.argv[1] == "copy":
        if not w.hasEntry(h, "KDEAIChat", sys.argv[2], app):
            sys.exit("no key for %s in KWallet folder KDEAIChat" % sys.argv[2])
        w.createFolder(h, "KDEAIChat-dev", app)
        if int(w.writePassword(h, "KDEAIChat-dev", sys.argv[2], w.readPassword(h, "KDEAIChat", sys.argv[2], app), app)) != 0:
            sys.exit("could not copy the key")
    else:
        w.removeFolder(h, "KDEAIChat-dev", app)
finally:
    w.close(h, False, app)
PY
}
cleanup() {
    systemctl --user stop "$TIMER_UNIT.timer" "$TIMER_UNIT.service" >/dev/null 2>&1 || true
    systemctl --user reset-failed "$TIMER_UNIT.timer" "$TIMER_UNIT.service" >/dev/null 2>&1 || true
    wallet clean
}
trap cleanup EXIT

# plasmawindowed runs one instance per applet id: a second dev run would only
# hand over to the first one (another worktree's, say) and write nothing.
if pgrep -f "^plasmawindowed org.kde.plasma.kdeaichat.dev" >/dev/null; then
    echo "another dev widget (plasmawindowed org.kde.plasma.kdeaichat.dev) is running; try again when it is done" >&2
    exit 2
fi

# The sandbox chat and config (first run creates them).
"$ROOT/scripts/dev-run.sh" 15 >/dev/null || true

PRESET="$(node -e '
const fs = require("fs"), vm = require("vm"), ctx = {};
vm.runInNewContext(fs.readFileSync(process.argv[1], "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "") + "\nthis.p = presetById(process_arg);", Object.assign(ctx, {process_arg: process.argv[2]}));
if (!ctx.p) { console.error("unknown provider preset: " + process.argv[2]); process.exit(1); }
console.log(JSON.stringify(ctx.p));' "$ROOT/org.kde.plasma.kdeaichat/contents/ui/ProviderService.js" "$PROVIDER")"

python3 - "$SANDBOX" "$PRESET" "$MODEL" "$MESSAGE" "$ROOT/org.kde.plasma.kdeaichat/contents/ui" <<'PY'
import datetime as dt, json, re, sys
sandbox, preset, model, message, ui = sys.argv[1:]
sys.path.insert(0, ui)
from kdeaichat import qsettings_ini
preset = json.loads(preset)
chats = f"{sandbox}/data/kdeaichat/chats/applet-4"
chat_id = json.loads(qsettings_ini.read_value(f"{chats}/index.ini", "sessions"))[0]["value"]
entry = {"id": preset["id"], "name": preset["name"], "type": preset["type"], "baseUrl": preset["baseUrl"], "model": model}
if preset.get("headers"):
    entry["headers"] = preset["headers"]
providers = json.dumps([entry]).replace("\\", "\\\\")
path = f"{sandbox}/config/plasmawindowedrc"
config = re.sub(r"^(providersJson|provider)=.*\n", "", open(path, encoding="utf-8").read(), flags=re.M)
group = "[Applets][4][Configuration][General]\n"
open(path, "w", encoding="utf-8").write(config.replace(group, group + f"provider={preset['id']}\nprovidersJson={providers}\n"))
now = dt.datetime.now().replace(second=0, microsecond=0)
def schedule(sid, at):
    return {"id": sid, "name": "E2E " + sid, "enabled": True, "chatId": chat_id, "message": message, "notify": True,
            "rules": [{"kind": "daily", "times": [at.strftime("%H:%M")]}], "catchUp": {"enabled": True, "withinHours": 1},
            "createdAt": (now - dt.timedelta(minutes=30)).isoformat(), "editedAt": (now - dt.timedelta(minutes=30)).isoformat()}
store = {"version": 2, "settings": {"historyLimit": 50},
         "schedules": [schedule("e2e-direct", now - dt.timedelta(minutes=2)), schedule("e2e-timer", now - dt.timedelta(minutes=1))]}
json.dump(store, open(f"{sandbox}/data/kdeaichat/schedules.v2.json", "w"), indent=1)
print("chat:", chat_id)
PY

wallet copy "$PROVIDER"
export XDG_DATA_HOME="$SANDBOX/data" XDG_CONFIG_HOME="$SANDBOX/config"
export KDEAICHAT_WALLET_FOLDER="KDEAIChat-dev" KDEAICHAT_UNIT_DIR="$SANDBOX/units" KDEAICHAT_SYSTEMCTL=true

# The widget runs for 45 s; the scheduled run happens while it is open.
(unset XDG_DATA_HOME XDG_CONFIG_HOME; DEV_KEEP=1 "$ROOT/scripts/dev-run.sh" 45 "$ROOT/build/dev-run/schedule-e2e.png" | tail -2) &
WIDGET=$!
sleep 12
echo "--- run_schedule e2e-direct:"
python3 "$HELPER" run_schedule e2e-direct

if [ "${DEV_TIMER:-0}" = "1" ]; then
    echo "--- transient timer $TIMER_UNIT fires run_schedule e2e-timer in 3 s"
    systemd-run --user --quiet --unit="$TIMER_UNIT" --on-active=3s --timer-property=AccuracySec=1s \
        --setenv=XDG_DATA_HOME="$XDG_DATA_HOME" --setenv=XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
        --setenv=KDEAICHAT_WALLET_FOLDER=KDEAIChat-dev --setenv=KDEAICHAT_UNIT_DIR="$KDEAICHAT_UNIT_DIR" \
        --setenv=KDEAICHAT_SYSTEMCTL=true /usr/bin/python3 "$HELPER" run_schedule e2e-timer
    for _ in $(seq 1 60); do
        grep -q '"lastStatus": "\(ok\|error\|skipped\)' "$XDG_DATA_HOME/kdeaichat/schedule-runs/e2e-timer.json" 2>/dev/null && break
        sleep 1
    done
fi
wait "$WIDGET" || true

python3 - "$SANDBOX" "$ROOT/org.kde.plasma.kdeaichat/contents/ui" <<'PY'
import glob, json, os, sys
sandbox, ui = sys.argv[1:]
sys.path.insert(0, ui)
from kdeaichat import qsettings_ini
data = f"{sandbox}/data/kdeaichat"
for path in sorted(glob.glob(f"{data}/schedule-runs/*.json")):
    state = json.load(open(path))
    print(f"--- {os.path.basename(path)}: runCount={state['runCount']} lastStatus={state['lastStatus']!r}")
    for h in state["history"]:
        print(f"    {h['scheduledFor']} -> {h['status']}")
print("--- chat file:")
for path in glob.glob(f"{data}/chats/applet-4/chat-*.ini"):
    for m in json.loads(qsettings_ini.read_value(path, "messages", "[]")):
        mark = " [scheduled: %s]" % m.get("scheduleName") if m.get("scheduled") else ""
        print(f"[{m.get('role')}]{mark} model={m.get('model')!r} tokens={m.get('tokens')}: {str(m.get('content', ''))[:300]!r}")
print("--- inbox left:", sorted(os.listdir(f"{data}/chats/applet-4/inbox")))
PY
