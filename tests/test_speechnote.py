"""Speech Note helper commands with a fake busctl / flatpak / dsnote and a fake session bus socket."""
import base64
import json
import os
import socket
import struct
import subprocess
import sys
import threading

import pytest

from kdeaichat import minidbus, speechnote, speechnote_bus
from kdeaichat.speechnote_bus import SpeechNoteError

UI = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui")
SECRET = "my private diary entry 12345"

# Fake busctl. Behaviour lives in $FAKE_DIR/config.json:
#   present: bool, State: int or list (a list is consumed one entry per read, the last one repeats),
#   props: {name: json value}, returns: {method: int}, signals: [lines printed after SttStopListen]
FAKE_BUSCTL = r"""#!%(py)s
import json, os, sys, time
d = os.environ["FAKE_DIR"]
cfg = json.load(open(d + "/config.json"))
args = [a for a in sys.argv[1:] if not a.startswith("--")]
def log(line):
    open(d + "/calls.log", "a").write(line + "\n")
def out(type_, data):
    print(json.dumps({"type": type_, "data": data}))
cmd = args[0]
if cmd == "get-property":
    name = args[4]
    if not cfg.get("present"):
        sys.stderr.write("Failed to get property: The name is not activatable\n"); sys.exit(1)
    if name == "State":
        st = cfg["State"]
        if isinstance(st, list):
            val = st[0]
            if len(st) > 1:
                cfg["State"] = st[1:]; json.dump(cfg, open(d + "/config.json", "w"))
        else:
            val = st
        out("i", val)
    else:
        v = cfg["props"][name]
        out("a{sv}" if isinstance(v, dict) else ("i" if isinstance(v, int) else "s"), v)
elif cmd == "call":
    method = args[4]
    log(" ".join(args[4:]))
    if cfg.get("call_fails") == method:
        sys.stderr.write("boom\n"); sys.exit(1)
    out("i", [cfg.get("returns", {}).get(method, 0)])
elif cmd == "monitor":
    def calls():
        try: return open(d + "/calls.log").read()
        except OSError: return ""
    def wait_for(word):
        for _ in range(300):
            if word in calls(): return True
            time.sleep(0.02)
    wait_for("KeepAliveService")
    print(json.dumps({"type": "method_call", "interface": "org.mkiol.Speech", "member": "KeepAliveService", "payload": {"type": "", "data": []}}), flush=True)
    print(json.dumps({"type": "signal", "interface": "org.freedesktop.DBus", "member": "NameOwnerChanged", "payload": {"type": "sss", "data": ["a", "b", "c"]}}), flush=True)
    wait_for(cfg.get("signals_after", "SttStopListen"))
    for line in cfg.get("signals", []):
        print(json.dumps(line), flush=True)
    time.sleep(30)
"""

FAKE_FLATPAK = r"""#!%(py)s
import json, os, sys, time
d = os.environ["FAKE_DIR"]
cfg = json.load(open(d + "/config.json"))
if sys.argv[1] == "info":
    sys.exit(0 if cfg.get("flatpak") else 1)
if sys.argv[1] == "run":
    open(d + "/launched", "w").write(json.dumps(sys.argv[1:]))
    if cfg.get("launch_dies"):
        sys.exit(1)
    time.sleep(cfg.get("launch_delay", 0))
    if not cfg.get("never_appears"):
        cfg["present"] = True
        json.dump(cfg, open(d + "/config.json", "w"))
    time.sleep(2)
"""

FAKE_DSNOTE = FAKE_FLATPAK.replace('sys.argv[1] == "run"', 'sys.argv[1] == "--service"').replace(
    'open(d + "/launched", "w").write(json.dumps(sys.argv[1:]))', 'open(d + "/launched", "w").write(json.dumps(["dsnote"] + sys.argv[1:]))')

STT = {"en_fasterwhisper_small": {"type": "as", "data": ["en_fasterwhisper_small", "English (FasterWhisper Small) / en", "", "en"]}}
TTS = {"en_kokoro_82m_af_alloy": {"type": "as", "data": ["en_kokoro_82m_af_alloy", "English (Kokoro 82M Alloy Female) / en", "", "en"]}}


