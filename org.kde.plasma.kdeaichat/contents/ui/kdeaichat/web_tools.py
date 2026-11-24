"""The tool bridge's two web tools: web_search and fetch_url.

stdlib only; imported by tool_bridge_server.py by plain name (it runs with
`python -I`). Both return ``(text, is_error)``. Search keys are passed in by
the caller, used only as a request header and never logged or returned.
"""
import json
import os
import re
import ssl
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from http.client import HTTPException
from typing import List, Optional, Tuple

import http_safe
import net_guard

SEARCH_TIMEOUT = float(os.environ.get("KDEAICHAT_TOOL_SEARCH_TIMEOUT", 20))
FETCH_TIMEOUT = float(os.environ.get("KDEAICHAT_TOOL_FETCH_TIMEOUT", 20))
MAX_DOWNLOAD = 2 * 1024 * 1024
MAX_SEARCH_RESPONSE = 2 * 1024 * 1024
DEFAULT_CHARS = 50000
MAX_CHARS = 100000
MAX_REDIRECTS = 5
USER_AGENT = "Mozilla/5.0 (compatible; KDE-AI-Chat)"
PROVIDERS = ("searxng", "brave", "tavily")
BRAVE_URL = "https://api.search.brave.com/res/v1/web/search"
TAVILY_URL = "https://api.tavily.com/search"

Result = Tuple[str, bool]


def _checked_url(url: str) -> Optional[str]:
    """None if ``url`` is an acceptable http(s) link without credentials, else the reason."""
    if not url or len(url) > 4096 or re.search(r"[\x00-\x20\x7f]", url):
        return "the link is empty, too long or has spaces"
    try:
        parts = urllib.parse.urlsplit(url)
        parts.port  # noqa: B018 (raises on a bad port)
    except ValueError:
        return "the link is not valid"
    if parts.scheme not in ("http", "https") or not parts.hostname:
        return "only http and https links are allowed"
    if parts.username is not None or parts.password is not None:
        return "links with a user name or password are not allowed"
    return None


# --- Search -------------------------------------------------------------------------

def _clip(text: object, limit: int) -> str:
    value = re.sub(r"\s+", " ", str(text or "")).strip()
    return value if len(value) <= limit else value[:limit - 1] + "..."


def _format_results(items: List[dict], count: int) -> Result:
    lines: List[str] = []
    found = 0
    for item in items[:count]:
        if not isinstance(item, dict) or not item.get("url"):
            continue
        found += 1
        lines.append(f"{found}. {_clip(item.get('title'), 200) or item['url']}\n   {item['url']}")
        snippet = _clip(item.get("snippet"), 500)
        if snippet:
            lines.append("   " + snippet)
    return ("\n".join(lines), False) if lines else ("No results.", False)


def _read_json(request: urllib.request.Request) -> object:
    with http_safe.urlopen(request, timeout=SEARCH_TIMEOUT) as response:
        data = response.read(MAX_SEARCH_RESPONSE + 1)
    if len(data) > MAX_SEARCH_RESPONSE:
        raise ValueError("the search answer is too large")
    return json.loads(data.decode("utf-8", "replace"))


def _entries(data: object, *path: str) -> list:
    for name in path:
        data = data.get(name) if isinstance(data, dict) else None
    return data if isinstance(data, list) else []


def web_search(provider: str, query: str, count: object = 5, searxng_url: str = "", key: str = "") -> Result:
    query = str(query or "").strip()
    if not query:
        return "The search needs a query.", True
    try:
        count = max(1, min(10, int(count)))
    except (TypeError, ValueError):
        count = 5
    try:
        if provider == "searxng":
            reason = _checked_url(searxng_url)
            if reason:
                return "The SearXNG address is not usable: " + reason + ".", True
            url = searxng_url.rstrip("/") + "/search?" + urllib.parse.urlencode({"q": query, "format": "json"})
            data = _read_json(urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": USER_AGENT}))
            items = [{"title": r.get("title"), "url": r.get("url"), "snippet": r.get("content")}
                     for r in _entries(data, "results") if isinstance(r, dict)]
        elif provider == "brave":
            url = BRAVE_URL + "?" + urllib.parse.urlencode({"q": query, "count": count})
            data = _read_json(urllib.request.Request(url, headers={
                "Accept": "application/json", "X-Subscription-Token": key, "User-Agent": USER_AGENT}))
            items = [{"title": r.get("title"), "url": r.get("url"), "snippet": r.get("description")}
                     for r in _entries(data, "web", "results") if isinstance(r, dict)]
        elif provider == "tavily":
            body = json.dumps({"query": query, "max_results": count}).encode()
            data = _read_json(urllib.request.Request(TAVILY_URL, data=body, method="POST", headers={
                "Content-Type": "application/json", "Authorization": "Bearer " + key, "User-Agent": USER_AGENT}))
            items = [{"title": r.get("title"), "url": r.get("url"), "snippet": r.get("content")}
                     for r in _entries(data, "results") if isinstance(r, dict)]
        else:
            return "No search service is set up.", True
    except urllib.error.HTTPError as exc:
        hint = " (the API key was refused)" if exc.code in (401, 403) else ""
        return f"The search failed: HTTP {exc.code}{hint}.", True
    except (OSError, HTTPException, ValueError) as exc:
        message = _clip(getattr(exc, "reason", exc), 200)
        return "The search failed: " + (message.replace(key, "***") if key else message) + ".", True
    return _format_results(items, count)


# --- Fetch --------------------------------------------------------------------------

class _CheckedRedirects(urllib.request.HTTPRedirectHandler):
    """At most MAX_REDIRECTS hops; each must be an acceptable link (the connection checks its address)."""
    max_redirections = MAX_REDIRECTS

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        target = urllib.parse.urljoin(req.full_url, newurl)
        if _checked_url(target):
            raise urllib.error.HTTPError(req.full_url, code, "refused a redirect to a link that is not allowed", headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, target)


def _open_url(url: str):  # type: ignore[no-untyped-def]
    # Only the guarded handlers (no proxies, ftp or file): every hop connects to a public address only.
    opener = urllib.request.OpenerDirector()
    for handler in (net_guard.GuardedHTTPHandler(), net_guard.GuardedHTTPSHandler(context=ssl.create_default_context()),
                    _CheckedRedirects(), urllib.request.HTTPDefaultErrorHandler(), urllib.request.HTTPErrorProcessor(),
                    urllib.request.UnknownHandler()):
        opener.add_handler(handler)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "text/html,text/plain,application/json;q=0.9,*/*;q=0.5"})
    return opener.open(request, timeout=FETCH_TIMEOUT)


