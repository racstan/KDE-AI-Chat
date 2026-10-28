#!/usr/bin/env python3
"""Makes the YouTube video from the docs media: every part shows the widget on the right and a
caption on the left (a title and a few plain lines on what is shown), between an intro and a
closing card. Run it after scripts/dev-media.sh, which leaves the stills in docs/media/ and the
flow frames in build/media-frames/.

Usage: youtube.py <frames-dir> <docs-media-dir> <out.mp4>

1920x1080, H.264 (crf 18, 30 fps, faststart), no sound. Not for docs/ (too big to commit).
Needs ffmpeg, Pillow and the Noto Sans fonts. Exits 1 if a part is missing or ffmpeg fails.
"""
import glob
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
BG, INK, MUTED, ACCENT = (239, 240, 241), (35, 38, 41), (77, 84, 91), (61, 174, 233)
TEXT_X, TEXT_W = 110, 640          # the caption column
BOX_X, BOX_W, BOX_H = 840, 1000, 980  # where the widget goes
FPS_FRAMES = 12.5                  # the tour grabs a flow frame every 80 ms
STILL_SECONDS, FLOW_HOLD, CARD_SECONDS = 6, 3, 4
FONT = "/usr/share/fonts/truetype/NotoSans-Regular.ttf"
BOLD = "/usr/share/fonts/truetype/NotoSans-Bold.ttf"

# (kind, name, title, lines): a flow plays build/media-frames/<name>/, a still shows <name>-light.png.
PARTS = [
    ("flow", "send-message", "Ask anything",
     "Click the widget in your panel, type a question and press Enter.",
     "The answer appears word by word, right on your desktop."),
    ("still", "chat-conversation", "Answers that are easy to read",
     "Replies are formatted: bold words, lists, and code with a copy button.",
     "Your name and the AI's name and picture show above each message."),
    ("still", "chat-history", "All your chats in one place",
     "Open the history to find older chats.",
     "Pin the ones you use most and group chats into projects."),
    ("flow", "search", "Search every chat",
     "Type a few words to find any message in any chat.",
     "Click a result to jump straight to it."),
    ("flow", "commands", "Shortcuts with /",
     "Type / to see commands and your own saved prompts.",
     "For example /summarize, or /image to make a picture."),
    ("still", "chat-ask", "The AI can ask you",
     "When it needs a choice or a missing detail, it asks you in the chat.",
     "Answer with a click instead of letting it guess."),
    ("flow", "incognito", "Incognito chats",
     "An incognito chat is never saved.",
     "When you leave it, its messages are gone."),
    ("still", "chat-settings", "Chat info",
     "See which AI answers this chat, how much it has used, and its own settings.",
     "A chat keeps the mode it was started in."),
    ("still", "schedule-editor", "Let it work on a schedule",
     "Have the AI run a prompt at set times, like a morning summary.",
     "Describe the schedule in plain words and check it before saving."),
    ("still", "settings-connection", "Settings: your AI",
     "Use online services such as OpenAI, Anthropic, Gemini or OpenRouter,",
     "or a model on your own computer, found with one click. Keys stay in KDE Wallet."),
    ("still", "settings-chat", "Settings: chats",
     "Choose how much of a chat the AI sees, how chats are named,",
     "whether the AI may ask you questions, and a folder new chats work in."),
    ("still", "settings-personality", "Settings: personality",
     "Tell the AI your name and a little about you,",
     "and give it a name, a tone and a picture of its own."),
    ("still", "settings-memory", "Settings: memory",
     "Notes you ask the AI to keep, sent only when they fit what you ask.",
     "Add, pin, edit or delete any of them here."),
    ("still", "settings-voice-speechnote", "Settings: voice",
     "Have replies read aloud and dictate instead of typing.",
     "Speech is handled on your computer by Speech Note."),
    ("still", "settings-appearance", "Settings: appearance",
     "Name the widget, pick its panel icon (even an animated one),",
     "and set the text size and spacing of the chat."),
]
INTRO = ("KDE AI Chat 1.4", "An AI chat that lives in your KDE Plasma panel.",
         "Use online AI services or models on your own computer.")
OUTRO = ("Get KDE AI Chat", "github.com/racstan/KDE-AI-Chat",
         "Free for personal and other noncommercial use.")