class Fake:
    def __init__(self, root):
        self.dir = str(root / "fake")
        os.makedirs(self.dir)
        self.config = {"present": False, "State": 3, "props": {
            "SttModels": STT, "TtsModels": TTS, "DefaultSttModel": "en_fasterwhisper_small",
            "DefaultTtsModel": "en_kokoro_82m_af_alloy", "DefaultSttLang": "en", "DefaultTtsLang": "en", "CurrentTask": 7}}
        self.save()
        self.busctl = self.script("busctl", FAKE_BUSCTL)
        self.flatpak = self.script("flatpak", FAKE_FLATPAK)
        self.dsnote = self.script("dsnote", FAKE_DSNOTE)

    def script(self, name, body):
        path = os.path.join(self.dir, name)
        with open(path, "w") as f:
            f.write(body % {"py": sys.executable})
        os.chmod(path, 0o755)
        return path

    def save(self):
        with open(os.path.join(self.dir, "config.json"), "w") as f:
            json.dump(self.config, f)

    def set(self, **values):
        self.config.update(values)
        self.save()

    def calls(self):
        try:
            with open(os.path.join(self.dir, "calls.log")) as f:
                return f.read().splitlines()
        except OSError:
            return []

    def launched(self):
        try:
            with open(os.path.join(self.dir, "launched")) as f:
                return json.load(f)
        except OSError:
            return None


@pytest.fixture
def fake(tmp_path, monkeypatch):
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path / "run"))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "data"))
    (tmp_path / "run").mkdir(mode=0o700)
    f = Fake(tmp_path)
    monkeypatch.setenv("FAKE_DIR", f.dir)
    monkeypatch.setenv("KDEAICHAT_BUSCTL", f.busctl)
    monkeypatch.setenv("KDEAICHAT_FLATPAK", f.flatpak)
    monkeypatch.setenv("KDEAICHAT_DSNOTE", "")
    monkeypatch.setattr(speechnote_bus, "READY_POLL", 0.02)
    monkeypatch.setattr(speechnote_bus, "NOT_CONFIGURED_GRACE", 0.2)
    monkeypatch.setattr(speechnote, "POLL", 0.02)
    monkeypatch.setenv("PATH", "/nonexistent")  # no real flatpak/dsnote/busctl may leak in: only the fakes count
    return f


def run(name, payload=None, capsys=None):
    speechnote.COMMANDS[name](payload or {})
    return json.loads(capsys.readouterr().out.strip().splitlines()[-1])


# ---- status ------------------------------------------------------------------------------------

def test_status_not_installed(fake, capsys):
    fake.set(flatpak=False)
    reply = run("speechnote_status", capsys=capsys)
    assert reply["installed"] is False and reply["running"] is False and reply["kind"] == ""
    assert reply["stt_models"] == []


def test_status_flatpak_not_running_starts_nothing(fake, capsys):
    fake.set(flatpak=True)
    reply = run("speechnote_status", capsys=capsys)
    assert (reply["installed"], reply["kind"], reply["running"]) == (True, "flatpak", False)
    assert fake.launched() is None


def test_status_native(fake, capsys, monkeypatch):
    monkeypatch.setenv("KDEAICHAT_DSNOTE", fake.dsnote)
    assert run("speechnote_status", capsys=capsys)["kind"] == "native"


def test_status_running_lists_models(fake, capsys):
    fake.set(present=True, flatpak=True)
    reply = run("speechnote_status", capsys=capsys)
    assert reply["running"] and reply["ready"] and reply["state"] == 3 and reply["models_known"]
    assert reply["stt_models"] == [{"id": "en_fasterwhisper_small", "name": "English (FasterWhisper Small) / en", "lang": "en"}]
    assert reply["tts_models"][0]["id"] == "en_kokoro_82m_af_alloy"
    assert reply["default_stt_model"] == "en_fasterwhisper_small" and reply["default_tts_lang"] == "en"


def test_status_running_without_a_detected_install_still_installed(fake, capsys):
    fake.set(present=True, flatpak=False)
    assert run("speechnote_status", capsys=capsys)["installed"] is True


# ---- start -------------------------------------------------------------------------------------

def test_start_flatpak_waits_for_state_3(fake, capsys):
    fake.set(flatpak=True, launch_delay=0.2, State=[2, 2, 3])
    reply = run("speechnote_start", capsys=capsys)
    assert reply == {"type": "speechnote_started", "state": 3, "started": True}
    argv = fake.launched()
    assert argv[:2] == ["run", "--own-name=net.mkiol.Speech"] and argv[-2:] == ["net.mkiol.SpeechNote", "--service"]
    log = os.path.join(os.environ["XDG_RUNTIME_DIR"], "kdeaichat", "speechnote", "service.log")
    assert oct(os.stat(log).st_mode & 0o777) == "0o600"


def test_start_native(fake, capsys, monkeypatch):
    monkeypatch.setenv("KDEAICHAT_DSNOTE", fake.dsnote)
    assert run("speechnote_start", capsys=capsys)["state"] == 3
    assert fake.launched() == ["dsnote", "--service"]