SKIPPED = {"script", "style", "nav", "noscript", "svg", "template", "iframe"}
DOUBLE = {"p", "ul", "ol", "table", "blockquote", "pre", "h1", "h2", "h3", "h4", "h5", "h6"}
SINGLE = {"div", "section", "article", "main", "header", "footer", "aside", "tr", "br", "hr", "form", "figure", "figcaption",
          "dl", "dt", "dd", "li"}


class _TextExtractor(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: List[str] = []
        self.title = ""
        self._skip = 0
        self._in_title = False
        self._trail = 0  # line breaks at the end of what has been written

    def _break(self, count: int) -> None:
        self.parts.append("\n" * max(0, count - self._trail))
        self._trail = max(self._trail, count)

    def handle_starttag(self, tag, attrs):  # type: ignore[no-untyped-def]
        if tag in SKIPPED:
            self._skip += 1
        elif tag == "title":
            self._in_title = True
        elif not self._skip and (tag in DOUBLE or tag in SINGLE):
            self._break(2 if tag in DOUBLE else 1)
            prefix = "- " if tag == "li" else "#" * int(tag[1]) + " " if tag in DOUBLE and tag[0] == "h" else ""
            if prefix:
                self.parts.append(prefix)
                self._trail = 0

    def handle_endtag(self, tag):  # type: ignore[no-untyped-def]
        if tag in SKIPPED:
            self._skip = max(0, self._skip - 1)
        elif tag == "title":
            self._in_title = False
        elif not self._skip and (tag in DOUBLE or tag in SINGLE):
            self._break(2 if tag in DOUBLE else 1)

    def handle_data(self, data):  # type: ignore[no-untyped-def]
        data = re.sub(r"\s+", " ", data)
        if self._in_title:
            self.title += data
        elif not self._skip and data:
            self.parts.append(data)
            if data.strip():
                self._trail = 0


def html_to_text(markup: str) -> str:
    parser = _TextExtractor()
    try:
        parser.feed(markup)
        parser.close()
    except Exception:  # noqa: BLE001  (html.parser can fail on odd input: keep what was read)
        pass
    text = "".join(parser.parts)
    lines = [re.sub(r"[ \t\r\f\v\xa0]+", " ", line).strip() for line in text.split("\n")]
    body = re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()
    title = re.sub(r"\s+", " ", parser.title).strip()
    return (title + "\n\n" + body).strip() if title else body


def fetch_url(url: str, max_chars: object = None) -> Result:
    url = str(url or "").strip()
    reason = _checked_url(url)
    if reason:
        return "Can't fetch that link: " + reason + ".", True
    try:
        limit = max(500, min(MAX_CHARS, int(max_chars))) if max_chars is not None else DEFAULT_CHARS
    except (TypeError, ValueError):
        limit = DEFAULT_CHARS
    try:
        with _open_url(url) as response:
            content_type = (response.headers.get("Content-Type") or "").split(";")[0].strip().lower()
            charset = response.headers.get_content_charset() or "utf-8"
            data = response.read(MAX_DOWNLOAD + 1)
    except urllib.error.HTTPError as exc:
        return f"The page answered with HTTP {exc.code}.", True
    except ValueError as exc:
        return "Refused: " + _clip(exc, 200) + " (only public internet addresses can be fetched).", True
    except (OSError, HTTPException) as exc:
        return "Could not fetch the page: " + _clip(getattr(exc, "reason", exc), 200) + ".", True
    cut = len(data) > MAX_DOWNLOAD
    data = data[:MAX_DOWNLOAD]
    textual = (not content_type or content_type.startswith("text/") or content_type in ("application/json", "application/xhtml+xml")
               or content_type.endswith("+json"))
    if not textual:
        return "Unsupported content type: " + (content_type or "unknown") + ".", True
    try:
        text = data.decode(charset, "replace")
    except LookupError:
        text = data.decode("utf-8", "replace")
    if content_type in ("text/html", "application/xhtml+xml") or (not content_type and re.match(r"\s*<(!doctype|html)", text, re.I)):
        text = html_to_text(text)
    if len(text) > limit:
        text, cut = text[:limit], True
    return (text + "\n\n[truncated]" if cut else text), False
