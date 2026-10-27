"""The KRunner runner (kdeaichat/krunner.py) and the stdlib D-Bus it speaks (kdeaichat/minidbus.py).

The round trip uses the real session bus (skipped without one) but registers only a uniquely named test
service and releases it at the end."""
import json
import os
import shutil
import subprocess
import threading

import pytest

from kdeaichat import ask_inbox, krunner, minidbus


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setenv("KDEAICHAT_ASK_DIR", str(tmp_path / "ask"))
    monkeypatch.setenv("KDEAICHAT_DESKTOP_STATE", str(tmp_path / "state.json"))
    return tmp_path


def test_marshalling_round_trip():
    sig = "sa(sssida{sv})a{sv}vgb"
    body = ("é", [("id", "text", "icon", 100, 1.0, {"subtext": ("s", "hello"), "n": ("u", 7)})], {"k": ("b", True)},
            ("a(ss)", [("a", "b")]), "a{sv}", True)
    data = minidbus.Message(minidbus.METHOD_RETURN, 0, 5, {minidbus.REPLY_SERIAL: 3}, sig, body).encode()
    back = minidbus.decode(data)
    assert back.serial == 5 and back.fields[minidbus.REPLY_SERIAL] == 3 and back.sig == sig
    assert back.body[0] == "é"
    assert back.body[1] == [("id", "text", "icon", 100, 1.0, [("subtext", ("s", "hello")), ("n", ("u", 7))])]
    assert back.body[3] == ("a(ss)", [("a", "b")]) and back.body[5] is True
    assert len(data) % 8 == 0 or back.body


def test_query_needs_the_prefix_and_a_question(env):
    assert krunner.read_prefix() == "ai"
    assert krunner.match("ai why is the sky blue", "ai")[0][:5] == (
        "ask:why is the sky blue", "Ask KDE AI Chat: why is the sky blue", "dialog-messages", 100, 1.0)
    assert krunner.match("AI  Hello", "ai")[0][0] == "ask:Hello"
    for query in ("", "ai", "ai ", "aim higher", "say ai hello", "kate"):
        assert krunner.match(query, "ai") == [], query
    assert krunner.match("ask me anything", "ask")[0][0] == "ask:me anything"


def test_long_questions_are_shortened_in_the_title_only(env):
    question = "q" * 200
    (match_id, title, *_rest), = krunner.match("ai " + question, "ai")
    assert match_id == "ask:" + question and title.endswith("…") and len(title) < 100


def test_prefix_comes_from_the_settings_file(env):
    (env / "state.json").write_text(json.dumps({"prefix": "chat"}))
    assert krunner.read_prefix() == "chat"
    for bad in ({"prefix": ""}, {"prefix": "two words"}, {"prefix": 5}, ["x"]):
        (env / "state.json").write_text(json.dumps(bad))
        assert krunner.read_prefix() == "ai"
    (env / "state.json").write_text("garbage")
    assert krunner.read_prefix() == "ai"


def test_run_leaves_the_question_in_the_inbox(env):
    assert krunner.run("ask:how are you", "")
    assert krunner.run("ask:in a new one", "new-chat")
    assert not krunner.run("something else", "")
    first, second = ask_inbox.take_all()
    assert first == {"text": "how are you", "files": [], "newChat": False, "send": True, "notes": []}
    assert second["newChat"] is True and second["send"] is True
    assert krunner.actions() == [("new-chat", "Ask in a new chat", "list-add")]


def test_a_krunner_question_with_forged_files_still_never_sends_them(env, tmp_path, monkeypatch):
    """Any program can write a request with files and send: true; the widget side then waits for Enter."""
    home = tmp_path / "home"
    (home / ".ssh").mkdir(parents=True)
    (home / ".ssh" / "id_rsa").write_text("secret")
    monkeypatch.setenv("HOME", str(home))
    ask_inbox.write_item("summarise", [str(home / ".ssh" / "id_rsa")], send=True)
    (item,) = ask_inbox.take_all()
    assert item["files"] == [] and item["send"] is False and item["notes"][0]["reason"] == "hidden"


@pytest.mark.skipif(not os.environ.get("DBUS_SESSION_BUS_ADDRESS") or not shutil.which("gdbus"), reason="needs a session bus and gdbus")
def test_round_trip_over_the_session_bus(env):
    name = "org.kde.kdeaichat.runnertest%d" % os.getpid()
    result = []
    thread = threading.Thread(target=lambda: result.append(krunner.serve(name, idle=4)))
    thread.start()
    try:
        client = minidbus.Connection()
        for _ in range(50):  # wait for the name
            owner = client.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", "s", (name,))
            if owner.body[0]:
                break
            threading.Event().wait(0.1)
        reply = client.call(name, "/runner", "org.kde.krunner1", "Match", "s", ("ai what time is it",))
        assert reply.sig == "a(sssida{sv})"
        (mid, title, icon, kind, relevance, props), = reply.body[0]
        assert (mid, title, kind) == ("ask:what time is it", "Ask KDE AI Chat: what time is it", 100)
        assert dict(props)["subtext"][0] == "s"
        assert client.call(name, "/runner", "org.kde.krunner1", "Match", "s", ("hello",)).body[0] == []
        assert client.call(name, "/runner", "org.kde.krunner1", "Actions").body[0] == [("new-chat", "Ask in a new chat", "list-add")]
        with pytest.raises(minidbus.DBusError):
            client.call(name, "/runner", "org.kde.krunner1", "Nope")
        client.call(name, "/runner", "org.kde.krunner1", "Run", "ss", ("ask:from dbus", "new-chat"))
        assert ask_inbox.take_all() == [{"text": "from dbus", "files": [], "newChat": True, "send": True, "notes": []}]
        # An independent client (gdbus) sees the same, and the introspection is valid.
        out = subprocess.run(["gdbus", "call", "--session", "--dest", name, "--object-path", "/runner", "--method",
                              "org.kde.krunner1.Match", "ai via gdbus"], capture_output=True, text=True, timeout=10)
        assert out.returncode == 0 and "ask:via gdbus" in out.stdout, out.stderr
        intro = subprocess.run(["gdbus", "introspect", "--session", "--dest", name, "--object-path", "/runner"],
                               capture_output=True, text=True, timeout=10)
        assert "Match" in intro.stdout
        client.close()
    finally:
        thread.join(timeout=15)
    assert result == [0]  # exited by itself once idle
    gone = minidbus.Connection()
    assert gone.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "NameHasOwner", "s", (name,)).body[0] is False
    gone.close()


