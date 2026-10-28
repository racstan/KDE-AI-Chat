#!/usr/bin/env python3
"""Adds the media tour to the staged copy of FullRepresentationContent.qml (dev-run.sh DEV_MEDIA_TOUR).

Usage: inject_tour.py <FullRepresentationContent.qml> <out-dir> <frames-dir> <theme> <flows 0|1> [only]
"""
import json
import sys

path, out, frames, theme, flows = sys.argv[1:6]
only = sys.argv[6] if len(sys.argv) > 6 else ""
src = open(path, encoding="utf-8").read()
anchor = 'import "chat" as Chat\n'
if anchor not in src:
    sys.exit("inject_tour: FullRepresentationContent.qml no longer imports chat")
src = src.replace(anchor, anchor + 'import "media" as Media\n', 1)
end = src.rstrip().rindex("}")
hook = """    Media.MediaTour {
        target: repRoot
        app: root
        body: body
        settingsDialog: chatSettingsDialog
        scheduleOverlay: scheduleOverlay
        exportDialog: exportDialog
        plasmoidRef: plasmoid
        outDir: %s
        framesDir: %s
        themeName: %s
        flows: %s
        only: %s
    }
""" % (json.dumps(out), json.dumps(frames), json.dumps(theme), "true" if flows == "1" else "false", json.dumps(only))
open(path, "w", encoding="utf-8").write(src[:end] + hook + src[end:])
