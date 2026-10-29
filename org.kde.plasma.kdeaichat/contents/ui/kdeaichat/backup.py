"""Back up and restore the widget's data as one .zip (chats, memories, schedules, MCP servers, settings).

Commands (payload is JSON; every command prints one JSON object, ``ok: false`` + ``error`` for a problem
the user can fix):
  backup_create  {directory, dest, settings?, widgetVersion?}   -> {ok, path, bytes, contents}
  backup_inspect {path}                                         -> {ok, manifest, counts, hasSettings}
  backup_restore {path, directory, mode: "merge", withSettings?} -> {ok, ...counts, settings?}

``directory`` is the widget's chat folder (chats/applet-<id>); ``settings`` the non-secret settings the
widget passes from its config (filtered again here, backup_zip.filter_settings).

Zip layout (members are plain relative names, mode 0600 file):
  manifest.json            {format: 1, app, widgetVersion, created, contents: {...counts}}
  settings.json            non-secret widget settings {name: value}
  memory.json              the memory store, as is
  schedules.v2.json        schedule definitions (run state is not kept)
  mcp.json                 MCP servers; a plain secret-looking value becomes a {"secret": NAME} placeholder
  tool-approvals.json      remembered "always allow" tool keys (kept in the backup; restore does not apply them)
  chats/index.ini, chats/projects.ini, chats/chat-<id>.ini, chats/attachments/<chat>/*, chats/images/<chat>/*

No secret ever goes in: API keys live only in KWallet, and the settings and MCP files are cleaned.

Restore only adds. A chat whose id exists is skipped (never overwritten); memories already present (same
text and scope) are skipped; schedules are added switched off (the user turns them on; a restore must
never start something by itself); MCP servers are added by id without replacing one; projects by id.
"""
import datetime as dt
import json
import os
import tempfile
import zipfile
from typing import Any, Dict, List, Optional

from kdeaichat import (backup_zip as bz, chat_files, chats, common, mcp_config, memory, qsettings_ini,
                       schedule_chat, schedule_model, schedule_store, tool_approvals)
from kdeaichat.common import safe_path

FORMAT = 1


def _out(data: Dict[str, Any]) -> None:
    print(json.dumps(data, ensure_ascii=False))


def _json_file(path: str) -> Optional[Any]:
    try:
        if os.path.getsize(path) > bz.MAX_JSON:
            return None
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def _mcp_without_secrets(data: Any) -> tuple:
    """mcp.json with every plain value under a secret-like name replaced by {"secret": NAME}."""
    servers = data.get("mcpServers") if isinstance(data, dict) else None
    if not isinstance(servers, dict):
        return None, 0
    redacted = 0
    for server in servers.values():
        for field in ("env", "headers"):
            pairs = server.get(field) if isinstance(server, dict) else None
            for name, value in (pairs.items() if isinstance(pairs, dict) else []):
                if isinstance(value, str) and value and bz.secret_name(name):
                    pairs[name] = {"secret": name if mcp_config.SECRET_NAME.match(name) else "SECRET"}
                    redacted += 1
    return {"mcpServers": servers}, redacted


def _add_bytes(z: zipfile.ZipFile, name: str, data: bytes) -> None:
    info = zipfile.ZipInfo(name, dt.datetime.now().timetuple()[:6])
    info.external_attr = 0o600 << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    z.writestr(info, data)


def _add_file(z: zipfile.ZipFile, name: str, path: str) -> None:
    info = zipfile.ZipInfo.from_file(path, name)
    info.external_attr = 0o600 << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    with open(path, "rb") as src, z.open(info, "w") as out:
        while True:
            block = src.read(1024 * 1024)
            if not block:
                break
            out.write(block)


def _chat_members(directory: str) -> List[tuple]:
    out = []
    for rel, full in bz.walk_files(directory):
        name = "chats/" + rel
        match = bz.CHAT_FILE.match(name)
        blob = bz.BLOB.match(name)
        if name in ("chats/index.ini", "chats/projects.ini"):
            out.append((name, full))
        elif match and chat_files.valid_id(match.group(1)):
            out.append((name, full))
        elif blob and chat_files.valid_id(blob.group(2)):
            out.append((name, full))
    return out


