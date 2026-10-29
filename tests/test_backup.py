"""Backup, inspect and restore (kdeaichat/backup.py). Everything runs in temp folders; the real data is never touched."""
import json
import os
import stat
import sys
import zipfile

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui"))

from kdeaichat import backup, backup_zip, chat_files, memory, schedule_store  # noqa: E402

SECRET_SETTINGS = {
    "apiKey": "sk-abc123secret", "anthropicApiKey": "sk-ant-zzz", "openRouterApiKey": "or-xyz",
    "someToken": "tok", "clientSecret": "s3cret", "passwordHint": "hunter2",
    "innocentLooking": "sk-live-1234567890", "authHeader": "Bearer abc",
    "chatSessionsJson": "[{\"value\":\"old\"}]", "walletKeysRevision": 4,
}
PLAIN_SETTINGS = {"provider": "openrouter", "model": "auto", "fontSize": 12, "streaming": True, "sendKey": "enter"}


def out(capsys):
    return json.loads(capsys.readouterr().out)


def applet_dir(root, applet="7"):
    return os.path.join(root, "kdeaichat", "chats", "applet-" + applet)


def msgs(text):
    return [{"id": "1", "role": "user", "content": text, "at": 1, "time": "10:00"}]


def seed(chat_env, capsys):
    """Two chats (one with an attachment and a picture), a project, memories, a schedule, MCP, approvals."""
    chat_env.add_chat("s-1", msgs("hello one"))
    chat_env.add_chat("s-2:x", msgs("hello two"), projectId="p-1")
    d = chat_env.dir
    for sub, name in (("attachments/s-1", "a" * 64 + ".txt"), ("images/s-1", "m1-0.png")):
        os.makedirs(os.path.join(d, sub), exist_ok=True)
        with open(os.path.join(d, sub, name), "wb") as f:
            f.write(b"bytes-" + name.encode())
    chat_env.ini.write_values(os.path.join(d, "projects.ini"),
                              {"version": "1", "projects": json.dumps([{"id": "p-1", "name": "Proj"}])})
    memory.COMMANDS["memory_add"]({"items": [{"text": "I use Fedora", "scope": "all"}, {"text": "Call me Ana", "scope": "all"}]})
    capsys.readouterr()
    data = chat_env.sched.data
    with open(os.path.join(data, "schedules.v2.json"), "w") as f:
        json.dump({"version": 2, "settings": {"historyLimit": 20}, "schedules": [{
            "id": "sch-1", "name": "Daily", "enabled": True, "chatId": "s-1", "message": "ping",
            "rules": [{"kind": "daily", "times": ["09:00"], "everyDays": 1}]}]}, f)
    with open(os.path.join(data, "mcp.json"), "w") as f:
        json.dump({"mcpServers": {"files": {"command": "npx", "args": ["x"], "enabled": True,
                                            "env": {"API_TOKEN": "plain-leaked-value", "MODE": "ro"}},
                                  "web": {"url": "https://example.com/mcp", "headers": {"Authorization": "Bearer leaked"}}}}, f)
    with open(os.path.join(data, "tool-approvals.json"), "w") as f:
        json.dump({"version": 1, "keys": ["mcp:files:read"]}, f)


def make_backup(chat_env, capsys, tmp_path, settings=None):
    dest = str(tmp_path / "out" / "b.zip")
    backup.COMMANDS["backup_create"]({"directory": chat_env.dir, "dest": dest, "widgetVersion": "1.5.0",
                                      "settings": settings if settings is not None else dict(PLAIN_SETTINGS, **SECRET_SETTINGS)})
    result = out(capsys)
    assert result["ok"], result
    return dest, result


def switch_to_empty_store(monkeypatch, tmp_path):
    root = str(tmp_path / "other")
    monkeypatch.setenv("XDG_DATA_HOME", root)
    return root


def test_backup_layout_and_private_mode(chat_env, capsys, tmp_path):
    seed(chat_env, capsys)
    dest, result = make_backup(chat_env, capsys, tmp_path)
    assert stat.S_IMODE(os.stat(dest).st_mode) == 0o600
    with zipfile.ZipFile(dest) as z:
        names = set(z.namelist())
    assert {"manifest.json", "settings.json", "memory.json", "schedules.v2.json", "mcp.json", "tool-approvals.json",
            "chats/index.ini", "chats/projects.ini", "chats/chat-s-1.ini", "chats/chat-s-2:x.ini",
            "chats/attachments/s-1/" + "a" * 64 + ".txt", "chats/images/s-1/m1-0.png"} <= names
    assert not any(n.startswith("chats/inbox") or n.endswith(".bak") for n in names)
    contents = result["contents"]
    assert contents["chats"] == 2 and contents["memories"] == 2 and contents["schedules"] == 1 and contents["mcpServers"] == 2
    with zipfile.ZipFile(dest) as z:
        manifest = json.loads(z.read("manifest.json"))
    assert manifest["format"] == 1 and manifest["widgetVersion"] == "1.5.0" and manifest["created"]


