"""Importing ChatGPT and Claude exports as chats (kdeaichat/import_chats.py)."""
import json
import os
import sys
import zipfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui"))

from kdeaichat import chat_files, import_chats, qsettings_ini  # noqa: E402


def out(capsys):
    return json.loads(capsys.readouterr().out)


def node(node_id, parent, role=None, parts=None, children=(), time=None, **extra):
    message = None
    if role:
        message = {"author": {"role": role}, "content": {"content_type": "text", "parts": parts or []},
                   "create_time": time, "metadata": extra.pop("metadata", {}), "recipient": "all"}
        message.update(extra)
    return {"id": node_id, "message": message, "parent": parent, "children": list(children)}


def chatgpt_export():
    """One branched conversation (the user regenerated the first answer), one empty, one with an image."""
    branched = {
        "id": "conv-1", "title": "Pasta  recipe", "create_time": 1700000000.5, "update_time": 1700000100.0,
        "current_node": "a2",
        "mapping": {
            "root": node("root", None, children=["sys"]),
            "sys": node("sys", "root", "system", ["You are ChatGPT"], ["u1"]),
            "u1": node("u1", "sys", "user", ["How do I cook pasta?"], ["a1-old", "a1"], time=1700000001),
            "a1-old": node("a1-old", "u1", "assistant", ["OLD BRANCH ANSWER"], [], time=1700000002),
            "a1": node("a1", "u1", "assistant", ["Boil water, add pasta."], ["tool", "u2"], time=1700000003,
                       metadata={"model_slug": "gpt-4o"}),
            "tool": node("tool", "a1", "tool", ["search results"], []),
            "u2": node("u2", "a1", "user", ["And the sauce?"], ["hid"], time=1700000004),
            "hid": node("hid", "u2", "assistant", ["hidden"], ["a2"], metadata={"is_visually_hidden_from_conversation": True}),
            "a2": node("a2", "hid", "assistant", ["Tomatoes and basil."], [], time=1700000005),
        },
    }
    empty = {"id": "conv-2", "title": "Nothing", "create_time": 1700000200, "current_node": "s",
             "mapping": {"s": node("s", None, "system", ["x"])}}
    image = {"id": "conv-3", "title": "A picture", "create_time": 1700000300, "current_node": "a",
             "mapping": {"u": node("u", None, "user", [{"content_type": "image_asset_pointer", "asset_pointer": "file-service://file-abc"},
                                                       "What is this?"], ["a"], time=1700000301),
                         "a": node("a", "u", "assistant", ["A cat."], [], time=1700000302)}}
    return [branched, empty, image]


def claude_export():
    return [
        {"uuid": "c-1", "name": "Trip plan", "created_at": "2025-01-02T10:00:00.000000Z", "updated_at": "2025-01-02T10:05:00Z",
         "chat_messages": [
             {"uuid": "m1", "sender": "human", "text": "Plan a trip", "created_at": "2025-01-02T10:00:00Z",
              "attachments": [{"file_name": "map.pdf"}], "files": [{"file_name": "photo.png"}]},
             {"uuid": "m2", "sender": "assistant", "text": "", "created_at": "2025-01-02T10:01:00Z",
              "content": [{"type": "text", "text": "Where to?"}]},
             {"uuid": "m3", "sender": "system", "text": "ignored"},
         ]},
        {"uuid": "c-2", "name": "", "created_at": "2025-02-01T00:00:00Z", "chat_messages": []},
    ]


def as_zip(tmp_path, name, data, member="conversations.json"):
    path = tmp_path / name
    with zipfile.ZipFile(path, "w") as z:
        z.writestr(member, json.dumps(data))
        z.writestr("users.json", "[]")
    return str(path)


def messages(directory, chat_id):
    raw = qsettings_ini.read_value(os.path.join(directory, "chat-%s.ini" % chat_id), "messages")
    return json.loads(raw)


def test_inspect_both_formats(tmp_path, capsys):
    import_chats.COMMANDS["import_inspect"]({"path": as_zip(tmp_path, "g.zip", chatgpt_export())})
    assert out(capsys) == {"ok": True, "format": "chatgpt", "conversations": 2}
    import_chats.COMMANDS["import_inspect"]({"path": as_zip(tmp_path, "c.zip", claude_export())})
    assert out(capsys) == {"ok": True, "format": "claude", "conversations": 1}
    plain = tmp_path / "conversations.json"
    plain.write_text(json.dumps(claude_export()))
    import_chats.COMMANDS["import_inspect"]({"path": str(plain)})
    assert out(capsys)["format"] == "claude"


