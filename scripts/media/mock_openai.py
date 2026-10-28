#!/usr/bin/env python3
"""A fake OpenAI-compatible server for the docs media (scripts/dev-media.sh).

Serves /v1/models and a streaming /v1/chat/completions that answers every
request with one canned markdown reply, a few words at a time, like a real
model. Binds to 127.0.0.1 only; no key is checked, nothing leaves the machine.

Usage: mock_openai.py <port>
"""
import json
import re
import sys
import os
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

BRIEFING = """Good morning, Alex. Here is your briefing.

- **Weather in Lisbon**: sunny, 22 degrees, a light breeze from the sea.
- **Today**: stand-up at 10:00, and the invoice for Sam is due on the 17th.
- **Worth knowing**: the Rust study group meets tonight."""

HELLO = """Hi! I can help with almost anything you type here:

- **Questions**: explain a topic, compare options, check a fact.
- **Writing**: emails, summaries, translations.
- **Code**: write, explain or fix a small program.

Just ask, and press Enter."""

PERSONA = """Hi Alex! I'm Nova, your assistant in the panel. I keep things friendly and short.

Ask me anything, and I'll answer in my own picture's company."""

BUDGET = """We settled on **600 euros** for the three days in Lisbon:

- Hotel: about 250
- Food: about 200
- Trains and tickets: about 150

Want me to turn that into a packing and booking list?"""

# The schedule editor's "Describe when" (config/ScheduleDescribe.js): its system prompt asks for JSON rules only.
RULES = '{"rules":[{"kind":"weekly","days":[1,2,3,4,5],"times":["08:30"]},{"kind":"weekly","days":[0],"times":["12:00"]}]}'

# The video's chat chapters (scripts/media/VideoChat*.qml) ask these.
STORY = """Once upon a time a lighthouse keeper named Mira lived on a quiet rock far out at sea.

Every evening she climbed the 112 steps, lit the great lamp and watched the ships go by. One foggy night a tiny boat lost its way, and only her light led it safely home.

The next morning the sailor left a loaf of warm bread on her doorstep, and from then on she was never lonely again.

The end. Shall I write a second chapter?"""

COMPARE = """Here is a comparison of the three modes.

| Mode | Talks to | Good for |
|---|---|---|
| Direct | any provider over HTTP | quick questions |
| OpenCode | a local OpenCode server | coding in a folder |
| Pi | the Pi agent | small agent tasks |

A tiny example of the direct request:

```python
import json, urllib.request

body = {"model": "nova-demo", "stream": True,
        "messages": [{"role": "user", "content": "Hello"}]}
```

Things to remember:

- Pick the mode once per chat.
- A chat keeps its mode.
- Your keys stay in KWallet."""

EXAMPLE = """Sure. Here is a tiny example:

```rust
static GREETING: &str = "Hello, Nova!";

fn main() {
    println!("{GREETING}");
}
```

`GREETING` lives for the whole program, so it is `'static`."""

SUMMARY = """- Rust checks every reference at compile time.
- Ownership means each value has exactly one owner.
- Borrowing lends values out without copying them."""

# The attachment step sends the project's real docs/voice.md and a real photo (scripts/media/lisbon-tram.jpg,
# public domain, see scripts/media/CREDITS.md); this reply says what they really contain.
ATTACHED = """From the **voice guide** you attached:

1. Install **Speech Note** (from Flathub) and open it once to download a voice.
2. In the widget's **Settings → Voice**, switch on **Read aloud** and **Offer to read replies aloud**.
3. A speaker button then shows under each reply. **Ctrl+Shift+S** reads the last reply, and again stops it.

Your **photo** shows a red Lisbon tram on route 28, climbing a narrow cobbled street between yellow and grey houses, with iron balconies and street lamps above. A lovely shot of the city!"""

PICTURE = """That is a white lighthouse on a rocky headland at dusk. The sky fades from violet to orange and the setting sun lays a path of light across the sea."""

CONTINUE = """Got it, you picked **{choice}**. Here is the summary in that style:

{text}"""

TAGLINES = ["Fresh bread, baked with love every morning.", "Warm from the oven, close to your door.",
            "Small bakery, big flavour, made by hand."]
