#!/usr/bin/env bash
# Makes the screenshots, GIFs and demo video for the docs (docs/media/), from the
# real widget running in the dev sandbox with made-up demo data. See docs/development.md.
#
# Usage: scripts/dev-media.sh [light|dark|both]      (default: both)
#   DEV_MEDIA_ONLY=videoChat,flowSend scripts/dev-media.sh light   runs only those tour steps (MediaTour.qml
#   steps()); the other stills and frames are kept, and nothing is checked or encoded.
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
# The widget runs with this as its home (DEV_HOME, seed.py), so folders read ~/.local/share/kdeaichat and
# ~/Projects/kdeaichat like a user's, never the real home or this repository's path.
SBHOME="$SANDBOX/home"
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
# Speech Note shows as installed (a file named dsnote), with no D-Bus: nothing is run or contacted.
# The local-server scan sees only the fake server, never a real one on this machine.
export KDEAICHAT_LOCAL_PORTS="$PORT"
export QML_XHR_ALLOW_FILE_READ=1   # VideoMore.qml reads media-part.txt
export KDEAICHAT_DSNOTE="$ROOT/scripts/media/fake_dsnote.sh" KDEAICHAT_BUSCTL="$ROOT/scripts/media/fake_busctl.sh"
# Read aloud through Speech Note talks to the bus directly (not through busctl): pointed at nothing, so it can
# never reach the real service and play sound. The video reads aloud with Qt's silent test voice instead.
export KDEAICHAT_SPEECHNOTE_BUS="unix:path=$ROOT/build/dev-run/no-such-bus"
# The fake Speech Note answers dictation with this text (scripts/media/fake_busctl.py); nothing records or plays.
export KDEAICHAT_FAKE_DICTATION="${KDEAICHAT_FAKE_DICTATION:-Remind me what we decided about the trip budget}"
python3 "$ROOT/scripts/media/mock_openai.py" "$PORT" &
MOCK=$!
# The agent modes: the demo OpenCode server (real files, several agents) and a fake `pi` replaying a recorded real Pi run.
OC_PORT="${DEV_MEDIA_OC_PORT:-18766}"
python3 "$ROOT/scripts/media/demo_opencode.py" "$OC_PORT" >/dev/null 2>&1 &
MOCK_OC=$!
mkdir -p "$ROOT/build/dev-run/pi-bin" "$ROOT/build/dev-run/media-work"
ln -sf "$ROOT/scripts/dev-pi-mock.py" "$ROOT/build/dev-run/pi-bin/pi"
export PATH="$ROOT/build/dev-run/pi-bin:$PATH" KDEAICHAT_PI_MOCK_DELAY="${KDEAICHAT_PI_MOCK_DELAY:-0.03}"
export DEV_MEDIA_OC_PORT="$OC_PORT" DEV_MEDIA_WORK="$ROOT/build/dev-run/media-work"
stop_all() {
    kill "$MOCK" "$MOCK_OC" 2>/dev/null || true
    HOME="$SBHOME" XDG_DATA_HOME="$SBHOME/.local/share" python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from kdeaichat import pi_bridge; pi_bridge.cmd_pi_bridge_stop({})' "$ROOT/org.kde.plasma.kdeaichat/contents/ui" >/dev/null 2>&1 || true
}
trap stop_all EXIT

# The scheduler, as systemd would run it (no timer is ever made): a schedule the tour saves (VideoMoreSchedule.qml,
# due at once) is run one time with the real job, kde_ai_helper.py run_schedule, in the sandbox. Its answer goes
# into the chat like any scheduled run. No notification reaches the desktop; the wallet is the dev one.
run_saved_schedules() {
    local store="$SBHOME/.local/share/kdeaichat/schedules.v2.json" seen="" id
    local ids='import json,sys; print(" ".join(s.get("id","") for s in json.load(open(sys.argv[1])).get("schedules",[])))'
    while [ ! -f "$store" ]; do sleep 0.5; done
    seen=" $(python3 -c "$ids" "$store" 2>/dev/null) "
    while :; do
        sleep 1
        for id in $(python3 -c "$ids" "$store" 2>/dev/null); do
            case "$seen" in *" $id "*) continue ;; esac
            seen="$seen$id "
            # Like its timer: tried every 2 s until it is due (at most 4 minutes), then run once.
            for _ in $(seq 120); do
                HOME="$SBHOME" XDG_CONFIG_HOME="$SBHOME/.config" XDG_DATA_HOME="$SBHOME/.local/share" XDG_CACHE_HOME="$SBHOME/.cache" \
                    KDEAICHAT_UNIT_DIR="$SANDBOX/units" KDEAICHAT_SYSTEMCTL=true KDEAICHAT_WALLET_FOLDER=KDEAIChat-dev \
                    KDEAICHAT_WIDGET_RUNNING=1 KDEAICHAT_NOTIFY_SEND=true \
                    python3 "$ROOT/org.kde.plasma.kdeaichat/contents/ui/kde_ai_helper.py" run_schedule "$id" >>"$ROOT/build/dev-media-schedules.log" 2>&1
                tail -n 1 "$ROOT/build/dev-media-schedules.log" | grep -q '"action": "run"' && break
                sleep 2
            done
        done
    done
}

