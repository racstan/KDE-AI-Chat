"""Images in chats: saving, deleting, copying and exporting image files.

Images a model sends back (or an image service makes) are kept as files under
the chat folder, never inside the chat history:

    chats/applet-<id>/images/<chatId>/<messageId>-<n>.<png|jpg|webp|gif>

The widget (QML) cannot write binary files, so it hands the helper either a
staging file it wrote itself (the base64 text of an image, too big for a
command line) or an https link for the helper to fetch. Every file is checked
by its first bytes (never by its name or the server's content type), capped in
size, and written privately and atomically.

Commands (payload is JSON; ``directory`` is chats/applet-<id>):
  image_save    {directory, chat, message, n, staging | url}
                -> {"path", "mime", "bytes"} or {"error", "code"}
  image_delete  {directory, chat, message?}   one message's files, or the chat's
  image_copy    {directory, path}             put the image on the clipboard
  image_export  {directory, path, dest}       copy the image to a file the user chose
"""
import base64
import http.client
import ipaddress
import json
import os
import re
import shutil
import socket
import ssl
import tempfile
import urllib.error
import urllib.request
from typing import Any, Dict, Optional, Tuple
from urllib.parse import urljoin, urlsplit

from kdeaichat import chats
from kdeaichat.common import safe_path

MAX_IMAGE_BYTES = 12 * 1024 * 1024
# base64 text in a staging file: 4/3 of the image, plus line-ending slack.
MAX_STAGING_BYTES = MAX_IMAGE_BYTES * 4 // 3 + 4096
FETCH_TIMEOUT = 20
USER_AGENT = "KDE-AI-Chat-image-fetch"

_NAME = re.compile(r"[^A-Za-z0-9._-]")
_STAGING = re.compile(r"^staging-[A-Za-z0-9._-]{1,80}\.ini$")
_REL_PATH = re.compile(r"^images/[A-Za-z0-9._-]{1,128}/[A-Za-z0-9._-]{1,200}\.(png|jpg|webp|gif)$")


def sniff(data: bytes) -> Optional[Tuple[str, str]]:
    """(mime, extension) from the first bytes, or None when it is not png/jpeg/webp/gif."""
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png", "png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg", "jpg"
    if data[:6] in (b"GIF87a", b"GIF89a"):
        return "image/gif", "gif"
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp", "webp"
    return None


def _clean_name(value: Any, what: str) -> str:
    name = _NAME.sub("_", str(value or ""))[:128].strip(".")
    if not name:
        raise ValueError(what + " is required")
    return name


def _image_dir(payload: Dict[str, Any], create: bool = False) -> str:
    base = chats._chat_dir(payload)
    path = os.path.join(base, "images", _clean_name(payload.get("chat"), "chat"))
    if create:
        for folder in (os.path.join(base, "images"), path):
            os.makedirs(folder, mode=0o700, exist_ok=True)
            os.chmod(folder, 0o700)
    return path


def _file_for(payload: Dict[str, Any]) -> str:
    """The absolute file for a relative ``path`` such as images/<chat>/<name>.png."""
    base = os.path.realpath(chats._chat_dir(payload))
    rel = str(payload.get("path", ""))
    if not _REL_PATH.match(rel):
        raise ValueError("invalid image path")
    full = os.path.realpath(os.path.join(base, rel))
    if not full.startswith(base + os.sep) or not os.path.isfile(full):
        raise ValueError("image not found")
    return full


def _error(code: str, message: str) -> None:
    print(json.dumps({"error": message, "code": code}))


# --- Reading the image's bytes -------------------------------------------------

def _read_staging(payload: Dict[str, Any]) -> bytes:
    """The base64 text the widget wrote to staging-<token>.ini (key ``data``), decoded. The file is deleted."""
    name = str(payload.get("staging", ""))
    if not _STAGING.match(name):
        raise ValueError("invalid staging file")
    path = os.path.join(chats._chat_dir(payload), name)
    try:
        if os.path.islink(path) or os.path.getsize(path) > MAX_STAGING_BYTES + 256:
            raise ValueError("image data is too large")
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
    finally:
        try:
            os.unlink(path)
        except OSError:
            pass
    match = re.search(r"^data=(.*)$", text, re.M)
    value = (match.group(1) if match else "").strip()
    if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        value = value[1:-1]
    if len(value) > MAX_STAGING_BYTES:
        raise ValueError("image data is too large")
    return base64.b64decode(value.replace("\\", ""), validate=True)


