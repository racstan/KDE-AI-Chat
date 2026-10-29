"""What may go into a backup .zip and what may come out of one (used by backup.py).

The zip is untrusted input when restoring: every member name must be a plain relative path (no
leading "/", no "..", no backslashes), only the layout below is ever read, no member is a symlink,
a member is at most MAX_MEMBER bytes and all of them at most MAX_TOTAL.

Layout (see backup.py):
  manifest.json  settings.json  memory.json  schedules.v2.json  mcp.json  tool-approvals.json
  chats/index.ini  chats/projects.ini  chats/chat-<id>.ini
  chats/attachments/<chat>/<file>  chats/images/<chat>/<file>

Settings: only what is safe to keep. Anything that is or might be a secret is left out, whatever the
caller passes: every API-key setting the widget ever had (kdeaichat/privacy.py), anything whose name
says key/token/secret/password/auth/credential, values that look like a key, and the headers of
providers (they can carry an Authorization value).
"""
import json
import os
import re
import stat
import zipfile
from typing import Any, Dict, Iterator, Tuple

from kdeaichat import privacy

MAX_MEMBER = 200 * 1024 * 1024
MAX_TOTAL = 2 * 1024 * 1024 * 1024
MAX_MEMBERS = 200000
MAX_JSON = 16 * 1024 * 1024

ROOT_FILES = ("manifest.json", "settings.json", "memory.json", "schedules.v2.json", "mcp.json", "tool-approvals.json")
SEGMENT = r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}"
CHAT_FILE = re.compile(r"^chats/chat-([A-Za-z0-9._:-]{1,128})\.ini\Z")
BLOB = re.compile(r"^chats/(attachments|images)/(%s)/([A-Za-z0-9][A-Za-z0-9._-]{0,199})\Z" % SEGMENT)

SECRETISH = re.compile(r"key|token|secret|passw|auth|credential|bearer", re.I)
KEY_VALUE = re.compile(r"^(sk-|sk_|AIza|xai-|gsk_|hf_|r8_|pplx-|ghp_|Bearer\s|Basic\s)", re.I)
KEEP_NAMES = {"sendKey"}  # a keyboard setting, not a secret
NEVER_NAMES = {"chatSessionsJson", "walletKeysRevision", "lastSessionId"}
JSON_SETTINGS = ("providersJson", "customProvidersJson")
MAX_SETTING = 1024 * 1024
_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_]{0,80}\Z")


class BackupError(ValueError):
    """A message fit to show to the user."""


def secret_name(name: str) -> bool:
    return name in privacy.LEGACY_KEY_PROVIDERS or bool(privacy.KEY_NAME.match(name)) or \
        (name not in KEEP_NAMES and bool(SECRETISH.search(name)))


def _scrub(value: Any) -> Any:
    """A provider list with every secret-like field (and `headers`) removed."""
    if isinstance(value, dict):
        return {k: _scrub(v) for k, v in value.items() if not (k == "headers" or secret_name(str(k)))}
    if isinstance(value, list):
        return [_scrub(v) for v in value]
    return value


def filter_settings(settings: Any) -> Tuple[Dict[str, Any], int]:
    """(settings that are safe to keep, how many were left out)."""
    clean: Dict[str, Any] = {}
    left_out = 0
    for name, value in (settings.items() if isinstance(settings, dict) else []):
        ok = isinstance(name, str) and bool(_NAME.match(name)) and name not in NEVER_NAMES and not secret_name(name)
        ok = ok and isinstance(value, (str, int, float, bool)) and not (isinstance(value, str) and len(value) > MAX_SETTING)
        if ok and isinstance(value, str) and KEY_VALUE.match(value.strip()):
            ok = False
        if ok and name in JSON_SETTINGS and isinstance(value, str) and value.strip():
            try:
                value = json.dumps(_scrub(json.loads(value)), ensure_ascii=False)
            except ValueError:
                ok = False
        if ok:
            clean[name] = value
        else:
            left_out += 1
    return clean, left_out


def safe_member_name(name: str) -> bool:
    if not name or name.startswith("/") or "\\" in name or "\0" in name or re.match(r"^[A-Za-z]:", name):
        return False
    return all(part not in ("", ".", "..") for part in name.rstrip("/").split("/"))


def known_member(name: str) -> bool:
    return name in ROOT_FILES or name in ("chats/index.ini", "chats/projects.ini") \
        or bool(CHAT_FILE.match(name)) or bool(BLOB.match(name))


def open_backup(path: str) -> Tuple[zipfile.ZipFile, Dict[str, zipfile.ZipInfo]]:
    """The opened zip and its readable members by name. Refuses the whole file when anything is unsafe."""
    try:
        z = zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError):
        raise BackupError("This isn't a backup file (it can't be opened as a zip).") from None
    infos = z.infolist()
    if len(infos) > MAX_MEMBERS:
        z.close()
        raise BackupError("The backup has too many files.")
    total = 0
    members: Dict[str, zipfile.ZipInfo] = {}
    for info in infos:
        if not safe_member_name(info.filename):
            z.close()
            raise BackupError("The backup contains an unsafe file name, so it was not used.")
        if info.is_dir():
            continue
        mode = (info.external_attr >> 16) & 0xFFFF
        if mode and stat.S_ISLNK(mode):
            z.close()
            raise BackupError("The backup contains a link, so it was not used.")
        if info.file_size > MAX_MEMBER:
            z.close()
            raise BackupError("The backup contains a file over 200 MB, so it was not used.")
        total += info.file_size
        if total > MAX_TOTAL:
            z.close()
            raise BackupError("The backup is larger than 2 GB, so it was not used.")
        if known_member(info.filename):
            members[info.filename] = info
    return z, members


def read_json(z: zipfile.ZipFile, info: zipfile.ZipInfo, what: str) -> Any:
    """A small JSON member, parsed; BackupError when it is too big or not JSON."""
    with z.open(info) as f:
        raw = f.read(MAX_JSON + 1)
    if len(raw) > MAX_JSON:
        raise BackupError("%s is too large." % what)
    try:
        return json.loads(raw.decode("utf-8"))
    except ValueError:
        raise BackupError("%s in the backup is damaged." % what) from None


def copy_member(z: zipfile.ZipFile, info: zipfile.ZipInfo, dest: str) -> None:
    """Write a member to `dest` (created 0600, replaced if present), counting the real bytes read."""
    fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    written = 0
    try:
        with os.fdopen(fd, "wb") as out, z.open(info) as src:
            while True:
                block = src.read(1024 * 1024)
                if not block:
                    break
                written += len(block)
                if written > MAX_MEMBER:
                    raise BackupError("A file in the backup is larger than it says, so it was not used.")
                out.write(block)
    except BaseException:
        try:
            os.unlink(dest)
        except OSError:
            pass
        raise


def walk_files(root: str) -> Iterator[Tuple[str, str]]:
    """(path relative to root with "/", absolute path) of the regular files under root; links are skipped."""
    if os.path.islink(root) or not os.path.isdir(root):
        return
    for base, dirs, files in os.walk(root):
        dirs[:] = sorted(d for d in dirs if not os.path.islink(os.path.join(base, d)))
        for name in sorted(files):
            full = os.path.join(base, name)
            if not os.path.islink(full) and os.path.isfile(full):
                yield os.path.relpath(full, root).replace(os.sep, "/"), full
