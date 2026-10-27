#!/usr/bin/env bash
# Launch the working-tree widget in its own window and report QML warnings
# (and screenshot it, see DEV_SCREENSHOT below), without touching the installed widget or restarting plasmashell.
#
# The package is installed under a separate id (org.kde.plasma.kdeaichat.dev)
# into a sandbox: XDG_CONFIG_HOME and XDG_DATA_HOME point at build/dev-run/,
# so the run never reads or writes your real config, chats or widget install.
# The sandbox is reset each run; set DEV_KEEP=1 to keep chats between runs.
# KWallet is the real session wallet (a D-Bus service), but the dev copy uses
# its own wallet folders ("KDEAIChat-dev", legacy "KaiChat-dev"), so your
# real keys are never touched.
#
# Usage: scripts/dev-run.sh [seconds-to-run] [screenshot-path]
# QT_QPA_PLATFORM=offscreen runs it without any window (warnings check only).
# Exit status: 0 if the run produced no QML warnings, 1 otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/org.kde.plasma.kdeaichat"
DEV_ID="org.kde.plasma.kdeaichat.dev"
RUN_SECONDS="${1:-8}"
OUT_DIR="$ROOT/build/dev-run"
SHOT="${2:-$OUT_DIR/screenshot.png}"
LOG="$OUT_DIR/qml.log"
SANDBOX="$OUT_DIR/sandbox"

if [ "${DEV_KEEP:-0}" != "1" ]; then
    rm -rf "$SANDBOX"
fi
rm -f "$SHOT"
mkdir -p "$OUT_DIR" "$(dirname "$SHOT")" "$SANDBOX/config" "$SANDBOX/data" "$SANDBOX/cache"
export XDG_CONFIG_HOME="$SANDBOX/config"
export XDG_DATA_HOME="$SANDBOX/data"
export XDG_CACHE_HOME="$SANDBOX/cache"
# Schedule timers the sandbox widget syncs on start go to a sandbox folder, and
# systemctl is a no-op: the real user manager is never told about them.
export KDEAICHAT_UNIT_DIR="$SANDBOX/units"
export KDEAICHAT_SYSTEMCTL=true
# The ask inbox (KRunner, Dolphin, kdeaichat-ask) and the KRunner/Dolphin/D-Bus files stay in the sandbox too.
export KDEAICHAT_ASK_DIR="$SANDBOX/ask"
export KDEAICHAT_KRUNNER_DIR="$SANDBOX/desktop/krunner" KDEAICHAT_DBUS_SERVICE_DIR="$SANDBOX/desktop/dbus"
export KDEAICHAT_SERVICEMENU_DIR="$SANDBOX/desktop/servicemenus" KDEAICHAT_DESKTOP_STATE="$SANDBOX/desktop/state.json"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Stage a copy with the dev id so it never replaces the real install.
cp -r "$SRC" "$STAGE/$DEV_ID"
find "$STAGE/$DEV_ID" -name __pycache__ -prune -exec rm -rf {} +
python3 - "$STAGE/$DEV_ID/metadata.json" "$DEV_ID" <<'PY'
import json, sys
path, dev_id = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    meta = json.load(f)
meta["KPlugin"]["Id"] = dev_id
meta["KPlugin"]["Name"] = meta["KPlugin"]["Name"] + " (dev)"
with open(path, "w", encoding="utf-8") as f:
    json.dump(meta, f, indent=4)
PY

# KWallet is the real session wallet, so keep dev keys in their own folder and
# never read or overwrite the user's real ones.
WALLET_QML="$STAGE/$DEV_ID/contents/ui/store/Wallet.qml"
sed -i -e 's/readonly property string folder: "KDEAIChat"/readonly property string folder: "KDEAIChat-dev"/' \
       -e 's/readonly property string legacyFolder: "KaiChat"/readonly property string legacyFolder: "KaiChat-dev"/' "$WALLET_QML"
grep -q '"KDEAIChat-dev"' "$WALLET_QML" && grep -q '"KaiChat-dev"' "$WALLET_QML" \
    || { echo "could not isolate wallet folders" >&2; exit 2; }

# DEV_AUTO_ANSWER="text": in the staged copy only, the model's ask_user questions
# (direct mode) are answered with this text right after they are shown, for
# end-to-end runs without clicking (scripts/dev-send.sh passes it through).
if [ -n "${DEV_AUTO_ANSWER:-}" ]; then
    python3 - "$STAGE/$DEV_ID/contents/ui/chat/DirectToolRounds.qml" "$DEV_AUTO_ANSWER" <<'PY'
import json, sys
path, answer = sys.argv[1:]
src = open(path, encoding="utf-8").read()
marker = "        // DEV_AUTO_ANSWER"
start = src.index(marker)
end = src.index("\n", start)
hook = "        Qt.callLater(function() { rounds.respondToQuestion(questionId, %s, false); });" % json.dumps(answer)
open(path, "w", encoding="utf-8").write(src[:start] + hook + src[end:])
PY
fi