# The tour files whose flows DEV_MEDIA_ONLY re-records (videoChat -> VideoChat.qml; built-in steps -> MediaTour.qml).
only_files() {
    local name f found
    for name in ${DEV_MEDIA_ONLY//,/ }; do   # a chapter may be split over ${Name}*.qml files (VideoMoreModes.qml, ...)
        found=0
        local parts="$ROOT/scripts/media/${name^}"[A-Z]*.qml part
        if [ "$name" = videoMore ] && [ -n "${DEV_MEDIA_PART:-}" ]; then   # only the chosen chapters' files
            parts=""
            for part in ${DEV_MEDIA_PART//,/ }; do parts="$parts $ROOT/scripts/media/VideoMore${part^}.qml"; done
        fi
        for f in "$ROOT/scripts/media/${name^}".qml $parts; do
            [ -f "$f" ] && { echo "$f"; found=1; }
        done
        [ "$found" = 1 ] || echo "$ROOT/scripts/media/MediaTour.qml"
    done | sort -u
}

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
    printf '%s' "${DEV_MEDIA_PART:-}" >"$SBHOME/.local/share/media-part.txt"   # which VideoMore chapters to run (VideoMore.qml)
    { cat "$colors"; printf '\n[Icons]\nTheme=%s\n' "$icons"; } >"$SBHOME/.config/kdeglobals"
    printf '[Theme]\nname=%s\n' "$plasma" >"$SBHOME/.config/plasmarc"

    flows=0
    if [ "$theme" = light ]; then
        flows=1
        # Every flow any tour file records (kit.record("<name>", ...)) gets an empty folder.
        [ -z "${DEV_MEDIA_ONLY:-}" ] && rm -rf "$FRAMES"
        for flow in $(grep -ohE 'kit\.record\("[a-z0-9-]+"' "$ROOT"/scripts/media/*.qml | sed -E 's/.*"(.*)"/\1/' | sort -u); do
            [ -n "${DEV_MEDIA_ONLY:-}" ] && grep -qE "kit\.record\(\"$flow\"" $(only_files) 2>/dev/null && rm -rf "${FRAMES:?}/$flow"
            mkdir -p "$FRAMES/$flow"
        done
    fi
    [ -z "${DEV_MEDIA_ONLY:-}" ] && rm -f "$OUT"/*-"$theme".png
    echo "== $theme: running the tour"
    rm -f "$ROOT/build/dev-media-schedules.log"
    run_saved_schedules &
    RUNNER=$!
    set +e
    DEV_HOME="$SBHOME" QT_QPA_PLATFORMTHEME=kde DEV_SCREENSHOT=0 DEV_KEEP=1 DEV_MEDIA_TOUR=1 DEV_MEDIA_OUT="$OUT" DEV_MEDIA_FRAMES="$FRAMES" \
        DEV_MEDIA_THEME="$theme" DEV_MEDIA_FLOWS="$flows" DEV_MEDIA_ONLY="${DEV_MEDIA_ONLY:-}" "$ROOT/scripts/dev-run.sh" "$SECONDS_MAX" >"$ROOT/build/dev-media-$theme.txt" 2>&1
    set -e
    kill "$RUNNER" 2>/dev/null || true
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
    [ -n "${DEV_MEDIA_ONLY:-}" ] && continue
    for state in "${STATES[@]}"; do
        [ -s "$OUT/$state-$theme.png" ] || { echo "$theme: missing $state-$theme.png" >&2; status=1; }
    done
    grep "MEDIA_SKIP" "$LOG" | sed 's/^qml: /skipped: /' || true
    grep -E "$ROOT|org.kde.plasma.kdeaichat.dev/contents" "$LOG" | grep -v "used before its declaration" | head -5 || true
done

if [ "$status" = 0 ] && [ -z "${DEV_MEDIA_ONLY:-}" ] && [[ " $THEMES " == *" light "* ]]; then
    python3 "$ROOT/scripts/media/encode.py" "$FRAMES" "$OUT" || status=1
fi
exit "$status"
