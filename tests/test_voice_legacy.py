"""The old built-in voice engines' systemd units are stopped and removed once, at widget start.

Never touches real units: KDEAICHAT_UNIT_DIR / KDEAICHAT_SYSTEMCTL point at a temporary folder and a fake systemctl.
"""
import base64
import json
import os
import subprocess
import sys
import threading

import pytest

from tests.conftest import UI_DIR

from kdeaichat import voice_legacy

OLD = ("kde-ai-stt.socket", "kde-ai-stt.service", "kde-ai-tts.service")


@pytest.fixture
def units(tmp_path, monkeypatch):
    folder = tmp_path / "units"
    folder.mkdir()
    monkeypatch.setenv("KDEAICHAT_UNIT_DIR", str(folder))
    return folder


def test_old_units_are_stopped_disabled_and_deleted(units):
    for name in OLD:
        (units / name).write_text("[Unit]\n")
    (units / "sockets.target.wants").mkdir()
    os.symlink(str(units / "kde-ai-stt.socket"), str(units / "sockets.target.wants" / "kde-ai-stt.socket"))
    (units / "default.target.wants").mkdir()
    os.symlink(str(units / "kde-ai-tts.service"), str(units / "default.target.wants" / "kde-ai-tts.service"))
    (units / "kdeaichat-sched-x.timer").write_text("[Timer]\n")
    (units / "kdeaichat-run@.service").write_text("[Service]\n")
    calls = []
    done = voice_legacy.cleanup_old_units(run=lambda args: calls.append(args) or 0)
    assert done["changed"] and sorted(done["units"]) == sorted(OLD)
    assert calls == [["disable", "--now", *OLD], ["daemon-reload"], ["reset-failed", *OLD]]
    assert sorted(os.listdir(units)) == ["default.target.wants", "kdeaichat-run@.service", "kdeaichat-sched-x.timer",
                                         "sockets.target.wants"]
    assert os.listdir(units / "sockets.target.wants") == [] and os.listdir(units / "default.target.wants") == []
    # Again: nothing to do, systemctl is not called at all.
    calls.clear()
    again = voice_legacy.cleanup_old_units(run=lambda args: calls.append(args) or 0)
    assert calls == [] and again["units"] == [] and not again["changed"]


def test_only_the_units_that_exist_are_named(units):
    (units / "kde-ai-stt.socket").write_text("[Socket]\n")
    calls = []
    voice_legacy.cleanup_old_units(run=lambda args: calls.append(args) or 0)
    assert calls[0] == ["disable", "--now", "kde-ai-stt.socket"]


def test_a_sandbox_leaves_other_processes_alone(units):
    fake = units / "voice_helper.py"
    fake.write_text("import time\ntime.sleep(60)\n")
    proc = subprocess.Popen([sys.executable, str(fake), "--stt-server"])
    other = subprocess.Popen([sys.executable, str(fake), "--tts-server", "--token-file", "x"])
    try:
        for _ in range(100):
            if {proc.pid, other.pid} <= set(voice_legacy._server_pids()):
                break
            threading.Event().wait(0.05)
        assert voice_legacy.cleanup_old_units(run=lambda args: 0)["killed"] == 0 and proc.poll() is None
        done = voice_legacy.cleanup_old_units(run=lambda args: 0, allow_kill=True)
        assert done["killed"] == 2
        assert proc.wait(timeout=5) != 0 and other.wait(timeout=5) != 0
    finally:
        for p in (proc, other):
            if p.poll() is None:
                p.kill()
                p.wait()


def test_kokoro_worker_stop_asks_over_its_socket(tmp_path):
    import socket
    path = str(tmp_path / "kokoro.sock")
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(path)
    server.listen(1)
    got = []

    def serve():
        conn, _ = server.accept()
        got.append(conn.recv(100))
        conn.close()

    thread = threading.Thread(target=serve, daemon=True)
    thread.start()
    assert voice_legacy.stop_kokoro_worker(str(tmp_path)) is True
    thread.join(5)
    server.close()
    assert json.loads(got[0]) == {"op": "stop"}
    assert voice_legacy.stop_kokoro_worker(str(tmp_path / "nothing")) is False


def test_startup_command_through_the_helper(units, tmp_path):
    for name in OLD:
        (units / name).write_text("[Unit]\n")
    env = dict(os.environ, KDEAICHAT_UNIT_DIR=str(units), KDEAICHAT_SYSTEMCTL="true")
    out = subprocess.run([sys.executable, os.path.join(UI_DIR, "kde_ai_helper.py"), "voice_startup",
                          base64.b64encode(b"{}").decode()], env=env, capture_output=True, text=True, timeout=30)
    reply = json.loads(out.stdout)
    assert reply["ok"] and sorted(reply["legacy"]["units"]) == sorted(OLD)
    assert os.listdir(units) == []
    assert not any(n in os.listdir(units) for n in OLD)


def test_the_widget_runs_it_at_start_when_one_of_the_unit_files_exists():
    commands = open(os.path.join(UI_DIR, "chat", "HelperCommands.qml"), encoding="utf-8").read()
    assert "voice_startup" in commands
    for unit in OLD:
        assert unit in commands
