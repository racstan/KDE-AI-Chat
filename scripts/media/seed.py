#!/usr/bin/env python3
"""Seeds the dev-run sandbox with made-up demo data for the docs media.

Usage: seed.py <sandbox> <mock-port>

Writes, all under <sandbox>: six chats for the widget plasmawindowed starts as
applet 4 (chats/applet-4/index.ini + chat-<id>.ini, the format of
store/ChatStore.qml), the widget's settings (config/plasmawindowedrc: names,
avatar, templates and a keyless local provider pointing at the mock server),
memories and one schedule (through the helper's own commands, so their
formats can't drift). Made-up names only (Alex, Nova); nothing here needs a
network, a model or a key.
"""
import base64
import shutil
import json
import os
import subprocess
import sys
import time

SANDBOX, PORT = os.path.abspath(sys.argv[1]), sys.argv[2]
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
HELPER = os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui", "kde_ai_helper.py")
# The widget runs with HOME=<sandbox>/home (dev-media.sh), so its folders read ~/.local/share/kdeaichat like a user's.
HOME = os.path.join(SANDBOX, "home")
DATA, CONFIG, CACHE = (os.path.join(HOME, ".local", "share"), os.path.join(HOME, ".config"), os.path.join(HOME, ".cache"))
PROJECT = os.path.join(HOME, "Projects", "kdeaichat")   # the demo project the agents work in
CHATS = os.path.join(DATA, "kdeaichat", "chats", "applet-4")
MODEL = "nova-demo"
NOW = int(time.time() * 1000)
MIN, HOUR, DAY = 60_000, 3_600_000, 86_400_000

RUST = """A lifetime is the compiler's name for **how long a reference is valid**. Rust checks that no reference outlives the value it points to.

Here is the classic case:

```rust
fn longest<'a>(a: &'a str, b: &'a str) -> &'a str {
    if a.len() >= b.len() { a } else { b }
}
```

The `'a` says: *the result lives no longer than the shorter of the two inputs.*

Rules of thumb:

- Most lifetimes are **inferred**, so you rarely write them.
- Write one when a function returns a reference and has more than one input reference.
- A struct that holds a reference needs a lifetime parameter too.
- `'static` means "valid for the whole program", e.g. string literals."""

SORT = """Use `sort` and `uniq`:

```bash
sort names.txt | uniq -c | sort -rn | head
```

That counts each line and shows the most common first."""

LISBON = """Three days is a good length. A simple plan:

1. **Day 1**: Alfama on foot, the castle, then fado in the evening.
2. **Day 2**: Belem (the tower, the monastery, pasteis de nata).
3. **Day 3**: a day trip to Sintra by train.

Book Sintra's palaces ahead if you travel in summer."""

MEALS = """Here is a simple week, built around cooking twice:

- **Mon / Tue**: lentil curry (cook a big pot)
- **Wed**: omelette and salad
- **Thu / Fri**: roasted vegetables with rice
- **Weekend**: something fresh, shop on Saturday"""

REPLY = """Hi Sam, thanks for the reminder. The invoice was sent on the 3rd and is due on the 17th. I will check with accounting and confirm by Friday.

Best,
Alex"""

RENAME = """Here is a small script that renames photos by their date:

```bash
#!/usr/bin/env bash
for f in *.jpg; do
    d=$(date -r "$f" +%Y-%m-%d)
    mv -n "$f" "${d}_$f"
done
```

`-n` stops it overwriting a file that already exists."""