def test_start_already_running_does_not_launch(fake, capsys):
    fake.set(present=True)
    assert run("speechnote_start", capsys=capsys)["started"] is False
    assert fake.launched() is None


def test_start_not_installed(fake, capsys):
    fake.set(flatpak=False)
    assert run("speechnote_start", capsys=capsys)["code"] == "not_installed"


def test_start_service_dies(fake, capsys):
    fake.set(flatpak=True, launch_dies=True)
    assert run("speechnote_start", capsys=capsys)["code"] == "service_failed_to_start"


def test_start_never_appears_times_out(fake, capsys, monkeypatch):
    fake.set(flatpak=True, never_appears=True)
    monkeypatch.setattr(speechnote_bus, "ensure_ready", lambda timeout=0.5, _orig=speechnote_bus.ensure_ready: _orig(0.5))
    assert run("speechnote_start", capsys=capsys)["code"] == "service_failed_to_start"


def test_start_stuck_busy_times_out(fake, capsys, monkeypatch):
    fake.set(present=True, State=2)
    monkeypatch.setattr(speechnote_bus, "ensure_ready", lambda timeout=0.5, _orig=speechnote_bus.ensure_ready: _orig(0.5))
    assert run("speechnote_start", capsys=capsys)["code"] == "timeout"


def test_start_not_configured(fake, capsys):
    fake.set(present=True, State=1)
    assert run("speechnote_start", capsys=capsys)["code"] == "not_configured"


def test_start_state_1_for_a_moment_is_fine(fake, capsys):
    fake.set(present=True, State=[1, 1, 3])
    assert run("speechnote_start", capsys=capsys)["state"] == 3


# ---- dictation ---------------------------------------------------------------------------------

def test_listen_start_keepalive_stop_returns_text(fake, capsys):
    fake.set(present=True, returns={"SttStartListen": 7, "KeepAliveTask": 9000, "SttStopListen": 0}, signals=[
        {"type": "signal", "interface": "org.mkiol.Speech", "member": "SttIntermediateTextDecoded", "payload": {"type": "ssi", "data": ["hel", "en", 7]}},
        {"type": "signal", "interface": "org.mkiol.Speech", "member": "SttTextDecoded", "payload": {"type": "ssi", "data": ["other", "en", 3]}},
        {"type": "signal", "interface": "org.mkiol.Speech", "member": "SttTextDecoded", "payload": {"type": "ssi", "data": ["hello world", "en", 7]}},
    ])
    assert run("speechnote_listen_start", {"model": "en_fasterwhisper_small"}, capsys) == {"type": "speechnote_listening", "task": 7}
    assert run("speechnote_keepalive", {"task": 7}, capsys) == {"type": "speechnote_keepalive", "task": 7, "alive": True}
    assert run("speechnote_listen_stop", {"task": 7, "timeout": 5}, capsys) == {
        "type": "speechnote_text", "text": "hello world", "lang": "en", "task": 7}
    calls = fake.calls()
    assert "SttStartListen iss 1 en_fasterwhisper_small " in calls[0] + " "
    assert "SttStopListen i 7" in calls


def test_listen_start_default_model_is_empty_string(fake, capsys):
    fake.set(present=True, returns={"SttStartListen": 4})
    run("speechnote_listen_start", capsys=capsys)
    assert fake.calls()[0] == "SttStartListen iss 1  "


def test_keepalive_reports_finished_task(fake, capsys):
    fake.set(present=True, returns={"KeepAliveTask": 0})
    assert run("speechnote_keepalive", {"task": 2}, capsys)["alive"] is False


def test_keepalive_service_only_when_running(fake, capsys):
    fake.set(present=False)
    assert run("speechnote_keepalive_service", capsys=capsys) == {"type": "speechnote_service_kept", "running": False}
    assert fake.launched() is None, "never starts the service"
    assert not any(c.startswith("KeepAliveService") for c in fake.calls())
    fake.set(present=True, returns={"KeepAliveService": 1})
    assert run("speechnote_keepalive_service", capsys=capsys) == {"type": "speechnote_service_kept", "running": True}
    assert any(c.startswith("KeepAliveService") for c in fake.calls())


def test_listen_stop_timeout(fake, capsys):
    fake.set(present=True, returns={"SttStopListen": 0}, signals=[])
    assert run("speechnote_listen_stop", {"task": 7, "timeout": 1}, capsys)["code"] == "timeout"


