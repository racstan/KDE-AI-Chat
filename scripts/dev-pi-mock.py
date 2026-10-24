#!/usr/bin/env python3
"""A fake `pi --mode rpc` for testing the Pi bridge and the widget's Pi mode.

Each prompt replays a recorded Pi run (default: the write-a-file capture in
tests/fixtures; set KDEAICHAT_PI_MOCK_FIXTURE to use another). The replay
pauses at a dialog until the client answers it, and `abort` ends the run the
way Pi does. With KDEAICHAT_PI_MOCK_LOG set, the arguments, folder and every
command received are appended there as JSON lines.

Install as `pi` by putting a symlink named `pi` on PATH.
"""
import json
import os
import sys
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
FIXTURE = os.environ.get("KDEAICHAT_PI_MOCK_FIXTURE") or os.path.join(ROOT, "tests/fixtures/pi-0.84-ollama-write.jsonl")
LOG = os.environ.get("KDEAICHAT_PI_MOCK_LOG")
DELAY = float(os.environ.get("KDEAICHAT_PI_MOCK_DELAY", "0.002"))
out_lock = threading.Lock()
answers = {}
answered = threading.Condition()
aborted = threading.Event()


def log(entry):
    if LOG:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")


def emit(obj):
    with out_lock:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()


def replay(prompt_id):
    events = [json.loads(line) for line in open(FIXTURE, encoding="utf-8") if line.strip()]
    for event in events:
        if aborted.is_set():
            emit({"type": "message_end", "message": {"role": "assistant", "content": [], "stopReason": "aborted",
                                                     "errorMessage": "Request was aborted", "usage": {"input": 0, "output": 0}}})
            emit({"type": "agent_end", "messages": []})
            emit({"type": "agent_settled"})
            return
        if event.get("type") == "response":
            event["id"] = prompt_id
        emit(event)
        if event.get("type") == "extension_ui_request" and event.get("method") in ("select", "confirm", "input", "editor"):
            with answered:
                answered.wait_for(lambda: event["id"] in answers or aborted.is_set(), timeout=60)
        time.sleep(DELAY)


def main():
    log({"argv": sys.argv[1:], "cwd": os.getcwd()})
    if "--version" in sys.argv:
        print("0.84.2 (mock)")
        return
    for raw in sys.stdin:
        command = json.loads(raw)
        log({"command": command})
        if command.get("type") == "prompt":
            aborted.clear()
            threading.Thread(target=replay, args=(command.get("id"),), daemon=True).start()
        elif command.get("type") == "abort":
            aborted.set()
            with answered:
                answered.notify_all()
            emit({"type": "response", "command": "abort", "success": True})
        elif command.get("type") == "extension_ui_response":
            with answered:
                answers[command.get("id")] = command
                answered.notify_all()


if __name__ == "__main__":
    main()