SHORT_SUMMARY = "Rust keeps memory safe with ownership, borrowing and lifetimes."
DETAILED_SUMMARY = "Rust gives each value one owner, lets you borrow it with references the compiler checks, and uses lifetimes to make sure no reference outlives its value. That is how it avoids a garbage collector."

# (keyword in the last user message, reply); the first match wins, ANSWER is the default.
CANNED = [("short briefing", BRIEFING), ("can you help", HELLO), ("who you are", PERSONA), ("trip budget", BUDGET),
          ("bedtime story", STORY), ("compare", COMPARE), ("show an example", EXAMPLE), ("summarize the following", SUMMARY),
          ("polite no", DECLINE), ("meeting invite", DECLINE), ("decline", DECLINE), ("lighthouse", LIGHTHOUSE)]
SLOW = ("bedtime story",)      # streamed slowly, so there is time to stop it or queue another message
counter = {"tagline": 0}


MEMORY_HEADING = "## Things the user asked you to remember"


def last_user(request):
    last = ""
    for message in request.get("messages") or []:
        if message.get("role") == "user":
            content = message.get("content")
            if isinstance(content, list):
                content = " ".join(str(p.get("text", "")) for p in content if isinstance(p, dict) and p.get("type") != "image_url")
            last = str(content or "")
    # Memories go before the message (chat/Memory.qml withMemories): only the message itself picks the reply.
    if last.startswith(MEMORY_HEADING) and "\n\n---\n\n" in last:
        last = last.split("\n\n---\n\n", 1)[1]
    return last


def has_image(request):
    last = None
    for message in request.get("messages") or []:
        if message.get("role") == "user":
            last = message
    content = last.get("content") if last else None
    return isinstance(content, list) and any(isinstance(p, dict) and p.get("type") == "image_url" for p in content)


def asks_user(request):
    """A tool call for ask_user when the request offers it and the user said "ask me"."""
    messages = request.get("messages") or []
    if not messages or messages[-1].get("role") != "user" or "ask me" not in last_user(request).lower():
        return None
    for tool in request.get("tools") or []:
        if "ask_user" in json.dumps(tool):
            return {"question": "Which style should the summary have?", "options": ["Short", "Detailed"], "allow_typed": True}
    return None


def answer_for(request):
    messages = request.get("messages") or []
    for message in messages:
        if message.get("role") == "system" and "convert a description of WHEN" in str(message.get("content")):
            # "every day at 10:42" (the video's schedule, due at once) -> that daily rule; else RULES.
            at = re.search(r"\b(\d{1,2}):(\d{2})\b", last_user(request))
            if at:
                return json.dumps({"rules": [{"kind": "daily", "times": ["%02d:%s" % (int(at.group(1)), at.group(2))], "everyDays": 1}]})
            return RULES
    if messages and messages[-1].get("role") == "tool":
        choice = str(messages[-1].get("content") or "").strip().strip('"')
        return CONTINUE.format(choice=choice, text=SHORT_SUMMARY if "short" in choice.lower() else DETAILED_SUMMARY)
    if has_image(request):
        return ATTACHED if "voice guide" in last_user(request).lower() else PICTURE
    last = last_user(request)
    if "tagline" in last.lower():
        counter["tagline"] += 1
        return TAGLINES[(counter["tagline"] - 1) % len(TAGLINES)]
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
        elif self.path.startswith("/img/"):
            # The picture /image gets (the video's tour points the image service's address here): one that
            # Pollinations really made for this prompt (scripts/media/CREDITS.md).
            with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "generated-lighthouse.jpg"), "rb") as f:
                data = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "image/jpeg")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
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
            call = asks_user(request)
            if call:
                event({"tool_calls": [{"index": 0, "id": "call_ask_1", "type": "function",
                                       "function": {"name": "ask_user", "arguments": json.dumps(call)}}]})
                event({}, "tool_calls", {"prompt_tokens": 80, "completion_tokens": 20, "total_tokens": 100})
                self.wfile.write(b"data: [DONE]\n\n")
                self.wfile.flush()
                return
            slow = any(k in last_user(request).lower() for k in SLOW)
            for chunk in pieces(answer_for(request), 2 if slow else 3):
                event({"content": chunk})
                time.sleep(0.16 if slow else 0.04)
            event({}, "stop", {"prompt_tokens": 80, "completion_tokens": 120, "total_tokens": 200})
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        except OSError:
            pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
