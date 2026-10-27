"""A tiny D-Bus client/service in plain Python (stdlib only), just enough for the KRunner runner.

Why not a D-Bus library: python3-dbus / PyGObject / jeepney are not installed on every KDE system and the
widget's helper code is stdlib-only by design. The wire protocol (v1) is small: a SASL EXTERNAL handshake on
the session bus socket, then messages made of a header (a fixed part plus an array of header fields) and a
body in a typed encoding. This module does the types the runner uses (y b n q i u x t d s o g v a () {}),
method calls, replies and errors. It is checked against a real dbus-daemon in tests/test_krunner.py.

Values: struct = tuple, array = list, dict (a{..}) = dict or list of pairs, variant = (signature, value).
"""
import os
import select
import socket
import struct
import urllib.parse
from typing import Any, Dict, List, Optional, Tuple

METHOD_CALL, METHOD_RETURN, ERROR, SIGNAL = 1, 2, 3, 4
NO_REPLY_EXPECTED = 0x1
PATH, INTERFACE, MEMBER, ERROR_NAME, REPLY_SERIAL, DESTINATION, SENDER, SIGNATURE = range(1, 9)

_FIXED = {"y": ("B", 1), "b": ("I", 4), "n": ("h", 2), "q": ("H", 2), "i": ("i", 4), "u": ("I", 4),
          "x": ("q", 8), "t": ("Q", 8), "d": ("d", 8)}


class DBusError(Exception):
    pass


class MalformedMessage(DBusError):
    """One message could not be parsed; it is already consumed, so the connection stays usable."""


MAX_MESSAGE = 128 * 1024 * 1024


def split_signature(sig: str) -> List[str]:
    """'sa{sv}(ii)' -> ['s', 'a{sv}', '(ii)']."""
    out, i = [], 0
    while i < len(sig):
        j = _end_of_type(sig, i)
        out.append(sig[i:j])
        i = j
    return out


def _end_of_type(sig: str, i: int) -> int:
    c = sig[i]
    if c == "a":
        return _end_of_type(sig, i + 1)
    if c in "({":
        close = ")" if c == "(" else "}"
        depth, j = 0, i
        while j < len(sig):
            if sig[j] in "({":
                depth += 1
            elif sig[j] in ")}":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        if j >= len(sig) or sig[j] != close:
            raise DBusError("bad signature " + sig)
        return j + 1
    if c not in "ybnqiuxtdsogv":
        raise DBusError("unsupported type " + c)
    return i + 1


def _align(n: int, a: int) -> int:
    return (n + a - 1) & ~(a - 1)


def _alignment(t: str) -> int:
    if t[0] in _FIXED:
        return _FIXED[t[0]][1]
    return {"s": 4, "o": 4, "a": 4, "g": 1, "v": 1, "(": 8, "{": 8}[t[0]]


class Writer:
    def __init__(self, base: int = 0) -> None:
        self.buf = bytearray()
        self.base = base  # offset of buf[0] in the message, for alignment

    def pad(self, a: int) -> None:
        self.buf += b"\0" * (_align(self.base + len(self.buf), a) - self.base - len(self.buf))

    def put(self, t: str, v: Any) -> None:
        c = t[0]
        if c in _FIXED:
            fmt, size = _FIXED[c]
            self.pad(size)
            self.buf += struct.pack("<" + fmt, int(v) if c != "d" else float(v))
        elif c in "so":
            data = str(v).encode("utf-8")
            self.pad(4)
            self.buf += struct.pack("<I", len(data)) + data + b"\0"
        elif c == "g":
            data = str(v).encode("ascii")
            self.buf += bytes([len(data)]) + data + b"\0"
        elif c == "v":
            sig, value = v
            self.put("g", sig)
            self.put(sig, value)
        elif c == "a":
            inner = t[1:]
            items = list(v.items()) if isinstance(v, dict) else list(v)
            self.pad(4)
            lenpos = len(self.buf)
            self.buf += b"\0\0\0\0"
            self.pad(_alignment(inner))
            start = len(self.buf)
            for item in items:
                self.put(inner, item)
            struct.pack_into("<I", self.buf, lenpos, len(self.buf) - start)
        elif c == "(":
            self.pad(8)
            for sub, item in zip(split_signature(t[1:-1]), v):
                self.put(sub, item)
        elif c == "{":
            self.pad(8)
            key, value = split_signature(t[1:-1])
            self.put(key, v[0])
            self.put(value, v[1])
        else:
            raise DBusError("cannot write " + t)


