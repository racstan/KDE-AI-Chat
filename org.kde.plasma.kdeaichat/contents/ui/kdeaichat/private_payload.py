"""Payloads that must not be on the command line (chat text read aloud).

store/HelperRunner.qml writes them with QtCore Settings to
``$XDG_RUNTIME_DIR/kdeaichat-payload-<n>.ini`` (a private 0700 folder) as
``payload=<base64url JSON>`` and passes ``@<file name>`` instead of the
base64 payload, because a process's arguments can be read by every local
user (/proc/<pid>/cmdline) while the runtime folder can't.

``read`` accepts only that file-name pattern in the runtime folder, only a
regular file owned by us in a folder only we can open, and deletes it.
"""
import base64
import json
import os
import re
import stat
from typing import Any, Dict

_NAME = re.compile(r"^kdeaichat-payload-[A-Za-z0-9-]{1,80}\.ini$")
MAX_BYTES = 1024 * 1024


class PayloadError(ValueError):
    pass


def runtime_dir() -> str:
    """Qt's RuntimeLocation: $XDG_RUNTIME_DIR, else /tmp/runtime-<user>."""
    folder = os.environ.get("XDG_RUNTIME_DIR")
    if folder:
        return folder
    import pwd
    return "/tmp/runtime-" + pwd.getpwuid(os.getuid()).pw_name


def read(argument: str, folder: str = "") -> Dict[str, Any]:
    name = argument[1:] if argument.startswith("@") else argument
    if not _NAME.match(name):
        raise PayloadError("bad payload file name")
    folder = folder or runtime_dir()
    info = os.stat(folder)
    if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o077:
        raise PayloadError("the runtime folder is not private")
    path = os.path.join(folder, name)
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    except OSError as e:
        raise PayloadError("can't open the payload file: %s" % (e.strerror or e)) from None
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > MAX_BYTES:
            raise PayloadError("the payload file is not ours")
        with os.fdopen(fd, "r", encoding="utf-8", errors="replace") as f:
            fd = -1
            text = f.read()
    finally:
        if fd >= 0:
            os.close(fd)
        try:
            os.unlink(path)
        except OSError:
            pass
    for line in text.splitlines():
        key, _, value = line.partition("=")
        if key.strip() == "payload":
            value = value.strip().strip('"')
            data = json.loads(base64.urlsafe_b64decode(value + "=" * (-len(value) % 4)).decode("utf-8"))
            if not isinstance(data, dict):
                raise PayloadError("the payload is not an object")
            return data
    raise PayloadError("no payload in the file")