def chat(cid, title, age_ms, pairs):
    messages, at = [], NOW - age_ms
    for question, answer in pairs:
        messages.append({"role": "user", "content": question, "at": at})
        at += 20_000
        messages.append({"role": "assistant", "content": answer, "model": MODEL, "at": at,
                         "tokens": {"input": 140 + len(question), "output": 90 + len(answer) // 4}})
        at += 90_000
    return {"id": cid, "title": title, "created": NOW - age_ms - MIN, "updated": at, "messages": messages}


CHAT_LIST = [
    chat("s-1000000000001-0001", "Rust lifetimes, explained", 6 * MIN,
         [("Can you explain Rust lifetimes in simple terms?", RUST)]),
    chat("s-1000000000002-0002", "Three days in Lisbon", 3 * HOUR,
         [("Plan a three-day trip to Lisbon for me.", LISBON)]),
    chat("s-1000000000003-0003", "Count duplicate lines", DAY + HOUR,
         [("How do I count duplicate lines in a file?", SORT)]),
    chat("s-1000000000004-0004", "Meal plan for the week", 2 * DAY,
         [("Suggest a cheap meal plan for the week.", MEALS)]),
    chat("s-1000000000005-0005", "Reply to Sam about the invoice", 4 * DAY,
         [("Write a short, polite reply to Sam about the invoice due on the 17th.", REPLY)]),
    chat("s-1000000000006-0006", "Rename photos by date", 9 * DAY,
         [("A bash script to prefix my photos with their date?", RENAME)]),
]


def ini_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


os.makedirs(CHATS, exist_ok=True)
sessions = [{"value": c["id"], "text": c["title"], "createdAt": c["created"], "updatedAt": c["updated"],
             "archived": False, "source": "provider", "projectId": "", "openCodeSessionId": "",
             "openCodeWorkspaceCwd": ""} for c in CHAT_LIST]
sessions.sort(key=lambda s: -s["updatedAt"])
index = "[General]\nsessions=" + ini_string(json.dumps(sessions, separators=(",", ":"))) + "\nversion=1\n"
for name in ("index.ini", "index.ini.bak"):
    with open(os.path.join(CHATS, name), "w", encoding="utf-8") as f:
        f.write(index)
for c in CHAT_LIST:
    with open(os.path.join(CHATS, "chat-%s.ini" % c["id"]), "w", encoding="utf-8") as f:
        f.write("[General]\nmessages=" + ini_string(json.dumps(c["messages"], separators=(",", ":"))) + "\n")

shutil.copy(os.path.join(ROOT, "scripts", "media", "lighthouse.png"), os.path.join(CHATS, "demo-picture.png"))   # chat-image

# The animated avatar of the video (an owner-supplied GIF, never committed): copied into the sandbox when it exists.
AVATAR = os.environ.get("DEV_MEDIA_AVATAR", "/home/home/Desktop/oie_14175751vZSQRLEn.gif")
if os.path.isfile(AVATAR):
    os.makedirs(os.path.join(DATA, "avatars"), exist_ok=True)
    shutil.copy(AVATAR, os.path.join(DATA, "avatars", "beagle.gif"))

templates = [{"name": "summarize", "prompt": "Summarize the following in three short bullet points:"},
             {"name": "translate", "prompt": "Translate the following into Portuguese:"},
             {"name": "explain", "prompt": "Explain the following like I am new to the topic:"},
             {"name": "proofread", "prompt": "Fix the spelling and grammar of the following, change nothing else:"}]
providers = [{"id": "ollama", "name": "Nova demo (local)", "type": "openai-compat",
              "baseUrl": "http://127.0.0.1:%s/v1" % PORT, "model": MODEL}]
settings = {"provider": "ollama", "providersJson": json.dumps(providers), "promptTemplates": json.dumps(templates),
            "userName": "Alex", "userAvatar": "face-glasses", "aiName": "Nova", "aiAvatar": "face-smile",
            "autoNameChats": "false", "lastSessionId": CHAT_LIST[0]["id"], "sttSettingsMigrated": "true",
            # The media run makes no sound and sends no desktop notification (Notifier.qml would play the reply sound).
            "playNotificationSound": "false", "notifyOnReply": "false", "notifyOnError": "false",
            "notifyOnScheduled": "false", "notifyOnInput": "false",
            # The demo OpenCode server (scripts/media/demo_opencode.py) and the folder the agent modes work in; Pi is the fake `pi` on PATH.
            "openCodeUrl": "http://127.0.0.1:%s" % os.environ.get("DEV_MEDIA_OC_PORT", "18766"), "openCodeProvider": "demo",
            "openCodeModel": "nova-coder", "openCodeAgent": "build",
            "openCodeWorkspaceCwd": PROJECT}   # the agents work in this demo project folder: copies of a few real files
# Its files (~/Projects/kdeaichat in the sandbox home): the few files the demo OpenCode
# server reads (scripts/check_file_sizes.py), the attach step attaches (docs/voice.md, the tram picture) and build/ it writes to.
for rel in ("docs/voice.md", "scripts/check_file_sizes.py", "scripts/media/lisbon-tram.jpg"):
    os.makedirs(os.path.dirname(os.path.join(PROJECT, rel)), exist_ok=True)
    shutil.copy(os.path.join(ROOT, rel), os.path.join(PROJECT, rel))
os.makedirs(os.path.join(PROJECT, "build"), exist_ok=True)
rc = "[Applets][4]\nimmutability=1\nplugin=org.kde.plasma.kdeaichat.dev\n\n"
rc += "[Applets][4][Configuration]\ngeometry=2,2,460,640\n\n[Applets][4][Configuration][General]\n"
rc += "".join("%s=%s\n" % (k, v) for k, v in settings.items())
os.makedirs(CONFIG, exist_ok=True)
with open(os.path.join(CONFIG, "plasmawindowedrc"), "w", encoding="utf-8") as f:
    f.write(rc)

env = dict(os.environ, HOME=HOME, XDG_CONFIG_HOME=CONFIG, XDG_DATA_HOME=DATA,
           XDG_CACHE_HOME=CACHE, KDEAICHAT_UNIT_DIR=os.path.join(SANDBOX, "units"),
           KDEAICHAT_SYSTEMCTL="true")


def helper(command, payload):
    arg = base64.b64encode(json.dumps(payload).encode()).decode()
    done = subprocess.run([sys.executable, HELPER, command, arg], env=env, capture_output=True, text=True)
    if done.returncode != 0 or '"ok": false' in done.stdout:
        sys.exit("seed: %s failed: %s %s" % (command, done.stdout, done.stderr))


helper("memory_add", {"items": [
    {"text": "Alex likes short answers with a code example when it is about code.", "scope": "all", "pinned": True},
    {"text": "Alex lives in Lisbon, so use metric units and the 24-hour clock.", "scope": "all"},
    {"text": "Alex is learning Rust and prefers explanations without jargon.", "scope": "chat",
     "chatId": CHAT_LIST[0]["id"]}]})
helper("schedule_save", {"schedule": {
    "id": "morning-brief", "name": "Morning briefing", "chatId": CHAT_LIST[1]["id"], "enabled": True,
    "message": "Give me a short briefing for today: the weather in Lisbon and three things worth knowing.",
    "rules": [{"kind": "weekly", "days": [1, 2, 3, 4, 5], "times": ["08:30"]}]}})
print("seeded %d chats, memories and a schedule in %s" % (len(CHAT_LIST), SANDBOX))