def marshal(sig: str, values: Tuple[Any, ...], base: int = 0) -> bytes:
    w = Writer(base)
    for t, v in zip(split_signature(sig), values):
        w.put(t, v)
    return bytes(w.buf)


class Reader:
    def __init__(self, data: bytes, pos: int = 0) -> None:
        self.data, self.pos = data, pos

    def pad(self, a: int) -> None:
        self.pos = _align(self.pos, a)

    def take(self, n: int) -> bytes:
        if self.pos + n > len(self.data):
            raise MalformedMessage("message too short")
        chunk = self.data[self.pos:self.pos + n]
        self.pos += n
        return chunk

    def get(self, t: str) -> Any:
        c = t[0]
        if c in _FIXED:
            fmt, size = _FIXED[c]
            self.pad(size)
            value = struct.unpack("<" + fmt, self.take(size))[0]
            return bool(value) if c == "b" else value
        if c in "so":
            self.pad(4)
            n = struct.unpack("<I", self.take(4))[0]
            value = self.take(n).decode("utf-8", "replace")
            self.take(1)
            return value
        if c == "g":
            n = self.take(1)[0]
            value = self.take(n).decode("ascii", "replace")
            self.take(1)
            return value
        if c == "v":
            sig = self.get("g")
            return (sig, self.get(sig))
        if c == "a":
            inner = t[1:]
            self.pad(4)
            n = struct.unpack("<I", self.take(4))[0]
            self.pad(_alignment(inner))
            end = self.pos + n
            out = []
            while self.pos < end:
                out.append(self.get(inner))
            return out
        if c == "(":
            self.pad(8)
            return tuple(self.get(sub) for sub in split_signature(t[1:-1]))
        if c == "{":
            self.pad(8)
            key, value = split_signature(t[1:-1])
            return (self.get(key), self.get(value))
        raise DBusError("cannot read " + t)


class Message:
    def __init__(self, mtype: int, flags: int = 0, serial: int = 0, fields: Optional[Dict[int, Any]] = None,
                 sig: str = "", body: Tuple[Any, ...] = ()) -> None:
        self.type, self.flags, self.serial = mtype, flags, serial
        self.fields: Dict[int, Any] = fields or {}
        self.sig, self.body = sig, body

    @property
    def path(self) -> str:
        return self.fields.get(PATH, "")

    @property
    def interface(self) -> str:
        return self.fields.get(INTERFACE, "")

    @property
    def member(self) -> str:
        return self.fields.get(MEMBER, "")

    def encode(self) -> bytes:
        body = marshal(self.sig, self.body) if self.sig else b""
        fields = dict(self.fields)
        if self.sig:
            fields[SIGNATURE] = self.sig
        w = Writer(12)  # the array starts after 12 fixed bytes
        entries = []
        for code, value in fields.items():
            sig = {PATH: "o", REPLY_SERIAL: "u", SIGNATURE: "g"}.get(code, "s")
            entries.append((code, (sig, value)))
        w.put("a(yv)", entries)
        head = struct.pack("<cBBBII", b"l", self.type, self.flags, 1, len(body), self.serial) + bytes(w.buf)
        head += b"\0" * (_align(len(head), 8) - len(head))
        return head + body


def decode(data: bytes) -> Message:
    """Parses one message; anything malformed raises DBusError (never IndexError or struct.error)."""
    try:
        return _decode(data)
    except (DBusError, IndexError, struct.error, ValueError, RecursionError) as error:  # UnicodeDecodeError is a ValueError
        raise MalformedMessage("malformed message: %s" % error)


def _decode(data: bytes) -> Message:
    if data[:1] != b"l":
        raise DBusError("only little-endian messages are supported")
    mtype, flags, _version, blen, serial = struct.unpack("<BBBII", data[1:12])
    r = Reader(data, 12)
    fields: Dict[int, Any] = {}
    for code, (_sig, value) in r.get("a(yv)"):
        fields[code] = value
    r.pos = _align(r.pos, 8)
    sig = fields.get(SIGNATURE, "")
    body = ()
    if sig and blen:
        rb = Reader(data, r.pos)
        body = tuple(rb.get(t) for t in split_signature(sig))
    return Message(mtype, flags, serial, fields, sig, body)


def session_address() -> str:
    address = os.environ.get("DBUS_SESSION_BUS_ADDRESS", "")
    if not address:
        address = "unix:path=/run/user/%d/bus" % os.getuid()
    for part in address.split(";"):
        if part.startswith("unix:"):
            return part
    raise DBusError("no unix session bus address")


