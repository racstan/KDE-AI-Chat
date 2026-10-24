#!/usr/bin/env bash
# Launch the working-tree widget in its own window, screenshot it and report
# QML warnings, without touching the installed widget or restarting plasmashell.
#
# The package is installed under a separate id (org.kde.plasma.kdeaichat.dev)
# into a sandbox: XDG_CONFIG_HOME and XDG_DATA_HOME point at build/dev-run/,
# so the run never reads or writes your real config, chats or widget install.
# The sandbox is reset each run; set DEV_KEEP=1 to keep chats between runs.
# KWallet is still the real session wallet (it's a D-Bus service).
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

kpackagetool6 --type Plasma/Applet --remove "$DEV_ID" >/dev/null 2>&1 || true
kpackagetool6 --type Plasma/Applet --install "$STAGE/$DEV_ID" >/dev/null

# Run windowed, screenshot the active window, then stop it.
plasmawindowed "$DEV_ID" >"$LOG" 2>&1 &
PID=$!
sleep "$RUN_SECONDS"
if command -v spectacle >/dev/null; then
    spectacle --background --nonotify --activewindow --output "$SHOT" >/dev/null 2>&1 || true
fi
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true

# Warnings from our own files. "used before its declaration" is a compiler
# hint about callbacks referring to later variables, harmless at runtime.
WARNINGS="$(grep -E "$DEV_ID/contents/" "$LOG" | grep -v "used before its declaration" || true)"

echo "Screenshot: $SHOT"
echo "Full log:   $LOG"
if [ -n "$WARNINGS" ]; then
    echo "QML warnings:"
    echo "$WARNINGS" | sed -E 's|^.*'"$DEV_ID"'/contents/||' | sort | uniq -c | sort -rn
    exit 1
fi
echo "No QML warnings."