# DEV_IMAGE_PROMPT="text": in the staged copy only, the widget runs "/image text" once,
# a few seconds after it starts, through root.sendImageCommand (what the composer's
# /image calls after its own checks). scripts/dev-image.sh passes it through.
if [ -n "${DEV_IMAGE_PROMPT:-}" ]; then
    python3 - "$STAGE/$DEV_ID/contents/ui/main.qml" "$DEV_IMAGE_PROMPT" <<'PY'
import json, sys
path, prompt = sys.argv[1:]
src = open(path, encoding="utf-8").read()
end = src.rstrip().rindex("}")
hook = "    Timer { interval: 5000; running: true; onTriggered: root.sendImageCommand(%s) }\n" % json.dumps(prompt)
open(path, "w", encoding="utf-8").write(src[:end] + hook + src[end:])
PY
fi

# DEV_SEND_MESSAGE="text": in the staged copy only, the widget sends this text from the
# composer once, a few seconds after it starts (root.sendMessage, the Send button's path).
# scripts/dev-send.sh and the dev-*-e2e.sh scripts use it.
# DEV_INCOGNITO=1: the message goes into a new incognito chat (chat/Incognito.qml)
# instead; nothing of it is stored, so its messages are logged every 2 s as
# "DEV_INCOGNITO <json>" for dev-send.sh to print.
if [ -n "${DEV_SEND_MESSAGE:-}" ]; then
    python3 - "$STAGE/$DEV_ID/contents/ui/main.qml" "$DEV_SEND_MESSAGE" "${DEV_INCOGNITO:-0}" <<'PY'
import json, sys
path, message, incognito = sys.argv[1:]
src = open(path, encoding="utf-8").read()
end = src.rstrip().rindex("}")
start = "root.incognito.start(); " if incognito == "1" else ""
hook = "    Timer { interval: 5000; running: true; onTriggered: { %sroot.chatInputText = %s; root.sendMessage(); } }\n" % (start, json.dumps(message))
if incognito == "1":
    hook += ("    Timer { interval: 2000; running: true; repeat: true; onTriggered: if (root.incognito.active) console.log(\"DEV_INCOGNITO \" + "
             "JSON.stringify({\"id\": root.currentSessionId, \"messages\": root.messages.map(function(m) { "
             "return {\"role\": m.role, \"model\": m.model || \"\", \"content\": String(m.content || \"\").substring(0, 400)}; })})) }\n")
open(path, "w", encoding="utf-8").write(src[:end] + hook + src[end:])
PY
fi

# DEV_SCHEDULE_DESCRIBE="sentence": in the staged copy only, a few seconds after
# start the chat's "Schedule a message…" editor opens and "Describe when" is run
# with this sentence; DEV_SCHEDULE_ANSWER="text" answers the model's first
# question. Each step is logged as "DEV_DESCRIBE …", and the editor (only the
# widget's own item) is saved to DEV_SCHEDULE_SHOT when the question or the
# rules arrive (scripts/dev-describe.sh).
if [ -n "${DEV_SCHEDULE_DESCRIBE:-}" ]; then
    python3 - "$STAGE/$DEV_ID/contents/ui/FullRepresentationContent.qml" "$DEV_SCHEDULE_DESCRIBE" \
        "${DEV_SCHEDULE_ANSWER:-}" "${DEV_SCHEDULE_SHOT:-}" <<'PY'
import json, sys
path, sentence, answer, shot = sys.argv[1:]
src = open(path, encoding="utf-8").read()
end = src.rstrip().rindex("}")
hook = """    Timer { interval: 5000; running: true; onTriggered: {
        scheduleOverlay.openForChat(root.currentSessionId);
        var editor = scheduleOverlay.dialog.editor, d = editor.describer, answer = %s, shot = %s, answered = false;
        var save = function(suffix, then) {
            var done = then || function() {};
            if (!shot) { Qt.callLater(done); return; }
            Qt.callLater(function() { scheduleOverlay.grabToImage(function(r) {
                r.saveToFile(shot.replace(/[.]png$/, suffix + ".png")); done(); }); });
        };
        d.phaseChanged.connect(function() {
            console.log("DEV_DESCRIBE phase=" + d.phase + " reply=" + JSON.stringify(d.lastReply) + " error=" + JSON.stringify(d.error));
            if (d.phase === "question")
                save("-question", function() { if (answer && !answered) { answered = true; d.answer(answer); } });
        });
        editor.previewResultChanged.connect(function() {
            console.log("DEV_DESCRIBE rules=" + JSON.stringify(editor.draft.rules) + " preview=" + JSON.stringify(editor.previewResult));
            if (d.lastReply) save("-rules");
        });
        var find = function(item) { if (item.objectName === "describeField") return item;
            for (var i = 0; i < item.children.length; i++) { var f = find(item.children[i]); if (f) return f; } return null; };
        find(editor).text = %s;
        d.start(find(editor).text);
    } }
""" % (json.dumps(answer), json.dumps(shot), json.dumps(sentence))
open(path, "w", encoding="utf-8").write(src[:end] + hook + src[end:])
PY
fi

kpackagetool6 --type Plasma/Applet --remove "$DEV_ID" >/dev/null 2>&1 || true
kpackagetool6 --type Plasma/Applet --install "$STAGE/$DEV_ID" >/dev/null