def test_no_secret_reaches_the_backup(chat_env, capsys, tmp_path):
    seed(chat_env, capsys)
    dest, result = make_backup(chat_env, capsys, tmp_path)
    with zipfile.ZipFile(dest) as z:
        blob = b"".join(z.read(n) for n in z.namelist() if not n.startswith("chats/"))
        settings = json.loads(z.read("settings.json"))
        mcp = json.loads(z.read("mcp.json"))
    for secret in ("sk-abc123secret", "sk-ant-zzz", "or-xyz", "s3cret", "hunter2", "sk-live-1234567890",
                   "plain-leaked-value", "Bearer leaked", "Bearer abc"):
        assert secret.encode() not in blob, secret
    assert settings == PLAIN_SETTINGS
    assert mcp["mcpServers"]["files"]["env"] == {"API_TOKEN": {"secret": "API_TOKEN"}, "MODE": "ro"}
    assert mcp["mcpServers"]["web"]["headers"] == {"Authorization": {"secret": "Authorization"}}
    assert result["contents"]["settingsLeftOut"] == len(SECRET_SETTINGS)


def test_every_historic_key_setting_is_excluded():
    from kdeaichat import privacy
    clean, _ = backup_zip.filter_settings({name: "value" for name in privacy.LEGACY_KEY_PROVIDERS})
    assert clean == {}


def test_provider_lists_lose_their_headers_and_keys():
    providers = json.dumps([{"id": "x", "baseUrl": "https://h", "headers": {"Authorization": "Bearer zzz"}, "apiKey": "k1"}])
    clean, _ = backup_zip.filter_settings({"providersJson": providers, "customProvidersJson": "not json"})
    assert json.loads(clean["providersJson"]) == [{"id": "x", "baseUrl": "https://h"}]
    assert "customProvidersJson" not in clean


def test_round_trip_into_an_empty_store(chat_env, capsys, tmp_path, monkeypatch):
    seed(chat_env, capsys)
    dest, _ = make_backup(chat_env, capsys, tmp_path)
    root = switch_to_empty_store(monkeypatch, tmp_path)
    directory = applet_dir(root)

    backup.COMMANDS["backup_inspect"]({"path": dest})
    info = out(capsys)
    assert info["ok"] and info["counts"] == {"chats": 2, "memories": 2, "schedules": 1, "mcpServers": 2}

    backup.COMMANDS["backup_restore"]({"path": dest, "directory": directory, "mode": "merge", "withSettings": True})
    result = out(capsys)
    assert result["ok"] and result["chatsAdded"] == 2 and result["chatsSkipped"] == 0
    assert result["memoriesAdded"] == 2 and result["schedulesAdded"] == 1 and result["mcpAdded"] == 2
    assert result["projectsAdded"] == 1
    assert result["settings"] == PLAIN_SETTINGS

    ids = {s["value"] for s in chat_files.sessions(directory)}
    assert ids == {"s-1", "s-2:x"}
    for chat_id, text in (("s-1", "hello one"), ("s-2:x", "hello two")):
        raw = chat_env.ini.read_value(os.path.join(directory, "chat-%s.ini" % chat_id), "messages")
        assert json.loads(raw)[0]["content"] == text
    assert open(os.path.join(directory, "attachments", "s-1", "a" * 64 + ".txt"), "rb").read().startswith(b"bytes-")
    assert os.path.isfile(os.path.join(directory, "images", "s-1", "m1-0.png"))
    assert os.path.isfile(os.path.join(directory, "index.ini.bak"))
    assert stat.S_IMODE(os.stat(os.path.join(directory, "chat-s-1.ini")).st_mode) == 0o600
    assert [m["text"] for m in memory.load()] == ["I use Fedora", "Call me Ana"]
    assert set(json.load(open(os.path.join(root, "kdeaichat", "mcp.json")))["mcpServers"]) == {"files", "web"}


def test_settings_are_returned_only_when_asked(chat_env, capsys, tmp_path, monkeypatch):
    seed(chat_env, capsys)
    dest, _ = make_backup(chat_env, capsys, tmp_path)
    root = switch_to_empty_store(monkeypatch, tmp_path)
    backup.COMMANDS["backup_restore"]({"path": dest, "directory": applet_dir(root), "mode": "merge"})
    assert "settings" not in out(capsys)


