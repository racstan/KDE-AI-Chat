#!/usr/bin/env python3
"""Puts background music under the YouTube video (youtube.py makes it silent).

Usage: add_music.py <video.mp4> <out.mp4> <track> [<track> ...]

The tracks play one after another with a 4 s crossfade (starting over from the first as often as the video needs), each brought to the same low loudness (LOUDNESS LUFS:
background, not a song) and softened (no highs above SOFTEN_HZ), cut to the video's length, faded in over 2 s and out over 5 s.
The picture is copied as it is; the sound is AAC 192 kb/s. The tracks must be ones the video may use
(the ones in scripts/media/CREDITS.md are public domain, CC0); they are not kept in the repository.
Exits 1 if ffmpeg fails.
"""
import subprocess
import sys

LOUDNESS = -30
SOFTEN_HZ = 3500   # the bright top is taken off, so it sounds like a backdrop rather than a song
CROSSFADE = 4
FADE_IN, FADE_OUT = 2, 5


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    video, out, tracks = sys.argv[1], sys.argv[2], sys.argv[3:]
    length = duration(video)
    lengths = [duration(t) for t in tracks]
    played, music = [], -CROSSFADE
    while music < length:   # loop the tracks until they cover the video
        i = len(played) % len(tracks)
        played.append(tracks[i])
        music += lengths[i] - CROSSFADE
    tracks = played
    inputs = ["-i", video]
    chain = []
    for i, track in enumerate(tracks, start=1):
        inputs += ["-i", track]
        chain.append("[%d:a]aresample=48000,aformat=channel_layouts=stereo,lowpass=f=%d,loudnorm=I=%d:TP=-2:LRA=7[t%d]" % (i, SOFTEN_HZ, LOUDNESS, i))
    last = "t1"
    for i in range(2, len(tracks) + 1):
        chain.append("[%s][t%d]acrossfade=d=%d:c1=tri:c2=tri[x%d]" % (last, i, CROSSFADE, i))
        last = "x%d" % i
    chain.append("[%s]atrim=0:%.3f,afade=t=in:d=%d,afade=t=out:st=%.3f:d=%d[music]" % (last, length, FADE_IN, length - FADE_OUT, FADE_OUT))
    done = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *inputs,
                           "-filter_complex", ";".join(chain), "-map", "0:v", "-map", "[music]",
                           "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-shortest", out],
                          capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit("ffmpeg failed: %s" % done.stderr.strip()[-600:])
    print("saved %s (%.0f s)" % (out, duration(out)))


if __name__ == "__main__":
    main()
