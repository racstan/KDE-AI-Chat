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
# The widget types and sends the message itself (DEV_SEND_MESSAGE in dev-run.sh), so no clicking is needed.
# DEV_AUTO_ANSWER="Tea" answers the model's ask_user questions with that text (see dev-run.sh).
# DEV_PROJECT="Answer in French." puts the chat in a project with those instructions.
# DEV_CONFIG=$'userName=Ana\naiName=Nova' adds settings (one key=value per line) to the sandbox config.
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

# The provider's preset (URL, type, headers) straight from ProviderService.js.
PRESET="$(node -e '
const fs = require("fs"), vm = require("vm"), ctx = {};
vm.runInNewContext(fs.readFileSync(process.argv[1], "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "") + "\nthis.p = presetById(process_arg);", Object.assign(ctx, {process_arg: process.argv[2]}));
if (!ctx.p) { console.error("unknown provider preset: " + process.argv[2]); process.exit(1); }
console.log(JSON.stringify(ctx.p));' "$ROOT/org.kde.plasma.kdeaichat/contents/ui/ProviderService.js" "$PROVIDER")"

python3 - "$SANDBOX" "$PRESET" "$MODEL" "$MESSAGE" <<'PY'
import json, os, re, sys
sandbox, preset, model, message = sys.argv[1:]
preset = json.loads(preset)
index = open(f"{sandbox}/data/kdeaichat/chats/applet-4/index.ini", encoding="utf-8").read()
raw = re.search(r"^sessions=(.*)$", index, re.M).group(1)
if raw.startswith('"'):
    raw = raw[1:-1].replace('\\"', '"').replace("\\\\", "\\")
chat_id = json.loads(raw)[0]["value"]
entry = {"id": preset["id"], "name": preset["name"], "type": preset["type"], "baseUrl": preset["baseUrl"], "model": model}
if preset.get("headers"):
    entry["headers"] = preset["headers"]
providers = json.dumps([entry]).replace("\\", "\\\\")
path = f"{sandbox}/config/plasmawindowedrc"
config = open(path, encoding="utf-8").read()
extra = [line for line in os.environ.get("DEV_CONFIG", "").split("\n") if re.match(r"^[A-Za-z]+=", line)]
keys = "|".join(["providersJson", "provider"] + [line.split("=", 1)[0] for line in extra])
config = re.sub(r"^(" + keys + r")=.*\n", "", config, flags=re.M)
group = "[Applets][4][Configuration][General]\n"
config = config.replace(group, group + f"provider={preset['id']}\nprovidersJson={providers}\n" + "".join(l + "\n" for l in extra))
open(path, "w", encoding="utf-8").write(config)

# DEV_PROJECT="instructions": the chat is put in a project "Dev project" with
# those instructions (projects.ini next to the chats, chat/Projects.js).
instructions = os.environ.get("DEV_PROJECT", "")
if instructions:
    def ini_string(value):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    chats_dir = f"{sandbox}/data/kdeaichat/chats/applet-4"
    project = {"id": "p-dev", "name": "Dev project", "color": "#3daee9", "instructions": instructions,
               "folder": "", "provider": "", "model": "", "createdAt": 1}
    with open(f"{chats_dir}/projects.ini", "w", encoding="utf-8") as f:
        f.write("[General]\nprojects=" + ini_string(json.dumps([project])) + "\nversion=1\n")
    sessions = json.loads(raw)
    sessions[0]["projectId"] = "p-dev"
    index = re.sub(r"^sessions=.*$", lambda m: "sessions=" + ini_string(json.dumps(sessions, separators=(",", ":"))), index, flags=re.M)
    open(f"{chats_dir}/index.ini", "w", encoding="utf-8").write(index)
PY

wallet copy "$PROVIDER"
DEV_KEEP=1 DEV_SEND_MESSAGE="$MESSAGE" "$ROOT/scripts/dev-run.sh" "$SECONDS_TO_RUN" | tail -1

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
                for call_id, tool in (m.get("tools") or {}).items():
                    print(f"    tool {tool.get('name')} [{tool.get('status')}] {tool.get('detail', '')!r} -> {str(tool.get('output', ''))[:120]!r}")
                if m.get("role") == "question_request":
                    print(f"    question [{m.get('status')}] answer={m.get('submittedAnswer')!r}")
PY
