#!/bin/bash

# AI Chat Plasma Widget Installation Script

set -e

WIDGET_DIR="org.kde.plasma.aichat"
INSTALL_TYPE="${1:-user}"

echo "Installing AI Chat Plasma Widget..."

if [ "$INSTALL_TYPE" = "global" ]; then
    echo "Installing globally (requires sudo)..."
    kpackagetool6 --install "$WIDGET_DIR" --type Plasma/Applet --global \
        || kpackagetool6 --upgrade "$WIDGET_DIR" --type Plasma/Applet --global
else
    echo "Installing for current user..."
    kpackagetool6 --install "$WIDGET_DIR" --type Plasma/Applet \
        || kpackagetool6 --upgrade "$WIDGET_DIR" --type Plasma/Applet
fi

echo "Installation complete!"
echo ""
echo "To add the widget:"
echo "  1. Right-click on desktop or panel"
echo "  2. Select 'Add Widgets...'"
echo "  3. Search for 'AI Chat'"
echo ""
echo "To uninstall:"
echo "  kpackagetool6 --remove org.kde.plasma.aichat"