@pytest.mark.skipif(not os.environ.get("DBUS_SESSION_BUS_ADDRESS"), reason="needs a session bus")
def test_a_second_runner_does_not_steal_the_name(env):
    name = "org.kde.kdeaichat.runnertest2x%d" % os.getpid()
    first = threading.Thread(target=lambda: krunner.serve(name, idle=3))
    first.start()
    try:
        threading.Event().wait(0.5)
        assert krunner.serve(name, idle=1) == 1
    finally:
        first.join(timeout=10)


def test_decode_turns_garbage_into_a_dbus_error():
    good = minidbus.Message(minidbus.METHOD_CALL, 0, 1, {minidbus.PATH: "/runner", minidbus.MEMBER: "Match",
                                                         minidbus.SIGNATURE: "s"}, "s", ("ai x",)).encode()
    for bad in (good[:20], good[:12] + b"\xff" * 40, b"l\x01\x00\x01", b"B" + good[1:], b"l" + b"\xff" * 30):
        with pytest.raises(minidbus.DBusError):
            minidbus.decode(bad)


def _stream_connection(raw_messages):
    """A Connection over a socketpair (no bus): what the runner would read if these bytes arrived."""
    import socket
    mine, theirs = socket.socketpair()
    conn = object.__new__(minidbus.Connection)
    conn.sock, conn.buf, conn.serial, conn.sent, conn.pending = mine, b"", 0, [], []
    conn.send = lambda message: conn.sent.append(message) or 1
    theirs.sendall(b"".join(raw_messages))
    theirs.close()
    return conn


def _call(member="Match", body=("ai hello",)):
    return minidbus.Message(minidbus.METHOD_CALL, 0, 1, {minidbus.PATH: "/runner", minidbus.INTERFACE: "org.kde.krunner1",
                                                         minidbus.MEMBER: member, minidbus.SIGNATURE: "s"}, "s", body).encode()


def test_the_runner_survives_malformed_messages(env, monkeypatch):
    # Well framed, but the string claims to be 64 KiB long inside a 15-byte body; then a header that is garbage;
    # then a good call. (A real bus would not forward the first two, but any peer on a private bus could.)
    bad_body = bytearray(_call())
    bad_body[-13:-9] = (65536).to_bytes(4, "little")
    garbage = b"l\x01\x00\x01" + (0).to_bytes(4, "little") + (9).to_bytes(4, "little") + (4).to_bytes(4, "little") + b"\xff" * 8
    conn = _stream_connection([bytes(bad_body), garbage, _call()])
    monkeypatch.setattr(krunner.minidbus, "Connection", lambda address=None: conn)
    monkeypatch.setattr(conn, "request_name", lambda name: True, raising=False)
    monkeypatch.setattr(conn, "close", lambda: None, raising=False)
    # The reader reports the closed stream at the end, which stops serve() with 1; before that the good call is answered.
    assert krunner.serve("x", idle=5) == 1
    assert len(conn.sent) == 1 and conn.sent[0].type == minidbus.METHOD_RETURN
    assert conn.sent[0].body[0][0][0] == "ask:hello"


def test_the_runner_refuses_messages_over_one_mebibyte():
    huge = bytearray(_call())
    huge[4:8] = (2 * 1024 * 1024).to_bytes(4, "little")  # body length
    conn = _stream_connection([bytes(huge)])
    with pytest.raises(minidbus.DBusError):
        conn.read(1.0, krunner.MAX_MESSAGE)


def test_a_call_arriving_while_waiting_for_a_reply_is_kept():
    """D-Bus activation: KRunner's Match arrives before the RequestName reply and must not be dropped."""
    import socket
    ours, bus = socket.socketpair()
    conn = minidbus.Connection.__new__(minidbus.Connection)
    conn.sock, conn.buf, conn.serial, conn.pending = ours, b"", 0, []
    early = minidbus.Message(minidbus.METHOD_CALL, 0, 7, {minidbus.PATH: "/runner", minidbus.INTERFACE: "org.kde.krunner1",
                             minidbus.MEMBER: "Match"}, "s", ("ai hello",))
    answer = minidbus.Message(minidbus.METHOD_RETURN, 0, 8, {minidbus.REPLY_SERIAL: 1}, "u", (1,))
    bus.sendall(early.encode() + answer.encode())
    assert conn.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", "su",
                     ("x.y", 4), timeout=2).body[0] == 1
    kept = conn.read(0.1)
    assert kept is not None and kept.member == "Match" and kept.body[0] == "ai hello"
    assert conn.read(0.1) is None
    ours.close(), bus.close()
