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

kpackagetool6 --type Plasma/Applet --remove "$DEV_ID" >/dev/null 2>&1 || true
kpackagetool6 --type Plasma/Applet --install "$STAGE/$DEV_ID" >/dev/null

# Run windowed, screenshot the active window, then stop it.
plasmawindowed "$DEV_ID" >"$LOG" 2>&1 &
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
