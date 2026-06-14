#!/bin/bash
# install.sh — KDE AI Chat full installer
# Installs the Plasma widget AND the optional scheduler daemon + systemd service.
set -e

WIDGET_DIR="org.kde.plasma.kdeaichat"
WIDGET_ID="org.kde.plasma.kdeaichat"
DAEMON_SRC="$WIDGET_DIR/contents/scripts/kde-ai-scheduler.py"
DATA_DIR="$HOME/.local/share/kdeaichat"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="kde-ai-scheduler.service"

echo "═══════════════════════════════════════════════"
echo "  KDE AI Chat — Installer"
echo "═══════════════════════════════════════════════"

# ── 0. Pull latest from git ───────────────────────────────────────────────────
# if [ -d ".git" ]; then
#     echo ""
#     echo "[0/4] Pulling latest changes from git..."
#     git pull
#     echo "      ✓ Git pull done."
# fi

# ── 1. Install the Plasma widget ──────────────────────────────────────────────
echo ""
echo "[1/4] Installing Plasma widget..."
kpackagetool6 --type Plasma/Applet --remove "$WIDGET_ID" >/dev/null 2>&1 || true
kpackagetool6 --type Plasma/Applet --install "$WIDGET_DIR"
echo "      ✓ Widget installed."

# ── 2. Deploy the scheduler daemon ───────────────────────────────────────────
echo ""
echo "[2/4] Deploying scheduler daemon..."
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/pending"
chmod 700 "$DATA_DIR"

if [ -f "$DAEMON_SRC" ]; then
    cp "$DAEMON_SRC" "$DATA_DIR/kde-ai-scheduler.py"
    chmod 700 "$DATA_DIR/kde-ai-scheduler.py"
    echo "      ✓ Daemon copied to $DATA_DIR/kde-ai-scheduler.py"
else
    echo "      ⚠ Daemon source not found at $DAEMON_SRC — skipping."
fi

# Ensure an empty schedules.json exists if it doesn't already
if [ ! -f "$DATA_DIR/schedules.json" ]; then
    echo '{"version":1,"schedules":[]}' > "$DATA_DIR/schedules.json"
    chmod 600 "$DATA_DIR/schedules.json"
    echo "      ✓ Created empty schedules.json"
fi

# ── 3. Register the systemd user service ─────────────────────────────────────
echo ""
echo "[3/4] Registering systemd user service..."
mkdir -p "$SERVICE_DIR"

cat > "$SERVICE_DIR/$SERVICE_FILE" << 'EOF'
[Unit]
Description=KDE AI Chat Scheduler Daemon
Documentation=https://github.com/racstan/KDE-AI-Chat
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 %h/.local/share/kdeaichat/kde-ai-scheduler.py
Restart=on-failure
RestartSec=30
StandardOutput=journal
StandardError=journal
# Reload schedules.json on SIGHUP without killing the daemon
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
echo "      ✓ Service file installed: $SERVICE_DIR/$SERVICE_FILE"
echo "      ✓ systemd daemon-reload done."
echo ""
echo "      To start the daemon now:"
echo "        systemctl --user start kde-ai-scheduler.service"
echo "      To start it automatically at login:"
echo "        systemctl --user enable kde-ai-scheduler.service"

# ── 4. Clear Qt6 QML cache and restart Plasma ────────────────────────────────
echo ""
echo "[4/4] Clearing QML cache and restarting Plasma..."
rm -rf "$HOME/.cache/plasmashell/qmlcache/"
echo "      ✓ QML cache cleared."

echo ""
echo "═══════════════════════════════════════════════"
echo "  Installation complete! Restarting Plasma..."
echo "═══════════════════════════════════════════════"
echo ""
set +e
systemctl --user restart plasma-plasmashell.service 2>/dev/null || \
    echo "  ⚠ Could not restart Plasma automatically."
echo "  If Plasma didn't restart, run:"
echo "    systemctl --user restart plasma-plasmashell.service"
