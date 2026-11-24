"""Connections that only ever reach public internet addresses.

stdlib only (the tool bridge imports it by plain name, so it must not import
the `kdeaichat` package). The address is chosen at connect time, so DNS can't
hand out a different one later; every redirect hop connects through here too,
so a redirect into the local network is refused.
"""
import http.client
import ipaddress
import socket
import urllib.request


def global_address(host: str, port: int) -> str:
    """An address of ``host`` that is public (never loopback, private, link-local...)."""
    infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    for info in infos:
        address = info[4][0]
        if ipaddress.ip_address(address.split("%")[0]).is_global:
            return address
    raise ValueError("the address is not a public one")


class GuardedHTTPConnection(http.client.HTTPConnection):
    """Connects only to a public address, chosen at connect time."""

    def connect(self) -> None:
        address = global_address(self.host, self.port)
        self.sock = socket.create_connection((address, self.port), self.timeout)


class GuardedHTTPSConnection(http.client.HTTPSConnection):
    """Like GuardedHTTPConnection, with TLS checked against the host name."""

    def connect(self) -> None:
        address = global_address(self.host, self.port)
        sock = socket.create_connection((address, self.port), self.timeout)
        self.sock = self._context.wrap_socket(sock, server_hostname=self.host)  # type: ignore[attr-defined]


class GuardedHTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, req):  # type: ignore[no-untyped-def]
        return self.do_open(GuardedHTTPSConnection, req, context=self._context)


class GuardedHTTPHandler(urllib.request.HTTPHandler):
    def http_open(self, req):  # type: ignore[no-untyped-def]
        return self.do_open(GuardedHTTPConnection, req)