def cmd_backup_create(payload: Dict[str, Any]) -> None:
    try:
        directory = chats._chat_dir(payload)
        dest = safe_path(payload.get("dest"))
        if os.path.isdir(dest):
            raise bz.BackupError("Pick a file name, not a folder.")
        members = _chat_members(directory)
        if sum(os.path.getsize(p) for _, p in members) > bz.MAX_TOTAL:
            raise bz.BackupError("The chats are larger than 2 GB, too big for one backup file.")
        settings, left_out = bz.filter_settings(payload.get("settings"))
        counts = {"chats": sum(1 for n, _ in members if bz.CHAT_FILE.match(n)),
                  "attachments": sum(1 for n, _ in members if n.startswith("chats/attachments/")),
                  "images": sum(1 for n, _ in members if n.startswith("chats/images/")),
                  "settings": len(settings), "settingsLeftOut": left_out}
        extra: Dict[str, bytes] = {}
        for name, path in (("memory.json", memory.memory_path()), ("schedules.v2.json", schedule_store.store_path()),
                           ("tool-approvals.json", tool_approvals.approvals_path())):
            data = _json_file(path)
            if data is not None:
                extra[name] = json.dumps(data, ensure_ascii=False, indent=1).encode("utf-8")
        mcp, redacted = _mcp_without_secrets(_json_file(mcp_config.config_path()))
        if mcp is not None:
            extra["mcp.json"] = json.dumps(mcp, ensure_ascii=False, indent=1).encode("utf-8")
        counts["mcpValuesReplaced"] = redacted
        counts["memories"] = len((json.loads(extra["memory.json"]) or {}).get("memories", [])) if "memory.json" in extra else 0
        counts["schedules"] = len((json.loads(extra["schedules.v2.json"]) or {}).get("schedules", [])) if "schedules.v2.json" in extra else 0
        counts["mcpServers"] = len(mcp["mcpServers"]) if mcp else 0
        manifest = {"format": FORMAT, "app": "kdeaichat", "widgetVersion": str(payload.get("widgetVersion") or "")[:40],
                    "created": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "contents": counts}
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".kdeaichat-backup-", suffix=".tmp", dir=os.path.dirname(dest))
        try:
            os.fchmod(fd, 0o600)
            with os.fdopen(fd, "wb") as raw, zipfile.ZipFile(raw, "w", zipfile.ZIP_DEFLATED) as z:
                _add_bytes(z, "manifest.json", json.dumps(manifest, indent=1).encode("utf-8"))
                _add_bytes(z, "settings.json", json.dumps(settings, ensure_ascii=False, indent=1).encode("utf-8"))
                for name, data in extra.items():
                    _add_bytes(z, name, data)
                for name, full in members:
                    _add_file(z, name, full)
            os.replace(tmp, dest)
            os.chmod(dest, 0o600)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
        _out({"ok": True, "path": dest, "bytes": os.path.getsize(dest), "contents": counts})
    except (bz.BackupError, ValueError, OSError) as e:
        _out({"ok": False, "error": str(e) or "The backup could not be written."})


def _chat_ids_in(z: zipfile.ZipFile, members: Dict[str, zipfile.ZipInfo], tmp: str) -> List[Dict[str, Any]]:
    """The index entries of the backup (valid ids only)."""
    info = members.get("chats/index.ini")
    if info is None:
        return []
    path = os.path.join(tmp, "index.ini")
    bz.copy_member(z, info, path)
    raw = qsettings_ini.read_value(path, "sessions", "")
    try:
        data = json.loads(raw) if raw else []
    except ValueError:
        raise bz.BackupError("The chat list in the backup is damaged.") from None
    if not isinstance(data, list):
        raise bz.BackupError("The chat list in the backup is damaged.")
    seen, out = set(), []
    for meta in data:
        if isinstance(meta, dict) and chat_files.valid_id(meta.get("value")) and meta["value"] not in seen:
            seen.add(meta["value"])
            out.append(meta)
    return out


def _list_in(data: Any, key: str) -> List[Any]:
    value = data.get(key) if isinstance(data, dict) else None
    return value if isinstance(value, list) else []