def ffmpeg(*args):
    done = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args], capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit("ffmpeg failed: %s" % done.stderr.strip()[-600:])


def wrap(draw, text, font, width):
    lines, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if draw.textlength(trial, font=font) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    return lines + ([line] if line else [])


def card(path, title, lines, centred=False):
    """The background of a part: the caption on the left (or centred, for intro and outro)."""
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    big, body = ImageFont.truetype(BOLD, 64 if centred else 52), ImageFont.truetype(FONT, 36 if centred else 32)
    width = 1400 if centred else TEXT_W
    rows = [(t, big, INK) for t in wrap(draw, title, big, width)]
    paragraphs = []
    for text in lines:  # a line ending in a comma goes on in the next one: one paragraph
        if paragraphs and paragraphs[-1].endswith(","):
            paragraphs[-1] += " " + text
        else:
            paragraphs.append(text)
    for text in paragraphs:
        rows.append(None)
        rows += [(t, body, MUTED) for t in wrap(draw, text, body, width)]
    heights = [24 if r is None else r[1].size + 18 for r in rows]
    y = (H - sum(heights)) // 2
    if not centred:
        draw.rectangle([TEXT_X, y - 40, TEXT_X + 90, y - 32], fill=ACCENT)
    for row, h in zip(rows, heights):
        if row:
            x = (W - draw.textlength(row[0], font=row[1])) // 2 if centred else TEXT_X
            draw.text((x, y), row[0], font=row[1], fill=row[2])
        y += h
    img.save(path)


def part(tmp, i, kind, name, title, lines, media, frames):
    bg, out = os.path.join(tmp, "%02d.png" % i), os.path.join(tmp, "%02d.mp4" % i)
    card(bg, title, lines)
    place = ("[1]scale=w=%d:h=%d:force_original_aspect_ratio=decrease:flags=lanczos[w];"
             "[0][w]overlay=x=%d+(%d-w)/2:y=(H-h)/2:shortest=1,format=yuv420p" % (BOX_W, BOX_H, BOX_X, BOX_W))
    if kind == "flow":
        if len(glob.glob(os.path.join(frames, name, "[0-9][0-9][0-9][0-9].png"))) < 10:
            sys.exit("youtube: flow %s has too few frames" % name)
        src = ["-framerate", str(FPS_FRAMES), "-i", os.path.join(frames, name, "%04d.png")]
        place = place.replace("[1]scale", "[1]tpad=stop_mode=clone:stop_duration=%d,scale" % FLOW_HOLD)
    else:
        still = os.path.join(media, name + "-light.png")
        if not os.path.exists(still):
            sys.exit("youtube: %s is missing" % still)
        src = ["-loop", "1", "-t", str(STILL_SECONDS), "-i", still]
    ffmpeg("-loop", "1", "-framerate", "30", "-i", bg, *src, "-filter_complex", place, "-r", "30",
           "-c:v", "libx264", "-crf", "14", out)
    return out


def still_card(tmp, name, text):
    bg, out = os.path.join(tmp, name + ".png"), os.path.join(tmp, name + ".mp4")
    card(bg, text[0], text[1:], centred=True)
    ffmpeg("-loop", "1", "-framerate", "30", "-t", str(CARD_SECONDS), "-i", bg, "-vf", "format=yuv420p",
           "-c:v", "libx264", "-crf", "14", out)
    return out


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    frames, media, out = (os.path.abspath(a) for a in sys.argv[1:])
    with tempfile.TemporaryDirectory() as tmp:
        parts = [still_card(tmp, "intro", INTRO)]
        parts += [part(tmp, i, kind, name, title, lines, media, frames)
                  for i, (kind, name, title, *lines) in enumerate(PARTS)]
        parts.append(still_card(tmp, "outro", OUTRO))
        listing = os.path.join(tmp, "list.txt")
        with open(listing, "w", encoding="utf-8") as f:
            f.writelines("file '%s'\n" % p for p in parts)
        ffmpeg("-f", "concat", "-safe", "0", "-i", listing, "-c:v", "libx264", "-preset", "slow", "-crf", "18",
               "-r", "30", "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-an", out)
    print("saved %s (%.0f KB)" % (out, os.path.getsize(out) / 1024))


if __name__ == "__main__":
    main()
