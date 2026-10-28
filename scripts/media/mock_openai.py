#!/usr/bin/env python3
"""A fake OpenAI-compatible server for the docs media (scripts/dev-media.sh).

Serves /v1/models and a streaming /v1/chat/completions that answers every
request with one canned markdown reply, a few words at a time, like a real
model. Binds to 127.0.0.1 only; no key is checked, nothing leaves the machine.

Usage: mock_openai.py <port>
"""
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18765
MODEL = "nova-demo"
ANSWER = """Good question! Here is a short answer.

**Rust** keeps memory safe without a garbage collector. Three ideas do the work:

- **Ownership**: every value has one owner.
- **Borrowing**: you can lend a reference, as long as it does not outlive the owner.
- **Lifetimes**: the compiler checks that for you.

```rust
let name = String::from("Nova");
let greeting = format!("Hello, {name}!");
println!("{greeting}");
```

Want me to go deeper on any of them?"""

DECLINE = """Of course. Here is a short, polite way to say no:

> Hi Sam, thank you for the invitation. I can't make this one, as my calendar is full that day. Please share the notes afterwards, and count me in next time.

Want me to go deeper on a warmer or a more formal version?"""

LIGHTHOUSE = """A lighthouse stands on a rock at dusk, its lamp just lit.

- **Sky**: a soft wash of violet fading into orange at the horizon.
- **Sea**: calm, deep blue, with a pale path of light on the water.

Want me to try a stormier version?"""

# (keyword in the last user message, reply); the first match wins, ANSWER is the default.
CANNED = [("polite no", DECLINE), ("meeting invite", DECLINE), ("decline", DECLINE), ("lighthouse", LIGHTHOUSE)]


def answer_for(request):
    last = ""
    for message in request.get("messages") or []:
        if message.get("role") == "user":
            content = message.get("content")
            if isinstance(content, list):
                content = " ".join(str(p.get("text", "")) for p in content if isinstance(p, dict))
            last = str(content or "")
    for keyword, reply in CANNED:
        if keyword in last.lower():
            return reply
    return ANSWER


def pieces(text, size=3):
    words = text.split(" ")
    for i in range(0, len(words), size):
        yield " ".join(words[i:i + size]) + (" " if i + size < len(words) else "")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def _json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self._json(200, {"object": "list", "data": [{"id": MODEL, "object": "model"}]})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        request = json.loads(self.rfile.read(length) or b"{}")
        if not self.path.rstrip("/").endswith("/chat/completions"):
            return self._json(404, {"error": "not found"})
        if not request.get("stream"):
            return self._json(200, {"id": "mock", "object": "chat.completion", "model": MODEL,
                                    "choices": [{"index": 0, "finish_reason": "stop",
                                                 "message": {"role": "assistant", "content": answer_for(request)}}],
                                    "usage": {"prompt_tokens": 80, "completion_tokens": 120, "total_tokens": 200}})
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True

        def event(delta, finish=None, usage=None):
            body = {"id": "mock", "object": "chat.completion.chunk", "model": MODEL,
                    "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            if usage:
                body["usage"] = usage
            self.wfile.write(b"data: " + json.dumps(body).encode() + b"\n\n")
            self.wfile.flush()

        try:
            event({"role": "assistant", "content": ""})
            time.sleep(0.4)
            for chunk in pieces(answer_for(request)):
                event({"content": chunk})
                time.sleep(0.04)
            event({}, "stop", {"prompt_tokens": 80, "completion_tokens": 120, "total_tokens": 200})
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        except OSError:
            pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