# Keep the test window off the user's main monitor: before launching, load a
# KWin script that moves plasmawindowed windows onto another output as soon
# as they appear. DEV_OUTPUT names the output; by default the first enabled
# output whose priority isn't 1 (the main one). With a single monitor, or
# without qdbus6/kscreen-doctor, the window stays where KWin puts it.
PLACE_MARK="kdeaichat-dev-place-$$"
PLACE_JS=""
# QT_QPA_PLATFORM=offscreen: no window at all, so no placement and no screenshot
# (kscreen-doctor would hang without a display connection).
OFFSCREEN=0
[ "${QT_QPA_PLATFORM:-}" = "offscreen" ] && OFFSCREEN=1 && DEV_OUTPUT="" && DEV_SCREENSHOT=0
[ "$OFFSCREEN" = "1" ] || DEV_OUTPUT="${DEV_OUTPUT:-$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '
    /^Output:/ { name = $3; on = 0 } /^[[:space:]]*enabled/ { on = 1 }
    /priority/ { if (on && $2 != 1 && pick == "") pick = name } END { print pick }')}"
if [ -n "$DEV_OUTPUT" ] && command -v qdbus6 >/dev/null; then
    PLACE_JS="$(mktemp --suffix=.js)"
    cat >"$PLACE_JS" <<JS
function place(w) {
    if (w.resourceClass.indexOf("plasmawindowed") === -1) return;
    for (const o of workspace.screens) {
        if (o.name !== "$DEV_OUTPUT") continue;
        const g = o.geometry, f = w.frameGeometry;
        const width = Math.min(f.width, g.width), height = Math.min(f.height, g.height);
        print("kdeaichat-dev placed on " + o.name);
        w.frameGeometry = { x: g.x + (g.width - width) / 2, y: g.y + (g.height - height) / 2,
                            width: width, height: height };
    }
}
workspace.windowList().forEach(place);
workspace.windowAdded.connect(place);
JS
    if PSID="$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$PLACE_JS" "$PLACE_MARK" 2>/dev/null)"; then
        qdbus6 org.kde.KWin "/Scripting/Script$PSID" org.kde.kwin.Script.run >/dev/null 2>&1 || true
    fi
fi
unplace() {
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$PLACE_MARK" >/dev/null 2>&1 || true
    if [ -n "$PLACE_JS" ]; then rm -f "$PLACE_JS"; fi
}
trap 'unplace; rm -rf "$STAGE"' EXIT

# Run windowed, screenshot the active window, then stop it. Qt would send its
# messages to the journal in a Plasma session; keep them in $LOG for the check below.
QT_FORCE_STDERR_LOGGING=1 plasmawindowed "$DEV_ID" >"$LOG" 2>&1 &
PID=$!
sleep "$RUN_SECONDS"
# spectacle can only grab the *active* window, so first ask KWin (scripting
# D-Bus API) to activate the dev window, then check it really is active before
# taking the shot. If either step fails, no screenshot is taken, so one of the
# user's own windows is never captured. DEV_SCREENSHOT=0 skips it.
SHOT_TAKEN=0
if [ "${DEV_SCREENSHOT:-1}" = "1" ] && command -v spectacle >/dev/null && command -v qdbus6 >/dev/null; then
    KWIN_JS="$(mktemp --suffix=.js)"
    MARK="kdeaichat-dev-$$"
    cat >"$KWIN_JS" <<JS
for (const w of workspace.windowList()) {
    if (w.pid === $PID) { workspace.activeWindow = w; }
}
const a = workspace.activeWindow;
print("$MARK active-pid=" + (a ? a.pid : -1));
JS
    SINCE="$(date '+%Y-%m-%d %H:%M:%S')"
    if SID="$(qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$KWIN_JS" "$MARK" 2>/dev/null)"; then
        qdbus6 org.kde.KWin "/Scripting/Script$SID" org.kde.kwin.Script.run >/dev/null 2>&1 || true
        sleep 1
        qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$MARK" >/dev/null 2>&1 || true
        if journalctl --user --since "$SINCE" --no-pager -o cat 2>/dev/null | grep -q "$MARK active-pid=$PID\$"; then
            spectacle --background --nonotify --activewindow --output "$SHOT" >/dev/null 2>&1 && SHOT_TAKEN=1
        fi
    fi
    rm -f "$KWIN_JS"
fi
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

# Warnings from our own files. "used before its declaration" is a compiler
# hint about callbacks referring to later variables, harmless at runtime.
WARNINGS="$(grep -E "$DEV_ID/contents/" "$LOG" | grep -v "used before its declaration" || true)"

if [ "$SHOT_TAKEN" = "1" ]; then echo "Screenshot: $SHOT"; else echo "Screenshot: not taken (dev window could not be made active)"; fi
echo "Full log:   $LOG"
if [ -n "$WARNINGS" ]; then
    echo "QML warnings:"
    echo "$WARNINGS" | sed -E 's|^.*'"$DEV_ID"'/contents/||' | sort | uniq -c | sort -rn
    exit 1
fi
echo "No QML warnings."
