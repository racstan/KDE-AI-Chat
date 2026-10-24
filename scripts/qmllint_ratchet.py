#!/usr/bin/env python3
"""qmllint ratchet: warning counts per QML file may only go down.

The widget has hundreds of existing qmllint warnings, so failing on any
warning would block every change. Instead each file's count is recorded in
scripts/qmllint_baseline.json; CI fails if a file gets more warnings than
its baseline, or if a new file has any. Lower counts are reported so the
baseline can be tightened with --update.

Usage:
  scripts/qmllint_ratchet.py [--qmllint PATH] [--update]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PACKAGE = os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents")
BASELINE = os.path.join(ROOT, "scripts", "qmllint_baseline.json")


def find_qmllint(explicit):
    candidates = [explicit] if explicit else [
        "qmllint6", "/usr/lib/qt6/bin/qmllint", "/usr/lib64/qt6/bin/qmllint", "qmllint",
    ]
    for candidate in candidates:
        path = shutil.which(candidate) or (candidate if os.access(candidate, os.X_OK) else None)
        if path:
            return path
    sys.exit("qmllint (Qt 6) not found")


def qml_files():
    for directory, _dirs, files in os.walk(PACKAGE):
        for name in sorted(files):
            if name.endswith(".qml"):
                yield os.path.relpath(os.path.join(directory, name), ROOT)


def count_warnings(qmllint, path):
    result = subprocess.run(
        [qmllint, path], capture_output=True, text=True, cwd=ROOT, timeout=300,
    )
    output = result.stdout + result.stderr
    return sum(1 for line in output.splitlines() if line.startswith(("Warning:", "Error:")))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--qmllint")
    parser.add_argument("--update", action="store_true", help="rewrite the baseline")
    args = parser.parse_args()

    qmllint = find_qmllint(args.qmllint)
    counts = {path: count_warnings(qmllint, path) for path in qml_files()}

    if args.update:
        with open(BASELINE, "w", encoding="utf-8") as f:
            json.dump(counts, f, indent=2, sort_keys=True)
            f.write("\n")
        print(f"Baseline written: {sum(counts.values())} warnings in {len(counts)} files")
        return 0

    with open(BASELINE, encoding="utf-8") as f:
        baseline = json.load(f)

    worse, better = [], []
    for path, count in sorted(counts.items()):
        allowed = baseline.get(path, 0)
        if count > allowed:
            worse.append(f"  {path}: {count} warnings (baseline {allowed})")
        elif count < allowed:
            better.append(f"  {path}: {count} warnings (baseline {allowed})")

    if better:
        print("Fewer warnings than baseline (run with --update to lock in):")
        print("\n".join(better))
    if worse:
        print("More qmllint warnings than baseline:")
        print("\n".join(worse))
        print(f"Run `{qmllint} <file>` to see them.")
        return 1
    print(f"qmllint ratchet OK: {sum(counts.values())} warnings in {len(counts)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
