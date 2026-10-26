#!/usr/bin/env bash
# Runs the schedule editor's "Describe when" once with a real model, in the
# dev sandbox, and prints what the model answered and the rules it produced.
#
# Usage: scripts/dev-describe.sh <provider-id> <model> "sentence" ["answer"] [seconds] [screenshot]
#   e.g. scripts/dev-describe.sh nvidia nvidia/nemotron-3.5-bolt-e4b "weekdays at 9 and Sunday at noon"
#
# The provider's key is copied into the dev wallet folder "KDEAIChat-dev" and
# removed afterwards, as in scripts/dev-send.sh (never printed). "answer"
# answers the model's first clarifying question. Nothing is saved: the editor
# is left open for review, so no schedule or timer is created.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="${1:?provider id, e.g. nvidia}"
MODEL="${2:?model}"
SENTENCE="${3:?sentence, e.g. weekdays at 9 and Sunday at noon}"
ANSWER="${4:-}"
SECONDS_TO_RUN="${5:-60}"
SHOT="${6:-$ROOT/build/dev-run/describe.png}"   # saved as describe-question.png / describe-rules.png
SANDBOX="$ROOT/build/dev-run/sandbox"

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
trap 'wallet clean' EXIT

# First run creates the sandbox config and an empty chat.
for _ in 1 2 3; do   # plasmawindowed does not always write its config before it is stopped
    DEV_SCREENSHOT=0 "$ROOT/scripts/dev-run.sh" 8 >/dev/null || true
    [ -f "$SANDBOX/config/plasmawindowedrc" ] && break
done

PRESET="$(node -e '
const fs = require("fs"), vm = require("vm"), ctx = {};
vm.runInNewContext(fs.readFileSync(process.argv[1], "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "") + "\nthis.p = presetById(process_arg);", Object.assign(ctx, {process_arg: process.argv[2]}));
if (!ctx.p) { console.error("unknown provider preset: " + process.argv[2]); process.exit(1); }
console.log(JSON.stringify(ctx.p));' "$ROOT/org.kde.plasma.kdeaichat/contents/ui/ProviderService.js" "$PROVIDER")"

python3 - "$SANDBOX" "$PRESET" "$MODEL" <<'PY'
import json, re, sys
sandbox, preset, model = sys.argv[1:]
preset = json.loads(preset)
entry = {"id": preset["id"], "name": preset["name"], "type": preset["type"], "baseUrl": preset["baseUrl"], "model": model}
if preset.get("headers"):
    entry["headers"] = preset["headers"]
providers = json.dumps([entry]).replace("\\", "\\\\")
path = f"{sandbox}/config/plasmawindowedrc"
config = open(path, encoding="utf-8").read()
config = re.sub(r"^(providersJson|provider)=.*\n", "", config, flags=re.M)
group = "[Applets][4][Configuration][General]\n"
config = config.replace(group, group + f"provider={preset['id']}\nprovidersJson={providers}\n")
open(path, "w", encoding="utf-8").write(config)
PY

wallet copy "$PROVIDER"
# No desktop screenshot (it could catch another window): the editor saves
# itself to <screenshot>-question.png / -rules.png.
rm -f "${SHOT%.png}-question.png" "${SHOT%.png}-rules.png"
DEV_SCHEDULE_DESCRIBE="$SENTENCE" DEV_SCHEDULE_ANSWER="$ANSWER" DEV_SCHEDULE_SHOT="$SHOT" DEV_SCREENSHOT=0 DEV_KEEP=1 \
    "$ROOT/scripts/dev-run.sh" "$SECONDS_TO_RUN" | tail -n +2 || true
grep -o "DEV_DESCRIBE.*" "$ROOT/build/dev-run/qml.log" || echo "no DEV_DESCRIBE lines in build/dev-run/qml.log"
ls "${SHOT%.png}"-*.png 2>/dev/null || true