def test_merge_never_overwrites_and_counts_skipped(chat_env, capsys, tmp_path, monkeypatch):
    seed(chat_env, capsys)
    dest, _ = make_backup(chat_env, capsys, tmp_path)
    root = switch_to_empty_store(monkeypatch, tmp_path)
    directory = applet_dir(root)
    # The target already has s-1 with different text, the memory "I use Fedora" and the MCP server "files".
    os.makedirs(directory)
    chat_files.write_messages(directory, "s-1", msgs("MINE"))
    chat_files.add_to_index(directory, [{"value": "s-1", "text": "mine", "source": "provider", "createdAt": 5, "updatedAt": 5}])
    memory.COMMANDS["memory_add"]({"items": [{"text": "i use  fedora", "scope": "all"}]})
    capsys.readouterr()
    os.makedirs(os.path.join(root, "kdeaichat"), exist_ok=True)
    json.dump({"mcpServers": {"files": {"command": "mine", "args": [], "env": {}, "enabled": True}}},
              open(os.path.join(root, "kdeaichat", "mcp.json"), "w"))

    backup.COMMANDS["backup_restore"]({"path": dest, "directory": directory, "mode": "merge"})
    result = out(capsys)
    assert result["chatsAdded"] == 1 and result["chatsSkipped"] == 1
    assert result["memoriesAdded"] == 1 and result["memoriesSkipped"] == 1
    assert result["mcpAdded"] == 1 and result["mcpSkipped"] == 1
    raw = chat_env.ini.read_value(os.path.join(directory, "chat-s-1.ini"), "messages")
    assert json.loads(raw)[0]["content"] == "MINE"
    assert {s["value"]: s["text"] for s in chat_files.sessions(directory)}["s-1"] == "mine"
    assert json.load(open(os.path.join(root, "kdeaichat", "mcp.json")))["mcpServers"]["files"]["command"] == "mine"
    # A second restore adds nothing.
    backup.COMMANDS["backup_restore"]({"path": dest, "directory": directory, "mode": "merge"})
    again = out(capsys)
    assert again["chatsAdded"] == 0 and again["chatsSkipped"] == 2 and again["memoriesAdded"] == 0 and again["schedulesAdded"] == 0


def test_restored_schedules_come_back_disabled(chat_env, capsys, tmp_path, monkeypatch):
    seed(chat_env, capsys)
    dest, _ = make_backup(chat_env, capsys, tmp_path)
    root = switch_to_empty_store(monkeypatch, tmp_path)
    backup.COMMANDS["backup_restore"]({"path": dest, "directory": applet_dir(root), "mode": "merge"})
    assert out(capsys)["schedulesAdded"] == 1
    store = schedule_store.read_store()
    assert [(s["id"], s["enabled"]) for s in store["schedules"]] == [("sch-1", False)]
    # The one that already exists is not touched.
    backup.COMMANDS["backup_restore"]({"path": dest, "directory": applet_dir(root), "mode": "merge"})
    assert out(capsys)["schedulesSkipped"] == 1


def zip_with(path, members, manifest=True):
    with zipfile.ZipFile(path, "w") as z:
        if manifest:
            z.writestr("manifest.json", json.dumps({"format": 1, "app": "kdeaichat", "contents": {}}))
        for name, data in members.items():
            z.writestr(name, data)
    return str(path)


@pytest.mark.parametrize("name", ["../evil.ini", "/etc/passwd", "chats/../../x", "chats\\..\\x", "a/./b", "C:/x"])
def test_unsafe_member_names_refuse_the_whole_backup(tmp_path, capsys, monkeypatch, name):
    root = switch_to_empty_store(monkeypatch, tmp_path)
    path = zip_with(tmp_path / "bad.zip", {name: "x"})
    backup.COMMANDS["backup_restore"]({"path": path, "directory": applet_dir(root), "mode": "merge"})
    result = out(capsys)
    assert result["ok"] is False and "unsafe" in result["error"]
    assert not os.path.exists(os.path.join(tmp_path, "evil.ini"))
    backup.COMMANDS["backup_inspect"]({"path": path})
    assert out(capsys)["ok"] is False


def test_symlink_member_is_refused(tmp_path, capsys, monkeypatch):
    root = switch_to_empty_store(monkeypatch, tmp_path)
    path = str(tmp_path / "link.zip")
    with zipfile.ZipFile(path, "w") as z:
        info = zipfile.ZipInfo("chats/chat-a.ini")
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        z.writestr(info, "/etc/passwd")
    backup.COMMANDS["backup_restore"]({"path": path, "directory": applet_dir(root), "mode": "merge"})
    assert out(capsys)["ok"] is False


