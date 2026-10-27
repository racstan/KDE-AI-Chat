#!/usr/bin/env python3
"""Turns the tour's frame sequences and stills into the docs' GIFs and demo video.

Usage: encode.py <frames-dir> <docs-media-dir>

  <frames>/<flow>/NNNN.png (every 80 ms)  ->  <media>/<flow>.gif   (12 fps, 460 px wide, looping)
  stills + flows                          ->  <media>/demo.webm     (VP9, crf 35, light theme, ~35 s)

Needs ffmpeg. Exits 1 if a flow has no frames or ffmpeg fails.
"""
import glob
import os
import subprocess
import sys
import tempfile

FRAMES, OUT = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
FPS = 12.5   # the tour grabs a frame every 80 ms
GIF_FPS = 12
WIDTH = 460
FLOWS = ["send-message", "search", "incognito", "commands"]
# The demo: (kind, name, seconds); stills hold for `seconds`, flows play their frames.
DEMO = [("flow", "send-message", 0), ("still", "chat-conversation", 2.5), ("still", "chat-empty", 2),
        ("still", "chat-history", 2.5), ("flow", "search", 0), ("flow", "commands", 0), ("still", "chat-ask", 3),
        ("flow", "incognito", 0), ("still", "chat-settings", 3), ("still", "schedule-editor", 3)]


def ffmpeg(*args):
    done = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit("ffmpeg failed: %s" % done.stderr.strip()[-600:])


def frames_of(flow):
    files = sorted(glob.glob(os.path.join(FRAMES, flow, "[0-9][0-9][0-9][0-9].png")))
    if len(files) < 10:
        sys.exit("encode: flow %s has only %d frames" % (flow, len(files)))
    return files


def gif(flow):
    out = os.path.join(OUT, flow + ".gif")
    frames = frames_of(flow)
    flt = "fps=%d,scale=%d:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" % (GIF_FPS, WIDTH)
    ffmpeg("-framerate", str(FPS), "-i", os.path.join(FRAMES, flow, "%04d.png"), "-vf", flt, "-loop", "0", out)
    print("saved %s (%d frames, %.0f KB)" % (out, len(frames), os.path.getsize(out) / 1024))


def demo():
    out = os.path.join(OUT, "demo.webm")
    with tempfile.TemporaryDirectory() as tmp:
        parts = []
        fit = "scale=%d:-2:flags=lanczos,format=yuv420p" % WIDTH
        for i, (kind, name, seconds) in enumerate(DEMO):
            part = os.path.join(tmp, "%02d.mp4" % i)
            if kind == "flow":
                frames_of(name)
                ffmpeg("-framerate", str(FPS), "-i", os.path.join(FRAMES, name, "%04d.png"), "-vf", fit, "-r", "25", part)
            else:
                still = os.path.join(OUT, name + "-light.png")
                if not os.path.exists(still):
                    sys.exit("encode: %s is missing" % still)
                ffmpeg("-loop", "1", "-framerate", "25", "-t", str(seconds), "-i", still, "-vf", fit, part)
            parts.append(part)
        listing = os.path.join(tmp, "list.txt")
        with open(listing, "w", encoding="utf-8") as f:
            f.writelines("file '%s'\n" % p for p in parts)
        ffmpeg("-f", "concat", "-safe", "0", "-i", listing, "-c:v", "libvpx-vp9", "-crf", "35", "-b:v", "0",
               "-pix_fmt", "yuv420p", "-an", out)
    print("saved %s (%.0f KB)" % (out, os.path.getsize(out) / 1024))


if __name__ == "__main__":
    for flow in FLOWS:
        gif(flow)
    demo()
