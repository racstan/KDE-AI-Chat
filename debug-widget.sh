#!/bin/bash
# debug-widget.sh - Utility to run and debug the KDE AI Chat widget in a standalone window

echo "================================================="
echo "  KDE AI Chat — Standalone Debug Window Launcher"
echo "================================================="
echo ""

echo "[1/3] Clearing QML cache..."
rm -rf "$HOME/.cache/plasmashell/qmlcache/"
echo "      ✓ QML cache cleared."

echo "[2/3] Enabling QML logging rules..."
# Set logging rules for Qt/QML
export QT_LOGGING_RULES="qml.debug=true;*.debug=true"

echo "[3/3] Launching widget in plasmawindowed..."
echo "      Press Ctrl+C in this terminal to close the window."
echo ""

plasmawindowed org.kde.plasma.kdeaichat