def test_oversized_members_and_totals_are_refused(tmp_path, capsys, monkeypatch):
    root = switch_to_empty_store(monkeypatch, tmp_path)
    monkeypatch.setattr(backup_zip, "MAX_MEMBER", 1000)
    path = zip_with(tmp_path / "big.zip", {"memory.json": "x" * 1001})
    backup.COMMANDS["backup_restore"]({"path": path, "directory": applet_dir(root), "mode": "merge"})
    result = out(capsys)
    assert result["ok"] is False and "200 MB" in result["error"]
    monkeypatch.setattr(backup_zip, "MAX_MEMBER", 10 ** 6)
    monkeypatch.setattr(backup_zip, "MAX_TOTAL", 1500)
    path = zip_with(tmp_path / "total.zip", {"memory.json": "x" * 900, "mcp.json": "y" * 900})
    backup.COMMANDS["backup_restore"]({"path": path, "directory": applet_dir(root), "mode": "merge"})
    assert "2 GB" in out(capsys)["error"]


def test_the_real_limits_are_200mb_and_2gb():
    assert backup_zip.MAX_MEMBER == 200 * 1024 * 1024 and backup_zip.MAX_TOTAL == 2 * 1024 ** 3


def test_damaged_json_and_missing_manifest_are_refused(tmp_path, capsys, monkeypatch):
    root = switch_to_empty_store(monkeypatch, tmp_path)
    bad = zip_with(tmp_path / "bad-json.zip", {"memory.json": "{not json"})
    backup.COMMANDS["backup_restore"]({"path": bad, "directory": applet_dir(root), "mode": "merge"})
    assert out(capsys)["ok"] is False
    none = zip_with(tmp_path / "no-manifest.zip", {"memory.json": "{}"}, manifest=False)
    backup.COMMANDS["backup_inspect"]({"path": none})
    assert out(capsys)["ok"] is False
    notzip = tmp_path / "x.zip"
    notzip.write_text("hello")
    backup.COMMANDS["backup_inspect"]({"path": str(notzip)})
    assert out(capsys)["ok"] is False


def test_chat_ids_must_match_the_store_pattern(tmp_path, capsys, monkeypatch):
    root = switch_to_empty_store(monkeypatch, tmp_path)
    directory = applet_dir(root)
    index = tmp_path / "index.ini"
    metas = [{"value": "../../x", "text": "bad"}, {"value": "s-incognito-1", "text": "inc"},
             {"value": "ok-1", "text": "fine"}]
    from kdeaichat import qsettings_ini
    qsettings_ini.write_values(str(index), {"version": "1", "sessions": json.dumps(metas)})
    chat = tmp_path / "chat.ini"
    qsettings_ini.write_values(str(chat), {"messages": "[]"})
    path = zip_with(tmp_path / "ids.zip", {"chats/index.ini": index.read_text(), "chats/chat-ok-1.ini": chat.read_text(),
                                           "chats/chat-s-incognito-1.ini": chat.read_text()})
    backup.COMMANDS["backup_restore"]({"path": path, "directory": directory, "mode": "merge"})
    result = out(capsys)
    assert result["chatsAdded"] == 1
    assert [s["value"] for s in chat_files.sessions(directory)] == ["ok-1"]
    assert sorted(n for n in os.listdir(directory) if n.startswith("chat-")) == ["chat-ok-1.ini"]


def test_a_damaged_chat_file_is_skipped_not_fatal(tmp_path, capsys, monkeypatch):
    root = switch_to_empty_store(monkeypatch, tmp_path)
    directory = applet_dir(root)
    from kdeaichat import qsettings_ini
    index = tmp_path / "index.ini"
    qsettings_ini.write_values(str(index), {"version": "1", "sessions": json.dumps([{"value": "a"}, {"value": "b"}])})
    good, bad = tmp_path / "g.ini", tmp_path / "b.ini"
    qsettings_ini.write_values(str(good), {"messages": "[]"})
    bad.write_text("[General]\nmessages=[{\"role\"\n")
    path = zip_with(tmp_path / "d.zip", {"chats/index.ini": index.read_text(), "chats/chat-a.ini": good.read_text(),
                                         "chats/chat-b.ini": bad.read_text()})
    backup.COMMANDS["backup_restore"]({"path": path, "directory": directory, "mode": "merge"})
    result = out(capsys)
    assert result["chatsAdded"] == 1 and result["chatsDamaged"] == 1
    assert not os.path.exists(os.path.join(directory, "chat-b.ini"))
    assert not [n for n in os.listdir(directory) if n.endswith(".tmp")]


def test_the_chat_folder_must_be_an_applet_folder(chat_env, capsys, tmp_path):
    backup.COMMANDS["backup_create"]({"directory": str(tmp_path), "dest": str(tmp_path / "b.zip")})
    assert out(capsys)["ok"] is False


def test_restore_refuses_another_mode(chat_env, capsys, tmp_path):
    dest, _ = make_backup(chat_env, capsys, tmp_path)
    backup.COMMANDS["backup_restore"]({"path": dest, "directory": chat_env.dir, "mode": "replace"})
    assert out(capsys)["ok"] is False
