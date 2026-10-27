"""HTTP for calls that carry an API key (read aloud, dictation, scheduled provider calls).

stdlib only. ``urllib`` copies request headers, key included, to wherever a redirect points.
This opener drops the credential headers when a redirect leaves the original scheme, host
and port, and refuses a redirect from https to http while a key is present. Same-origin
redirects keep the key. Nothing here logs or prints a header value.
"""

import urllib.error
import urllib.request
from typing import Any, Optional
from urllib.parse import urlsplit

CREDENTIAL_HEADERS = ("authorization", "proxy-authorization", "x-api-key", "x-goog-api-key", "api-key",
                      "x-auth-token", "cookie")
INSECURE_KEY_WARNING = "The key is sent over plain http:// to a server that is not on this computer."


def _origin(url: str) -> tuple:
    parts = urlsplit(url)
    port = parts.port or {"http": 80, "https": 443}.get(parts.scheme)
    return parts.scheme, (parts.hostname or "").lower(), port


def _credentials(headers: Any) -> list:
    return [name for name in headers if name.lower() in CREDENTIAL_HEADERS]


def insecure_key_url(url: str) -> bool:
    """True for an http:// URL that is not on this computer (a key would travel in clear text)."""
    parts = urlsplit(str(url or "").strip())
    host = (parts.hostname or "").lower()
    if parts.scheme.lower() != "http":
        return False
    return not (host in ("localhost", "::1") or host.startswith("127."))


class _KeepKeysHome(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        sent = _credentials(req.headers) + _credentials(req.unredirected_hdrs)
        new = super().redirect_request(req, fp, code, msg, headers, newurl)
        if new is None or not sent or _origin(req.full_url) == _origin(newurl):
            return new
        if urlsplit(req.full_url).scheme == "https" and urlsplit(newurl).scheme != "https":
            raise urllib.error.HTTPError(req.full_url, code, "refused a redirect from https to http while a key is sent", headers, fp)
        for table in (new.headers, new.unredirected_hdrs):
            for name in _credentials(table):
                del table[name]
        return new


def build_opener() -> urllib.request.OpenerDirector:
    return urllib.request.build_opener(_KeepKeysHome)


def urlopen(request: Any, timeout: Optional[float] = None):  # type: ignore[no-untyped-def]
    """Like urllib.request.urlopen, but redirects never carry credentials to another origin."""
    return build_opener().open(request, timeout=timeout)
