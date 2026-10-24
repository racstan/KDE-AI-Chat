#!/usr/bin/env python3
"""File-size guard: keep source files small (see docs/plan/modularisation.md).

A QML, JS or Python file in the widget package may have at most LIMIT lines,
unless it is listed in scripts/file_size_allowlist.json. Listed files may not
grow past their recorded size; when one shrinks, the allowlist should be
tightened (--update), and a file back under the limit is dropped from it.

Usage:
  scripts/check_file_sizes.py [--update]
"""
import argparse
import json
import os
import sys

LIMIT = 400
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PACKAGE = os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents")
ALLOWLIST = os.path.join(ROOT, "scripts", "file_size_allowlist.json")
EXTENSIONS = (".qml", ".js", ".py")


def source_files():
    for directory, dirs, files in os.walk(PACKAGE):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for name in sorted(files):
            if name.endswith(EXTENSIONS):
                yield os.path.relpath(os.path.join(directory, name), ROOT)


def line_count(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return sum(1 for _ in f)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--update", action="store_true", help="rewrite the allowlist")
    args = parser.parse_args()

    sizes = {path: line_count(path) for path in source_files()}
    oversized = {path: n for path, n in sizes.items() if n > LIMIT}

    if args.update:
        with open(ALLOWLIST, "w", encoding="utf-8") as f:
            json.dump(oversized, f, indent=2, sort_keys=True)
            f.write("\n")
        print(f"Allowlist written: {len(oversized)} files over {LIMIT} lines")
        return 0

    with open(ALLOWLIST, encoding="utf-8") as f:
        allowlist = json.load(f)

    failures = []
    for path, n in sorted(oversized.items()):
        allowed = allowlist.get(path)
        if allowed is None:
            failures.append(f"  {path}: {n} lines (limit {LIMIT}; split it up)")
        elif n > allowed:
            failures.append(f"  {path}: {n} lines (allowlisted at {allowed}; it may only shrink)")

    stale = sorted(path for path in allowlist if sizes.get(path, 0) < allowlist[path])
    if stale:
        print("Allowlisted files that shrank or are gone (run with --update to tighten):")
        print("\n".join(f"  {path}" for path in stale))
    if failures:
        print("Files too large:")
        print("\n".join(failures))
        return 1
    print(f"File sizes OK: {len(oversized)} allowlisted files over {LIMIT} lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