def test_chatgpt_follows_the_current_branch_and_skips_noise(chat_env, tmp_path, capsys):
    path = as_zip(tmp_path, "g.zip", chatgpt_export())
    import_chats.COMMANDS["import_run"]({"path": path, "directory": chat_env.dir})
    result = out(capsys)
    assert result == {"ok": True, "format": "chatgpt", "imported": 2, "existing": 0, "empty": 1}

    sessions = {s["value"]: s for s in chat_files.sessions(chat_env.dir)}
    assert set(sessions) == {"imp-chatgpt-conv-1", "imp-chatgpt-conv-3"}
    meta = sessions["imp-chatgpt-conv-1"]
    assert meta["text"] == "Pasta recipe" and meta["source"] == "provider" and meta["messageCount"] == 4
    assert meta["createdAt"] == 1700000000500 and meta["updatedAt"] == 1700000100000 and meta["archived"] is False

    chat = messages(chat_env.dir, "imp-chatgpt-conv-1")
    assert [(m["role"], m["content"]) for m in chat] == [
        ("user", "How do I cook pasta?"), ("assistant", "Boil water, add pasta."),
        ("user", "And the sauce?"), ("assistant", "Tomatoes and basil.")]
    assert chat[1]["model"] == "gpt-4o" and chat[0]["at"] == 1700000001000
    assert "OLD BRANCH" not in json.dumps(chat) and "search results" not in json.dumps(chat)

    picture = messages(chat_env.dir, "imp-chatgpt-conv-3")
    assert picture[0]["content"].startswith("[attachment not imported: image") and "What is this?" in picture[0]["content"]


def test_claude_import_text_attachments_and_dates(chat_env, tmp_path, capsys):
    import_chats.COMMANDS["import_run"]({"path": as_zip(tmp_path, "c.zip", claude_export()), "directory": chat_env.dir})
    assert out(capsys) == {"ok": True, "format": "claude", "imported": 1, "existing": 0, "empty": 1}
    meta = chat_files.sessions(chat_env.dir)[0]
    assert meta["value"] == "imp-claude-c-1" and meta["text"] == "Trip plan" and meta["messageCount"] == 2
    assert meta["createdAt"] == 1735812000000
    chat = messages(chat_env.dir, "imp-claude-c-1")
    assert chat[0]["role"] == "user" and chat[0]["content"] == "Plan a trip\n\n[attachment not imported: map.pdf]\n\n[attachment not imported: photo.png]"
    assert (chat[1]["role"], chat[1]["content"]) == ("assistant", "Where to?")


def test_importing_twice_adds_nothing_and_keeps_existing_chats(chat_env, tmp_path, capsys):
    chat_env.add_chat("s-mine", [{"id": "1", "role": "user", "content": "keep me", "at": 1}])
    for name, data in (("g.zip", chatgpt_export()), ("c.zip", claude_export())):
        path = as_zip(tmp_path, name, data)
        import_chats.COMMANDS["import_run"]({"path": path, "directory": chat_env.dir})
        first = out(capsys)
        import_chats.COMMANDS["import_run"]({"path": path, "directory": chat_env.dir})
        second = out(capsys)
        assert first["imported"] > 0 and second["imported"] == 0 and second["existing"] == first["imported"]
    ids = [s["value"] for s in chat_files.sessions(chat_env.dir)]
    assert len(ids) == len(set(ids)) == 4 and "s-mine" in ids
    assert messages(chat_env.dir, "s-mine")[0]["content"] == "keep me"


def test_a_plain_conversations_json_works(chat_env, tmp_path, capsys):
    plain = tmp_path / "conversations.json"
    plain.write_text(json.dumps(chatgpt_export()))
    import_chats.COMMANDS["import_run"]({"path": str(plain), "directory": chat_env.dir})
    assert out(capsys)["imported"] == 2


def test_imported_ids_are_safe_for_the_store(chat_env, tmp_path, capsys):
    data = claude_export()
    data[0]["uuid"] = "../../weird id/with:chars"
    import_chats.COMMANDS["import_run"]({"path": as_zip(tmp_path, "c.zip", data), "directory": chat_env.dir})
    assert out(capsys)["imported"] == 1
    chat_id = chat_files.sessions(chat_env.dir)[0]["value"]
    assert chat_files.valid_id(chat_id) and "/" not in chat_id and " " not in chat_id


def test_bad_files_are_reported_not_raised(chat_env, tmp_path, capsys):
    for name, content in (("a.json", "{nope"), ("b.json", "{}"), ("c.json", json.dumps([{"x": 1}]))):
        (tmp_path / name).write_text(content)
        import_chats.COMMANDS["import_inspect"]({"path": str(tmp_path / name)})
        assert out(capsys)["ok"] is False
    nozip = tmp_path / "n.zip"
    with zipfile.ZipFile(nozip, "w") as z:
        z.writestr("other.txt", "x")
    import_chats.COMMANDS["import_run"]({"path": str(nozip), "directory": chat_env.dir})
    assert out(capsys)["ok"] is False
    import_chats.COMMANDS["import_run"]({"path": str(tmp_path / "missing.zip"), "directory": chat_env.dir})
    assert out(capsys)["ok"] is False


def test_a_damaged_index_is_never_replaced(chat_env, tmp_path, capsys):
    chat_env.add_chat("s-1")
    with open(os.path.join(chat_env.dir, "index.ini"), "w") as f:
        f.write("[General]\nsessions=[{broken\n")
    import_chats.COMMANDS["import_run"]({"path": as_zip(tmp_path, "c.zip", claude_export()), "directory": chat_env.dir})
    assert out(capsys)["ok"] is False
    assert "broken" in open(os.path.join(chat_env.dir, "index.ini")).read()