def test_listen_stop_microphone_error(fake, capsys):
    fake.set(present=True, signals=[{"type": "signal", "interface": "org.mkiol.Speech", "member": "ErrorOccured",
                                     "payload": {"type": "i", "data": [1]}}])
    reply = run("speechnote_listen_stop", {"task": 7, "timeout": 5}, capsys)
    assert reply["code"] == "mic_error"


def test_listen_stop_rejected(fake, capsys):
    fake.set(present=True, returns={"SttStopListen": 1})
    assert run("speechnote_listen_stop", {"task": 7, "timeout": 5}, capsys)["code"] == "bus_error"


def test_listen_start_refused_maps_state(fake, capsys):
    fake.set(present=True, returns={"SttStartListen": -1})
    fake.set(State=[3, 1])  # idle for ensure_ready, then not configured when asked why
    assert run("speechnote_listen_start", capsys=capsys)["code"] == "not_configured"
    fake.set(present=True, State=[3, 2])
    assert run("speechnote_listen_start", capsys=capsys)["code"] == "busy"
    fake.set(present=True, State=3)
    assert run("speechnote_listen_start", capsys=capsys)["code"] == "bus_error"


def test_listen_cancel(fake, capsys):
    fake.set(present=True)
    assert run("speechnote_listen_cancel", {"task": 7}, capsys) == {"type": "speechnote_cancelled", "task": 7}
    assert fake.calls() == ["Cancel i 7"]


def test_bus_failure_is_bus_error(fake, capsys):
    fake.set(present=True, call_fails="KeepAliveTask")
    assert run("speechnote_keepalive", {"task": 7}, capsys)["code"] == "bus_error"


def test_missing_busctl_is_bus_error(fake, capsys, monkeypatch):
    monkeypatch.setenv("KDEAICHAT_BUSCTL", "")
    assert run("speechnote_keepalive", {"task": 7}, capsys)["code"] == "bus_error"


def test_bad_inputs(fake, capsys):
    assert run("speechnote_keepalive", {}, capsys)["code"] == "bad_request"
    assert run("speechnote_listen_start", {"model": "--evil"}, capsys)["code"] == "bad_request"
    assert run("speechnote_speak", {"text": "  "}, capsys)["code"] == "bad_request"


# ---- read aloud --------------------------------------------------------------------------------

class FakeBus:
    """A session bus that accepts one method call per connection and records its body."""

    def __init__(self, path, reply_task=11):
        self.path = path
        self.reply_task = reply_task
        self.seen = []
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(path)
        self.server.listen(5)
        threading.Thread(target=self.serve, daemon=True).start()

    @staticmethod
    def reply(serial, reply_serial, sig, body):
        def field(code, s, value):
            return bytes([code, len(s)]) + s.encode() + b"\0" + value
        fields = b""
        fields += field(5, "u", struct.pack("<I", reply_serial))
        fields += b"\0" * (-len(fields) % 8)
        if sig:
            fields += field(8, "g", bytes([len(sig)]) + sig.encode() + b"\0")
        head = struct.pack("<BBBBIII", ord("l"), 2, 1, 1, len(body), serial, len(fields))
        msg = head + fields
        msg += b"\0" * (-len(msg) % 8)
        return msg + body

    @staticmethod
    def read_message(conn):
        def take(n):
            data = b""
            while len(data) < n:
                data += conn.recv(n - len(data))
            return data
        head = take(16)
        blen, flen = struct.unpack("<II", head[4:8] + head[12:16])
        rest = take(-(16 + flen) % 8 + flen + blen)
        return minidbus.decode(head + rest)

    def serve(self):
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            threading.Thread(target=self.handle, args=(conn,), daemon=True).start()

    def handle(self, conn):
        def line():
            data = b""
            while not data.endswith(b"\r\n"):
                data += conn.recv(1)
            return data
        assert b"AUTH EXTERNAL" in line()
        conn.sendall(b"OK 0123\r\n")
        assert line() == b"BEGIN\r\n"
        for _ in range(2):
            message = self.read_message(conn)
            if message.member == "Hello":
                conn.sendall(self.reply(1, 1, "s", struct.pack("<I", 4) + b":1.1\0"))
            else:
                self.seen.append((message.interface, message.member, message.fields[minidbus.DESTINATION], list(message.body)))
                conn.sendall(self.reply(2, 2, "i", struct.pack("<i", self.reply_task)))
        conn.close()


@pytest.fixture
def session_bus(tmp_path, monkeypatch):
    path = str(tmp_path / "bus.sock")
    bus = FakeBus(path)
    monkeypatch.setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=" + path)
    yield bus
    bus.server.close()


