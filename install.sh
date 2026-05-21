#!/bin/bash
set -e

WIDGET_DIR="org.kde.plasma.kaichat"
WIDGET_ID="org.kde.plasma.kaichat"

echo "Installing / upgrading $WIDGET_ID ..."

# Clean reinstall to avoid stale metadata/config binding issues.
kpackagetool6 --type Plasma/Applet --remove "$WIDGET_ID" >/dev/null 2>&1 || true
kpackagetool6 --type Plasma/Applet --install "$WIDGET_DIR"

echo "Done. Restart plasmashell to load the new version:"
echo "  systemctl --user restart plasma-plasmashell.service"
