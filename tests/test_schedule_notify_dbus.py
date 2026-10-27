"""schedule_notify: the notification goes over D-Bus (a fake Notifications service on a private socket), never argv."""
import os
import socket
import struct
import sys
import threading

import pytest

UI = os.path.join(os.path.dirname(__file__), "..", "org.kde.plasma.kdeaichat", "contents", "ui")
sys.path.insert(0, UI)
from kdeaichat import minidbus, schedule_notify  # noqa: E402

REPLY = "secret diary <b>text</b> & more"


class FakeNotifications:
    def __init__(self, path):
        self.server = socket.socket(socket.AF_UNIX)
        self.server.bind(path)
        self.server.listen(2)
        self.seen = []
        threading.Thread(target=self.serve, daemon=True).start()

    @staticmethod
    def reply(serial, reply_serial, sig, body):
        fields = b""

        def field(code, t, data):
            nonlocal fields
            fields += b"\0" * (-len(fields) % 8)
            fields += bytes([code, 1, ord(t), 0]) + data
        field(5, "u", struct.pack("<I", reply_serial))
        fields += b"\0" * (-len(fields) % 8)
        if sig:
            field(8, "g", bytes([len(sig)]) + sig.encode() + b"\0")
        msg = struct.pack("<BBBBIII", ord("l"), 2, 1, 1, len(body), serial, len(fields)) + fields
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
        return minidbus.decode(head + take(-(16 + flen) % 8 + flen + blen))

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
        line()
        conn.sendall(b"OK 0123\r\n")
        line()
        for _ in range(2):
            message = self.read_message(conn)
            if message.member == "Hello":
                conn.sendall(self.reply(1, 1, "s", struct.pack("<I", 4) + b":1.1\0"))
            else:
                self.seen.append((message.fields[minidbus.DESTINATION], message.member, list(message.body)))
                conn.sendall(self.reply(2, 2, "u", struct.pack("<I", 7)))
        conn.close()


def _fake_notify_send(tmp_path, monkeypatch):
    log = tmp_path / "notify-send.log"
    tool = tmp_path / "notify-send"
    tool.write_text('#!/bin/sh\necho "$@" >> "%s"\n' % log)
    tool.chmod(0o755)
    monkeypatch.setenv("KDEAICHAT_NOTIFY_SEND", str(tool))
    return log


def test_sent_over_dbus_with_markup_escaped(tmp_path, monkeypatch):
    path = str(tmp_path / "bus.sock")
    bus = FakeNotifications(path)
    monkeypatch.setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=" + path)
    log = _fake_notify_send(tmp_path, monkeypatch)
    try:
        assert schedule_notify.send("Daily is ready", REPLY, fallback_body="A new reply is ready")
    finally:
        bus.server.close()
    (dest, member, body), = bus.seen
    assert (dest, member) == ("org.freedesktop.Notifications", "Notify")
    assert body[0] == "KDE AI Chat" and body[3] == "Daily is ready"
    assert body[4] == "secret diary &lt;b&gt;text&lt;/b&gt; &amp; more"
    assert body[5] == [] and body[7] == -1
    assert not log.exists()  # notify-send never ran, so no reply text on any command line


def test_fallback_argv_has_no_reply_text(tmp_path, monkeypatch):
    monkeypatch.setenv("DBUS_SESSION_BUS_ADDRESS", "unix:path=" + str(tmp_path / "none"))
    log = _fake_notify_send(tmp_path, monkeypatch)
    assert schedule_notify.send("Daily is ready", REPLY, fallback_body="A new reply is ready")
    text = log.read_text()
    assert "Daily is ready" in text and "A new reply is ready" in text and "diary" not in text