def _socket_path(address: str) -> str:
    opts = dict(p.split("=", 1) for p in address[len("unix:"):].split(",") if "=" in p)
    if "path" in opts:
        return urllib.parse.unquote(opts["path"])
    if "abstract" in opts:
        return "\0" + urllib.parse.unquote(opts["abstract"])
    raise DBusError("unsupported bus address")


class Connection:
    """One bus connection: handshake, Hello, then call()/read()."""

    def __init__(self, address: Optional[str] = None) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect(_socket_path(address or session_address()))
        self.buf = b""
        self.serial = 0
        # Messages that arrived while call() waited for its reply (for a D-Bus-activated service, the call
        # that started it comes in right after RequestName), handed out by read() first.
        self.pending: List[Message] = []
        self._handshake()
        self.unique_name = self.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "Hello").body[0]

    def _handshake(self) -> None:
        uid = str(os.getuid()).encode().hex().encode()
        self.sock.sendall(b"\0AUTH EXTERNAL " + uid + b"\r\n")
        line = b""
        while not line.endswith(b"\r\n"):
            chunk = self.sock.recv(1)
            if not chunk:
                raise DBusError("the bus closed the connection")
            line += chunk
        if not line.startswith(b"OK"):
            raise DBusError("the bus refused the login: " + line.decode("ascii", "replace").strip())
        self.sock.sendall(b"BEGIN\r\n")

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass

    def send(self, message: Message) -> int:
        self.serial += 1
        message.serial = self.serial
        self.sock.sendall(message.encode())
        return self.serial

    def _fill(self, n: int, timeout: Optional[float]) -> bool:
        while len(self.buf) < n:
            if timeout is not None and not select.select([self.sock], [], [], timeout)[0]:
                return False
            chunk = self.sock.recv(65536)
            if not chunk:
                raise DBusError("the bus closed the connection")
            self.buf += chunk
        return True

    def read(self, timeout: Optional[float] = None, max_size: int = MAX_MESSAGE) -> Optional[Message]:
        """The next message, or None when none arrived within ``timeout`` seconds."""
        if self.pending:
            return self.pending.pop(0)
        return self._read_wire(timeout, max_size)

    def _read_wire(self, timeout: Optional[float], max_size: int = MAX_MESSAGE) -> Optional[Message]:
        if not self._fill(16, timeout):
            return None
        blen, flen = struct.unpack("<II", self.buf[4:8] + self.buf[12:16])
        total = _align(16 + flen, 8) + blen
        if total > max_size or flen > 65536:
            raise DBusError("message too large")
        self._fill(total, None)
        data, self.buf = self.buf[:total], self.buf[total:]
        return decode(data)

    def call(self, dest: str, path: str, interface: str, member: str, sig: str = "", body: Tuple[Any, ...] = (),
             timeout: float = 10.0) -> Message:
        serial = self.send(Message(METHOD_CALL, 0, 0, {PATH: path, INTERFACE: interface, MEMBER: member, DESTINATION: dest}, sig, body))
        while True:
            message = self._read_wire(timeout)
            if message is None:
                raise DBusError("no reply from " + dest)
            if message.fields.get(REPLY_SERIAL) == serial:
                if message.type == ERROR:
                    raise DBusError("%s: %s" % (message.fields.get(ERROR_NAME, "error"), message.body[0] if message.body else ""))
                return message
            self.pending.append(message)

    def reply(self, call: Message, sig: str = "", body: Tuple[Any, ...] = ()) -> None:
        if call.flags & NO_REPLY_EXPECTED:
            return
        fields = {REPLY_SERIAL: call.serial}
        if SENDER in call.fields:
            fields[DESTINATION] = call.fields[SENDER]
        self.send(Message(METHOD_RETURN, NO_REPLY_EXPECTED, 0, fields, sig, body))

    def reply_error(self, call: Message, name: str, text: str) -> None:
        if call.flags & NO_REPLY_EXPECTED:
            return
        fields = {REPLY_SERIAL: call.serial, ERROR_NAME: name}
        if SENDER in call.fields:
            fields[DESTINATION] = call.fields[SENDER]
        self.send(Message(ERROR, NO_REPLY_EXPECTED, 0, fields, "s", (text,)))

    def request_name(self, name: str) -> bool:
        """Owns a well-known name (not queued: False when someone else has it)."""
        reply = self.call("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "RequestName", "su", (name, 0x4))
        return reply.body[0] in (1, 4)
