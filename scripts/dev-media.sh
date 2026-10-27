#!/usr/bin/env bash
# Makes the screenshots, GIFs and demo video for the docs (docs/media/), from the
# real widget running in the dev sandbox with made-up demo data. See docs/development.md.
#
# Usage: scripts/dev-media.sh [light|dark|both]      (default: both)
#   docs/media/<state>-<light|dark>.png   the widget's chat states and the settings pages
#   docs/media/{send-message,search,incognito,commands}.gif and demo.webm   (light theme only)
#
# Per theme, the sandbox of scripts/dev-run.sh is reset and seeded (scripts/media/seed.py: chats,
# memories, a schedule, names Alex and Nova), a Breeze Light or Dark colour scheme is written into
# the sandbox's kdeglobals/plasmarc (QT_QPA_PLATFORMTHEME=kde, as tests/test_qml.py does), a fake
# OpenAI-compatible server (scripts/media/mock_openai.py) answers the chat, and the widget runs
# with scripts/media/MediaTour.qml, which saves the widget's own item (grabToImage) at 460x640
# logical px, device pixel ratio 2. Nothing grabs the screen; no key, network or model is used.
# QT_QPA_PLATFORM=offscreen runs it without a window. Exit status 1 if any state failed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEMES="${1:-both}"
case "$THEMES" in light | dark) THEMES="$THEMES" ;; both) THEMES="light dark" ;; *) echo "usage: $0 [light|dark|both]" >&2; exit 2 ;; esac
OUT="$ROOT/docs/media"
FRAMES="$ROOT/build/media-frames"
SANDBOX="$ROOT/build/dev-run/sandbox"
PORT="${DEV_MEDIA_PORT:-18765}"
SECONDS_MAX="${DEV_MEDIA_SECONDS:-240}"
FLOWS=(send-message search incognito commands)
STATES=(chat-conversation chat-empty chat-history chat-search chat-incognito chat-commands chat-ask chat-settings schedule-editor
        settings-connection settings-chat settings-personality settings-memory settings-schedules settings-voice
        settings-appearance settings-desktop settings-storage settings-support settings-setup-check)
# Extra states: one that can't be reached is skipped (MEDIA_SKIP in the log), which is not an error.
EXTRAS=(chat-quote chat-edit chat-variants chat-more-menu chat-export chat-workspace chat-opencode chat-pi chat-image
        chat-error chat-mode-notice chat-model-notice chat-remember chat-first-run chat-scheduled chat-long-reply
        chat-avatars chat-narrow settings-providers-find settings-avatar-picker settings-icon
        settings-voice-speechnote settings-schedule-dialog)

mkdir -p "$OUT"
python3 "$ROOT/scripts/media/mock_openai.py" "$PORT" &
MOCK=$!
trap 'kill "$MOCK" 2>/dev/null || true' EXIT

status=0
for theme in $THEMES; do
    case "$theme" in
        light) scheme=BreezeLight; icons=breeze; plasma=breeze-light ;;
        dark) scheme=BreezeDark; icons=breeze-dark; plasma=breeze-dark ;;
    esac
    colors="/usr/share/color-schemes/$scheme.colors"
    [ -f "$colors" ] || { echo "missing $colors" >&2; exit 2; }

    rm -rf "$SANDBOX" "$ROOT/build/media-frames-$theme"
    python3 "$ROOT/scripts/media/seed.py" "$SANDBOX" "$PORT"
    { cat "$colors"; printf '\n[Icons]\nTheme=%s\n' "$icons"; } >"$SANDBOX/config/kdeglobals"
    printf '[Theme]\nname=%s\n' "$plasma" >"$SANDBOX/config/plasmarc"

    flows=0
    if [ "$theme" = light ]; then
        flows=1
        rm -rf "$FRAMES"
        for flow in "${FLOWS[@]}"; do mkdir -p "$FRAMES/$flow"; done
    fi
    rm -f "$OUT"/*-"$theme".png
    echo "== $theme: running the tour"
    set +e
    QT_QPA_PLATFORMTHEME=kde DEV_SCREENSHOT=0 DEV_KEEP=1 DEV_MEDIA_TOUR=1 DEV_MEDIA_OUT="$OUT" DEV_MEDIA_FRAMES="$FRAMES" \
        DEV_MEDIA_THEME="$theme" DEV_MEDIA_FLOWS="$flows" "$ROOT/scripts/dev-run.sh" "$SECONDS_MAX" >"$ROOT/build/dev-media-$theme.txt" 2>&1
    set -e
    LOG="$ROOT/build/dev-run/qml.log"
    cp "$LOG" "$ROOT/build/dev-media-$theme.log"
    grep -E "^qml: MEDIA_(START|THEME)" "$LOG" | sed 's/^qml: /   /' || true
    grep -E "MEDIA_(SAVED|FRAMES)" "$LOG" | sed -E 's/^qml: MEDIA_SAVED /saved /; s/^qml: MEDIA_FRAMES /frames /' || true
    if grep -q "MEDIA_FAIL" "$LOG"; then
        grep "MEDIA_FAIL" "$LOG" | head -3 >&2
        status=1
    elif ! grep -q "MEDIA_DONE" "$LOG"; then
        echo "$theme: the tour did not finish in ${SECONDS_MAX}s" >&2
        status=1
    fi
    for state in "${STATES[@]}"; do
        [ -s "$OUT/$state-$theme.png" ] || { echo "$theme: missing $state-$theme.png" >&2; status=1; }
    done
    grep "MEDIA_SKIP" "$LOG" | sed 's/^qml: /skipped: /' || true
    grep -E "$ROOT|org.kde.plasma.kdeaichat.dev/contents" "$LOG" | grep -v "used before its declaration" | head -5 || true
done

if [ "$status" = 0 ] && [[ " $THEMES " == *" light "* ]]; then
    python3 "$ROOT/scripts/media/encode.py" "$FRAMES" "$OUT" || status=1
fi
exit "$status"
