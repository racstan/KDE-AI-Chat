#!/usr/bin/env bash
# Makes ONE real picture with AI Horde through the widget's /image path, in the
# dev sandbox, then prints the chat and the saved image files.
#
# Usage: scripts/dev-image.sh ["prompt"] [seconds]
#
# AI Horde is used anonymously (its documented key 0000000000; no KWallet key
# is read or written). The prompt goes to AI Horde and a volunteer's computer,
# and anonymous images are shared with LAION: use a harmless prompt. Each run
# is one real job on a community service, so keep runs rare.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT="${1:-a small red lighthouse on a rock by the sea, watercolour}"
SECONDS_TO_RUN="${2:-120}"
SANDBOX="$ROOT/build/dev-run/sandbox"

# First run creates the sandbox config and an empty chat.
"$ROOT/scripts/dev-run.sh" 8 >/dev/null || true

# AI Horde as the (switched on) image service that /image uses.
python3 - "$SANDBOX" <<'PY'
import json, re, sys
sandbox = sys.argv[1]
entry = {"id": "aihorde", "name": "AI Horde (images)", "type": "image", "service": "horde",
         "baseUrl": "https://aihorde.net/api/v2", "model": "stable_diffusion", "accepted": True,
         "options": {"width": 512, "height": 512, "steps": 22}}
providers = json.dumps([entry]).replace("\\", "\\\\")
path = f"{sandbox}/config/plasmawindowedrc"
config = open(path, encoding="utf-8").read()
config = re.sub(r"^(providersJson|imageProvider)=.*\n", "", config, flags=re.M)
group = "[Applets][4][Configuration][General]\n"
config = config.replace(group, group + f"imageProvider=aihorde\nprovidersJson={providers}\n")
open(path, "w", encoding="utf-8").write(config)
PY

DEV_KEEP=1 DEV_IMAGE_PROMPT="$PROMPT" "$ROOT/scripts/dev-run.sh" "$SECONDS_TO_RUN" | tail -3 || true

python3 - "$SANDBOX" <<'PY'
import glob, json, os, sys
chats = f"{sys.argv[1]}/data/kdeaichat/chats/applet-4"
for path in glob.glob(f"{chats}/chat-*.ini"):
    for line in open(path, encoding="utf-8"):
        if line.startswith("messages="):
            raw = line[len("messages="):].rstrip("\n")
            if raw.startswith('"'):
                raw = raw[1:-1].replace('\\"', '"').replace("\\\\", "\\")
            for m in json.loads(raw):
                print(f"[{m.get('role')}]: {str(m.get('content', ''))[:300]}")
                for image in m.get("images") or []:
                    print("    image", json.dumps(image))
for path in sorted(glob.glob(f"{chats}/images/*/*")):
    print("file", os.path.relpath(path, chats), os.path.getsize(path), "bytes", oct(os.stat(path).st_mode & 0o777))
PY