def test_speak_sends_text_over_the_socket_never_argv(fake, session_bus, capsys):
    fake.set(present=True)
    reply = run("speechnote_speak", {"text": SECRET + " é中", "model": "en_kokoro_82m_af_alloy"}, capsys)
    assert reply == {"type": "speechnote_speaking", "task": 11}
    assert session_bus.seen == [("org.mkiol.Speech", "TtsPlaySpeech", "net.mkiol.Speech",
                                 [SECRET + " é中", "en_kokoro_82m_af_alloy"])]
    assert not any("diary" in c for c in fake.calls())  # nothing with the text reached busctl


def test_speak_refused_maps_not_configured(fake, session_bus, capsys):
    session_bus.reply_task = -1
    fake.set(present=True, State=[3, 1])
    assert run("speechnote_speak", {"text": "hi"}, capsys)["code"] == "not_configured"


def test_speak_without_session_bus_is_bus_error(fake, capsys, monkeypatch, tmp_path):
    monkeypatch.setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=" + str(tmp_path / "none"))
    fake.set(present=True)
    assert run("speechnote_speak", {"text": "hi"}, capsys)["code"] == "bus_error"


def test_speak_bus_override_never_reaches_the_session_bus(fake, session_bus, capsys, monkeypatch, tmp_path):
    # The docs media set it to nothing: the real service (here the session bus) is never called.
    monkeypatch.setenv("KDEAICHAT_SPEECHNOTE_BUS", "unix:path=" + str(tmp_path / "none"))
    fake.set(present=True)
    assert run("speechnote_speak", {"text": "hi"}, capsys)["code"] == "bus_error"
    assert session_bus.seen == []


def test_pause_resume_stop(fake, capsys):
    fake.set(present=True)
    assert run("speechnote_pause", {"task": 3}, capsys) == {"type": "speechnote_paused", "task": 3, "result": 0}
    assert run("speechnote_resume", {"task": 3}, capsys)["type"] == "speechnote_resumed"
    assert run("speechnote_stop", {"task": 3}, capsys)["type"] == "speechnote_stopped"
    assert fake.calls() == ["TtsPauseSpeech i 3", "TtsResumeSpeech i 3", "TtsStopSpeech i 3"]


def test_wait_spoken_returns_when_task_is_no_longer_current(fake, capsys):
    fake.set(present=True)  # CurrentTask is 7
    assert run("speechnote_wait_spoken", {"task": 8}, capsys) == {"type": "speechnote_spoken", "task": 8}


def test_wait_spoken_keeps_alive_then_times_out(fake, capsys):
    fake.set(present=True)
    assert run("speechnote_wait_spoken", {"task": 7, "timeout": 1}, capsys)["code"] == "timeout"
    assert "KeepAliveTask i 7" in fake.calls()


def test_wait_spoken_reports_the_sentence_being_read(fake, capsys):
    other = {"type": "signal", "interface": "org.mkiol.Speech", "member": "TtsPartialSpeechPlaying",
             "payload": {"type": "si", "data": ["Not ours.", 9]}}
    ours = {"type": "signal", "interface": "org.mkiol.Speech", "member": "TtsPartialSpeechPlaying",
            "payload": {"type": "si", "data": ["Hello there.", 7]}}
    fake.set(present=True, signals_after="KeepAliveService", signals=[other, ours])
    assert run("speechnote_wait_spoken", {"task": 7, "sentences": True}, capsys) == {
        "type": "speechnote_sentence", "task": 7, "text": "Hello there."}


def test_wait_spoken_without_a_watch_still_waits(fake, capsys, monkeypatch):
    fake.set(present=True)
    def broken():
        raise SpeechNoteError("bus_error", "no monitor")
    monkeypatch.setattr(speechnote_bus, "Monitor", broken)
    assert run("speechnote_wait_spoken", {"task": 8, "sentences": True}, capsys)["type"] == "speechnote_spoken"


def test_wait_spoken_service_gone_means_finished(fake, capsys):
    fake.set(present=False)
    assert run("speechnote_wait_spoken", {"task": 7}, capsys)["type"] == "speechnote_spoken"


# ---- through the helper's dispatcher ---------------------------------------------------------

def test_registered_in_the_helper(fake, tmp_path):
    fake.set(present=True)
    payload = base64.b64encode(b"{}").decode()
    env = dict(os.environ, PYTHONPATH=UI)
    done = subprocess.run([sys.executable, os.path.join(UI, "kde_ai_helper.py"), "speechnote_status", payload],
                          capture_output=True, text=True, env=env, timeout=30)
    assert json.loads(done.stdout)["type"] == "speechnote_status"
    assert json.loads(done.stdout)["running"] is True
