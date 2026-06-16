#!/bin/bash
# debug_all.sh — Comprehensive KDE AI Chat debugger
# Run this after reproducing any issue.
# It captures everything: errors, warnings, timing, QML issues, voice, streaming.

echo "═══════════════════════════════════════════════════════════════"
echo "  KDE AI Chat — Full Debug Report"
echo "  $(date)"
echo "═══════════════════════════════════════════════════════════════"

echo ""
echo "─── 1. PLASMASHELL STATUS ───────────────────────────────────"
systemctl --user status plasma-plasmashell.service 2>/dev/null | head -10

echo ""
echo "─── 2. ALL KAI- LOGS (last 5 min) ──────────────────────────"
journalctl --user --since "5 minutes ago" --no-pager 2>/dev/null | grep "KAI-" | tail -50

echo ""
echo "─── 3. ERRORS & WARNINGS (last 5 min) ──────────────────────"
journalctl --user --since "5 minutes ago" --no-pager 2>/dev/null | grep -iE "error|warn|fatal|abort|crash|segfault|qml|binding" | grep -i "kdeaichat\|plasmashell" | tail -30

echo ""
echo "─── 4. QML BINDING LOOPS ───────────────────────────────────"
journalctl --user --since "5 minutes ago" --no-pager 2>/dev/null | grep -i "binding loop" | tail -10

echo ""
echo "─── 5. VOICE/STT/TTS ISSUES ───────────────────────────────"
journalctl --user --since "5 minutes ago" --no-pager 2>/dev/null | grep -iE "voice|stt|tts|whisper|daemon|kde-ai-stt|kde-ai-tts" | tail -20

echo ""
echo "─── 6. OPENCODE SERVER STATUS ──────────────────────────────"
pgrep -a opencode 2>/dev/null || echo "No opencode processes found"
cat /tmp/kdeaichat-opencode-$(id -u).log 2>/dev/null | tail -10 || echo "No OpenCode log found"

echo ""
echo "─── 7. WIDGET INSTALLED FILES ──────────────────────────────"
echo "Source files:"
ls -la /home/home/Programming/rachitkdeaichat/org.kde.plasma.kdeaichat/contents/ui/*.qml /home/home/Programming/rachitkdeaichat/org.kde.plasma.kdeaichat/contents/ui/*.js 2>/dev/null | awk '{print $5, $9}'
echo ""
echo "Installed files:"
ls -la /home/home/.local/share/plasma/plasmoids/org.kde.plasma.kdeaichat/contents/ui/*.qml /home/home/.local/share/plasma/plasmoids/org.kde.plasma.kdeaichat/contents/ui/*.js 2>/dev/null | awk '{print $5, $9}'
echo ""
echo "File diffs between source and installed:"
for f in main.qml FullRepresentation.qml MessageContent.qml MainDatabase.js MainNetwork.js MainOpenCode.js MainDataSources.qml; do
    if ! diff -q "/home/home/Programming/rachitkdeaichat/org.kde.plasma.kdeaichat/contents/ui/$f" "/home/home/.local/share/plasma/plasmoids/org.kde.plasma.kdeaichat/contents/ui/$f" >/dev/null 2>&1; then
        echo "  DIFFERS: $f"
    else
        echo "  OK: $f"
    fi
done

echo ""
echo "─── 8. QML CACHE STATUS ────────────────────────────────────"
echo "Cache dir: $(ls -la ~/.cache/plasmashell/qmlcache/ 2>/dev/null | wc -l) entries"
ls -la ~/.cache/plasmashell/qmlcache/ 2>/dev/null | head -10

echo ""
echo "─── 9. CONFIG FILE ─────────────────────────────────────────"
cat /home/home/.config/kdeaichatrc 2>/dev/null | head -20

echo ""
echo "─── 10. SESSIONS DATA SIZE ──────────────────────────────────"
python3 -c "
import json
try:
    with open('$HOME/.config/kdeaichat_history.json') as f:
        data = json.load(f)
    sessions = data if isinstance(data, list) else data.get('sessions', [])
    total_msgs = sum(len(s.get('messages', [])) for s in sessions if isinstance(s, dict))
    print(f'Sessions: {len(sessions)}, Total messages: {total_msgs}')
except Exception as e:
    print(f'Error: {e}')
" 2>/dev/null

echo ""
echo "─── 11. SYSTEM RESOURCES ───────────────────────────────────"
echo "RAM: $(free -h | awk '/Mem:/{print $3"/"$2}')"
echo "CPU: $(top -bn1 | grep "plasmashell" | awk '{print $9}')"
echo "Plasma threads: $(pgrep -c plasmashell 2>/dev/null || echo 0)"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Report complete. Paste this entire output."
echo "═══════════════════════════════════════════════════════════════"