def _read_parts(z: zipfile.ZipFile, members: Dict[str, zipfile.ZipInfo]) -> Dict[str, Any]:
    if "manifest.json" not in members:
        raise bz.BackupError("This isn't a KDE AI Chat backup (no manifest).")
    manifest = bz.read_json(z, members["manifest.json"], "The manifest")
    if not isinstance(manifest, dict) or manifest.get("app") != "kdeaichat" or manifest.get("format") != FORMAT:
        raise bz.BackupError("This backup is from a different version and can't be read.")
    parts: Dict[str, Any] = {"manifest": manifest}
    for key, name in (("settings", "settings.json"), ("memory", "memory.json"), ("schedules", "schedules.v2.json"),
                      ("mcp", "mcp.json")):
        parts[key] = bz.read_json(z, members[name], name) if name in members else None
    return parts


def cmd_backup_inspect(payload: Dict[str, Any]) -> None:
    z = None
    try:
        z, members = bz.open_backup(safe_path(payload.get("path")))
        parts = _read_parts(z, members)
        with tempfile.TemporaryDirectory() as tmp:
            metas = _chat_ids_in(z, members, tmp)
        servers = parts["mcp"].get("mcpServers") if isinstance(parts["mcp"], dict) else None
        _out({"ok": True, "manifest": parts["manifest"], "hasSettings": isinstance(parts["settings"], dict) and bool(parts["settings"]),
              "counts": {"chats": sum(1 for m in metas if "chats/chat-%s.ini" % m["value"] in members),
                         "memories": len(_list_in(parts["memory"], "memories")),
                         "schedules": len(_list_in(parts["schedules"], "schedules")),
                         "mcpServers": len(servers) if isinstance(servers, dict) else 0}})
    except (bz.BackupError, ValueError, OSError) as e:
        _out({"ok": False, "error": str(e) or "The backup could not be read."})
    finally:
        if z:
            z.close()


def _restore_chats(z, members, directory, tmp, result) -> None:
    metas = _chat_ids_in(z, members, tmp)
    with chat_files.locked(directory):
        taken = chat_files.known_ids(directory)
        added: List[Dict[str, Any]] = []
        for meta in metas:
            chat_id = meta["value"]
            info = members.get("chats/chat-%s.ini" % chat_id)
            if chat_id in taken:
                result["chatsSkipped"] += 1
                continue
            if info is None:
                result["chatsDamaged"] += 1
                continue
            staged = os.path.join(directory, ".restore-%d.tmp" % os.getpid())
            try:
                bz.copy_member(z, info, staged)
                raw = qsettings_ini.read_value(staged, "messages", "")
                if raw and not isinstance(json.loads(raw), list):
                    raise ValueError("messages")
                os.replace(staged, os.path.join(directory, "chat-%s.ini" % chat_id))
            except (ValueError, bz.BackupError):
                result["chatsDamaged"] += 1
                if os.path.exists(staged):
                    os.unlink(staged)
                continue
            _restore_blobs(z, members, directory, chat_id)
            added.append(meta)
            taken.add(chat_id)
        chat_files.add_to_index(directory, added)
        result["chatsAdded"] = len(added)
        _restore_projects(z, members, directory, tmp, result)


def _restore_blobs(z, members, directory, chat_id) -> None:
    folder = chats.chat_folder_name(chat_id)
    for name, info in members.items():
        match = bz.BLOB.match(name)
        if not match or match.group(2) != folder:
            continue
        target_dir = os.path.join(directory, match.group(1), folder)
        common.ensure_private_dir(os.path.join(directory, match.group(1)))
        common.ensure_private_dir(target_dir)
        target = os.path.join(target_dir, match.group(3))
        if os.path.lexists(target):
            continue  # never overwritten
        staged = target + ".restore.tmp"
        bz.copy_member(z, info, staged)
        os.replace(staged, target)


def _restore_projects(z, members, directory, tmp, result) -> None:
    info = members.get("chats/projects.ini")
    if info is None:
        return
    path = os.path.join(tmp, "projects.ini")
    bz.copy_member(z, info, path)
    try:
        theirs = json.loads(qsettings_ini.read_value(path, "projects", "") or "[]")
    except ValueError:
        return
    ours = schedule_chat.load_projects(directory)
    have = {str(p.get("id")) for p in ours}
    new = [p for p in theirs if isinstance(p, dict) and isinstance(p.get("id"), str) and p["id"] not in have] \
        if isinstance(theirs, list) else []
    if new:
        qsettings_ini.write_values(os.path.join(directory, "projects.ini"),
                                   {"version": "1", "projects": json.dumps(ours + new, ensure_ascii=False, separators=(",", ":"))})
    result["projectsAdded"] = len(new)