def _global_address(host: str, port: int) -> str:
    """An address of ``host`` that is public (never loopback, private, link-local...)."""
    infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    for info in infos:
        address = info[4][0]
        if ipaddress.ip_address(address.split("%")[0]).is_global:
            return address
    raise ValueError("the address is not a public one")


class _GuardedHTTPS(http.client.HTTPSConnection):
    """Connects only to a public address, chosen at connect time (so DNS cannot change it later)."""

    def connect(self) -> None:
        address = _global_address(self.host, self.port)
        sock = socket.create_connection((address, self.port), self.timeout)
        self.sock = self._context.wrap_socket(sock, server_hostname=self.host)  # type: ignore[attr-defined]


class _GuardedHandler(urllib.request.HTTPSHandler):
    def https_open(self, req):  # type: ignore[no-untyped-def]
        return self.do_open(_GuardedHTTPS, req, context=self._context)


def valid_image_url(url: str) -> bool:
    """https only, a host name, no credentials, no control characters."""
    if not url or len(url) > 4096 or re.search(r"[\x00-\x20\x7f]", url):
        return False
    parts = urlsplit(url)
    return parts.scheme == "https" and bool(parts.hostname) and parts.username is None and parts.password is None


class _CheckedRedirects(urllib.request.HTTPRedirectHandler):
    """Every hop must pass the same checks as the first link (https, no credentials)."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        target = urljoin(req.full_url, newurl)
        if not valid_image_url(target):
            raise urllib.error.HTTPError(req.full_url, code, "refused a redirect to a link that is not an https one", headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, target)


def _open_url(url: str):  # type: ignore[no-untyped-def]
    # Only the guarded https handler: no http, ftp or file handlers, so a redirect cannot reach this computer.
    # Each hop connects through _GuardedHTTPS, which also refuses non-public addresses.
    opener = urllib.request.OpenerDirector()
    for handler in (_GuardedHandler(context=ssl.create_default_context()), _CheckedRedirects(),
                    urllib.request.HTTPErrorProcessor(), urllib.request.UnknownHandler()):
        opener.add_handler(handler)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "image/png,image/jpeg,image/webp,image/gif"})
    return opener.open(request, timeout=FETCH_TIMEOUT)


def _fetch(url: str) -> bytes:
    if not valid_image_url(url):
        raise ValueError("only https image links are allowed")
    with _open_url(url) as response:
        length = response.headers.get("Content-Length")
        if length and length.isdigit() and int(length) > MAX_IMAGE_BYTES:
            raise OverflowError
        data = response.read(MAX_IMAGE_BYTES + 1)
    if len(data) > MAX_IMAGE_BYTES:
        raise OverflowError
    return data


# --- Commands ----------------------------------------------------------------------

def _write_private(path: str, data: bytes) -> None:
    folder = os.path.dirname(path)
    fd, tmp = tempfile.mkstemp(prefix="." + os.path.basename(path) + ".", dir=folder)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def cmd_image_save(payload: Dict[str, Any]) -> None:
    message = _clean_name(payload.get("message"), "message")
    n = int(payload.get("n", 0))
    if not 0 <= n < 100:
        raise ValueError("invalid image number")
    folder = _image_dir(payload)
    try:
        if payload.get("staging"):
            data = _read_staging(payload)
        elif payload.get("url"):
            data = _fetch(str(payload["url"]))
        else:
            raise ValueError("staging or url is required")
    except OverflowError:
        return _error("too_large", "The image is larger than %d MB." % (MAX_IMAGE_BYTES // (1024 * 1024)))
    except (urllib.error.HTTPError,) as e:
        return _error("http_%d" % e.code, "The server answered HTTP %d." % e.code)
    except (urllib.error.URLError, OSError, http.client.HTTPException, ssl.SSLError) as e:
        return _error("fetch_failed", "The image could not be loaded: %s" % getattr(e, "reason", e))
    except (ValueError, base64.binascii.Error) as e:  # type: ignore[attr-defined]
        return _error("bad_data", "The image data was not valid: %s" % e)
    if len(data) > MAX_IMAGE_BYTES:
        return _error("too_large", "The image is larger than %d MB." % (MAX_IMAGE_BYTES // (1024 * 1024)))
    kind = sniff(data)
    if kind is None:
        return _error("not_image", "That is not a PNG, JPEG, WebP or GIF image.")
    _image_dir(payload, create=True)
    base = os.path.realpath(chats._chat_dir(payload))
    name = "%s-%d.%s" % (message, n, kind[1])
    full = os.path.join(folder, name)
    _write_private(full, data)
    rel = "/".join(["images", os.path.basename(folder), name])
    assert os.path.realpath(full).startswith(base + os.sep)
    print(json.dumps({"path": rel, "mime": kind[0], "bytes": len(data)}))


def cmd_image_delete(payload: Dict[str, Any]) -> None:
    """Delete one message's image files (``message``) or all of a chat's (no ``message``)."""
    folder = _image_dir(payload)
    removed = 0
    if os.path.islink(folder) or not os.path.isdir(folder):
        print(json.dumps({"deleted": 0}))
        return
    if payload.get("message"):
        prefix = _clean_name(payload["message"], "message") + "-"
        for name in os.listdir(folder):
            full = os.path.join(folder, name)
            if name.startswith(prefix) and re.match(r"^\d{1,2}\.(png|jpg|webp|gif)$", name[len(prefix):]) \
                    and os.path.isfile(full) and not os.path.islink(full):
                os.unlink(full)
                removed += 1
        try:
            os.rmdir(folder)
        except OSError:
            pass
    else:
        for name in os.listdir(folder):
            full = os.path.join(folder, name)
            if not os.path.islink(full) and os.path.isfile(full):
                removed += 1
        shutil.rmtree(folder, ignore_errors=True)
    print(json.dumps({"deleted": removed}))


def _clipboard_command(mime: str, path: str) -> Optional[list]:
    if os.environ.get("WAYLAND_DISPLAY") and shutil.which("wl-copy"):
        return ["wl-copy", "--type", mime]
    if os.environ.get("DISPLAY") and shutil.which("xclip"):
        return ["xclip", "-selection", "clipboard", "-t", mime, "-i", path]
    if shutil.which("wl-copy"):
        return ["wl-copy", "--type", mime]
    if shutil.which("xclip"):
        return ["xclip", "-selection", "clipboard", "-t", mime, "-i", path]
    return None


def cmd_image_copy(payload: Dict[str, Any]) -> None:
    """Put the image on the clipboard with wl-copy (Wayland) or xclip (X11)."""
    import subprocess
    full = _file_for(payload)
    with open(full, "rb") as f:
        kind = sniff(f.read(16))
    if kind is None:
        return _error("not_image", "That file is not an image.")
    command = _clipboard_command(kind[0], full)
    if command is None:
        return _error("no_tool", "Copying an image needs wl-clipboard (Wayland) or xclip (X11).")
    # Both tools stay in the background to serve the clipboard, so nothing is read from them.
    with open(full, "rb") as source:
        result = subprocess.run(command, stdin=source, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                timeout=10, start_new_session=True)
    if result.returncode != 0:
        return _error("copy_failed", "%s could not copy the image." % command[0])
    print(json.dumps({"tool": command[0]}))


def cmd_image_export(payload: Dict[str, Any]) -> None:
    """Copy the image to ``dest`` (a path chosen in the Save dialog)."""
    full = _file_for(payload)
    dest = safe_path(payload.get("dest", ""))
    if not re.search(r"\.(png|jpe?g|webp|gif)$", dest, re.I):
        raise ValueError("the file name must end in .png, .jpg, .webp or .gif")
    if os.path.isdir(dest):
        raise ValueError("the destination is a folder")
    with open(full, "rb") as f:
        data = f.read(MAX_IMAGE_BYTES + 1)
    if len(data) > MAX_IMAGE_BYTES or sniff(data) is None:
        raise ValueError("not a valid image")
    folder = os.path.dirname(dest)
    fd, tmp = tempfile.mkstemp(prefix=".kdeaichat-", dir=folder)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        os.chmod(tmp, 0o644 & ~_umask())
        os.replace(tmp, dest)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    print(json.dumps({"saved": dest}))


def _umask() -> int:
    mask = os.umask(0)
    os.umask(mask)
    return mask


COMMANDS = {
    "image_save": cmd_image_save,
    "image_delete": cmd_image_delete,
    "image_copy": cmd_image_copy,
    "image_export": cmd_image_export,
}
