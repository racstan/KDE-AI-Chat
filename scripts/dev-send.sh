#!/usr/bin/env bash
# Sends one real message through the widget's own send path, in the dev
# sandbox, and prints the conversation. For checking providers end to end.
#
# Usage: scripts/dev-send.sh <provider-id> <model> [message] [seconds]
#   e.g. scripts/dev-send.sh openrouter openrouter/auto
#
# The provider's API key is copied from your KWallet folder "KDEAIChat" into
# the dev folder "KDEAIChat-dev" inside D-Bus (never printed or put on a
# command line) and that folder is deleted afterwards, even on failure.
# The message is delivered as a scheduler trigger, so no clicking is needed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROVIDER="${1:?provider id, e.g. openrouter}"
MODEL="${2:?model, e.g. openrouter/auto}"
MESSAGE="${3:-This is an automated test of a KDE desktop widget. Reply with one short sentence confirming you received it.}"
SECONDS_TO_RUN="${4:-45}"
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
"$ROOT/scripts/dev-run.sh" 8 >/dev/null || true

python3 - "$SANDBOX" "$PROVIDER" "$MODEL" "$MESSAGE" <<'PY'
import json, os, re, sys
sandbox, provider, model, message = sys.argv[1:]
index = open(f"{sandbox}/data/kdeaichat/chats/applet-4/index.ini", encoding="utf-8").read()
raw = re.search(r"^sessions=(.*)$", index, re.M).group(1)
if raw.startswith('"'):
    raw = raw[1:-1].replace('\\"', '"').replace("\\\\", "\\")
chat_id = json.loads(raw)[0]["value"]
model_keys = {"openai": "model", "anthropic": "anthropicModel", "openrouter": "openRouterModel", "groq": "groqModel",
              "deepseek": "deepSeekModel", "mistral": "mistralModel", "nvidia": "nvidiaModel", "google": "googleModel"}
path = f"{sandbox}/config/plasmawindowedrc"
config = open(path, encoding="utf-8").read()
group = "[Applets][4][Configuration][General]\n"
config = config.replace(group, group + f"provider={provider}\n{model_keys.get(provider, 'model')}={model}\nschedulerEnabled=true\n")
open(path, "w", encoding="utf-8").write(config)
os.makedirs(f"{sandbox}/data/kdeaichat/pending", exist_ok=True)
with open(f"{sandbox}/data/kdeaichat/pending/dev-send.json", "w") as f:
    json.dump({"chatId": chat_id, "message": message, "name": "dev-send"}, f)
PY

wallet copy "$PROVIDER"
DEV_KEEP=1 "$ROOT/scripts/dev-run.sh" "$SECONDS_TO_RUN" | tail -1

python3 - "$SANDBOX" <<'PY'
import glob, json, sys
for path in glob.glob(f"{sys.argv[1]}/data/kdeaichat/chats/applet-4/chat-*.ini"):
    for line in open(path, encoding="utf-8"):
        if line.startswith("messages="):
            raw = line[len("messages="):].rstrip("\n")
            if raw.startswith('"'):
                raw = raw[1:-1].replace('\\"', '"').replace("\\\\", "\\")
            for m in json.loads(raw):
                extra = f" model={m.get('model')} tokens={m.get('tokens')}" if m.get("role") == "assistant" else ""
                print(f"[{m.get('role')}]{extra}: {str(m.get('content', ''))[:400]}")
PY