def _restore_memories(data: Any, result) -> None:
    with memory._locked():
        have = memory.load()
        taken = {m["id"] for m in have}
        keys = {memory._key(m) for m in have}
        added = 0
        for raw in _list_in(data, "memories"):
            item = memory.normalize(raw)
            if item is None or memory._key(item) in keys:
                result["memoriesSkipped"] += 1
                continue
            if len(have) >= memory.MAX_MEMORIES:
                result["memoriesSkipped"] += 1
                continue
            if item["id"] in taken:
                item["id"] = memory._new_id(taken)
            have.append(item)
            taken.add(item["id"])
            keys.add(memory._key(item))
            added += 1
        if added:
            memory._save(have)
        result["memoriesAdded"] = added


def _restore_schedules(data: Any, result) -> None:
    incoming = _list_in(data, "schedules")
    if not incoming:
        return
    now = schedule_model.now_local()
    with common.schedule_store_lock():
        store = schedule_store.read_store() or schedule_store._migrate_locked(now)
        have = {s["id"] for s in store["schedules"]}
        added = 0
        for raw in incoming:
            if not isinstance(raw, dict) or raw.get("id") in have or len(store["schedules"]) >= schedule_store.MAX_SCHEDULES:
                result["schedulesSkipped"] += 1
                continue
            try:
                item = schedule_model.normalize_schedule(dict(raw, enabled=False), now=now)
            except (ValueError, TypeError):
                result["schedulesSkipped"] += 1
                continue
            store["schedules"].append(item)
            have.add(item["id"])
            added += 1
        if added:
            common.atomic_write_json(schedule_store.store_path(), store)
            schedule_store._sync(store, now)
        result["schedulesAdded"] = added


def _restore_mcp(data: Any, result) -> None:
    servers = data.get("mcpServers") if isinstance(data, dict) else None
    if not isinstance(servers, dict):
        return
    have = mcp_config._load()
    added = 0
    for sid, raw in servers.items():
        if sid in have:
            result["mcpSkipped"] += 1
            continue
        try:
            item = mcp_config.validate(dict(raw, id=sid) if isinstance(raw, dict) else raw)
        except ValueError:
            result["mcpSkipped"] += 1
            continue
        item.pop("id")
        have[sid] = item
        added += 1
    if added:
        mcp_config._store(have)
    result["mcpAdded"] = added


def cmd_backup_restore(payload: Dict[str, Any]) -> None:
    z = None
    try:
        if payload.get("mode", "merge") != "merge":
            raise bz.BackupError("Only merging a backup into your data is supported.")
        directory = chat_files.folder(payload)
        z, members = bz.open_backup(safe_path(payload.get("path")))
        parts = _read_parts(z, members)
        result: Dict[str, Any] = {"ok": True, "chatsAdded": 0, "chatsSkipped": 0, "chatsDamaged": 0, "projectsAdded": 0,
                                  "memoriesAdded": 0, "memoriesSkipped": 0, "schedulesAdded": 0, "schedulesSkipped": 0,
                                  "mcpAdded": 0, "mcpSkipped": 0}
        with tempfile.TemporaryDirectory() as tmp:
            _restore_chats(z, members, directory, tmp, result)
        _restore_memories(parts["memory"], result)
        _restore_schedules(parts["schedules"], result)
        _restore_mcp(parts["mcp"], result)
        if payload.get("withSettings") is True and isinstance(parts["settings"], dict):
            result["settings"] = bz.filter_settings(parts["settings"])[0]
        _out(result)
    except (bz.BackupError, ValueError, OSError) as e:
        _out({"ok": False, "error": str(e) or "The backup could not be restored."})
    finally:
        if z:
            z.close()


COMMANDS = {"backup_create": cmd_backup_create, "backup_inspect": cmd_backup_inspect, "backup_restore": cmd_backup_restore}
