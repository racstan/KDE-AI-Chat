"""A minimal D-Bus client for the one call that carries private text.

``busctl`` takes every argument on its command line, which any local user can
read (/proc/<pid>/cmdline). Text the user reads aloud must not go there, so
``call`` speaks the D-Bus wire protocol over the session bus socket itself
(EXTERNAL auth, little-endian, no fd passing). It supports only what Speech
Note's methods need: arguments of type ``i`` and ``s``, replies of ``i``/``s``.
"""
import os
import socket
import struct
from typing import Any, Dict, List, Tuple
from urllib.parse import unquote

TIMEOUT = 15.0
MAX_BODY = 64 * 1024 * 1024


class WireError(Exception):
    """Connecting, authenticating or the bus's reply failed (``name`` is the D-Bus error name if any)."""

    def __init__(self, message: str, name: str = ""):
        super().__init__(message)
        self.name = name


def _address() -> str:
    raw = os.environ.get("DBUS_SESSION_BUS_ADDRESS") or "unix:path=/run/user/%d/bus" % os.getuid()
    for part in raw.split(";"):
        if not part.startswith("unix:"):
            continue
        fields = dict(p.split("=", 1) for p in part[5:].split(",") if "=" in p)
        if fields.get("path"):
            return unquote(fields["path"])
        if fields.get("abstract"):
            return "\0" + unquote(fields["abstract"])
    raise WireError("no usable session bus address")


class _Writer:
    def __init__(self) -> None:
        self.buf = bytearray()

    def align(self, n: int) -> None:
        self.buf.extend(b"\0" * (-len(self.buf) % n))

    def u32(self, v: int) -> None:
        self.align(4)
        self.buf.extend(struct.pack("<I", v))

    def i32(self, v: int) -> None:
        self.align(4)
        self.buf.extend(struct.pack("<i", v))

    def string(self, s: str) -> None:
        data = s.encode("utf-8")
        if b"\0" in data:
            raise WireError("text contains a NUL character")
        self.u32(len(data))
        self.buf.extend(data + b"\0")

    def signature(self, s: str) -> None:
        self.buf.extend(bytes([len(s)]) + s.encode("ascii") + b"\0")


def _field(w: _Writer, code: int, sig: str, value: str) -> None:
    w.align(8)
    w.buf.append(code)
    w.signature(sig)
    if sig == "g":
        w.signature(value)
    else:
        w.string(value)


def build(serial: int, dest: str, path: str, iface: str, member: str, sig: str, args: List[Any]) -> bytes:
    body = _Writer()
    for kind, value in zip(sig, args):
        if kind == "s":
            body.string(str(value))
        elif kind == "i":
            body.i32(int(value))
        else:
            raise WireError("unsupported argument type " + kind)
    fields = _Writer()
    _field(fields, 1, "o", path)
    if iface:
        _field(fields, 2, "s", iface)
    _field(fields, 3, "s", member)
    _field(fields, 6, "s", dest)
    if sig:
        _field(fields, 8, "g", sig)
    head = struct.pack("<BBBBIII", ord("l"), 1, 0, 1, len(body.buf), serial, len(fields.buf))
    out = bytearray(head + bytes(fields.buf))
    out.extend(b"\0" * (-len(out) % 8))
    return bytes(out + body.buf)


def _read(sock: socket.socket, n: int) -> bytes:
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise WireError("the bus closed the connection")
        data += chunk
    return data


def read_message(sock: socket.socket) -> Tuple[int, Dict[int, Any], bytes]:
    """(message type, header fields by code, body); fields of types o, s, u, g are decoded."""
    head = _read(sock, 16)
    if head[0:1] != b"l":
        raise WireError("unexpected byte order")
    mtype, _flags, _ver, blen, _serial, flen = struct.unpack("<BBBIII", head[1:])
    if blen > MAX_BODY:
        raise WireError("reply too large")
    raw = _read(sock, flen + (-flen % 8))[:flen]
    body = _read(sock, blen)
    fields: Dict[int, Any] = {}
    pos = 0
    while pos < flen:
        pos += -pos % 8
        if pos >= flen:
            break
        code = raw[pos]
        slen = raw[pos + 1]
        sig = raw[pos + 2:pos + 2 + slen].decode("ascii")
        pos += slen + 3
        if sig in ("s", "o"):
            pos += -pos % 4
            n = struct.unpack_from("<I", raw, pos)[0]
            fields[code] = raw[pos + 4:pos + 4 + n].decode("utf-8", "replace")
            pos += 5 + n
        elif sig == "u":
            pos += -pos % 4
            fields[code] = struct.unpack_from("<I", raw, pos)[0]
            pos += 4
        elif sig == "g":
            n = raw[pos]
            fields[code] = raw[pos + 1:pos + 1 + n].decode("ascii")
            pos += n + 2
        else:
            raise WireError("unsupported header field type " + sig)
    return mtype, fields, body


def _await_reply(sock: socket.socket, serial: int) -> Tuple[Dict[int, Any], bytes]:
    while True:
        mtype, fields, body = read_message(sock)
        if fields.get(5) != serial:
            continue  # signals and replies to other calls
        if mtype == 3:
            name = fields.get(4, "")
            raise WireError("D-Bus error " + name, name)
        return fields, body


def call(dest: str, path: str, iface: str, member: str, sig: str, args: List[Any]) -> Any:
    """Call a method on the session bus; returns the single ``i`` or ``s`` reply value, else None."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(TIMEOUT)
    try:
        sock.connect(_address())
        sock.sendall(b"\0AUTH EXTERNAL " + str(os.getuid()).encode().hex().encode() + b"\r\n")
        reply = b""
        while b"\r\n" not in reply:
            chunk = sock.recv(256)
            if not chunk:
                raise WireError("the bus closed the connection")
            reply += chunk
        if not reply.startswith(b"OK"):
            raise WireError("the bus refused authentication")
        sock.sendall(b"BEGIN\r\n")
        sock.sendall(build(1, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello", "", []))
        _await_reply(sock, 1)
        sock.sendall(build(2, dest, path, iface, member, sig, args))
        fields, body = _await_reply(sock, 2)
        kind = fields.get(8, "")
        if kind == "i":
            return struct.unpack_from("<i", body, 0)[0]
        if kind == "s":
            n = struct.unpack_from("<I", body, 0)[0]
            return body[4:4 + n].decode("utf-8", "replace")
        return None
    except (OSError, struct.error) as e:
        raise WireError("D-Bus connection failed: %s" % e) from None
    finally:
        sock.close()
