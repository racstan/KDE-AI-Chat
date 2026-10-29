#!/usr/bin/env python3
"""A tiny stdio MCP server for tests: tools echo, boom (isError), slow (sleeps), big (50 kB), crash (exits).

Two pages of tools/list (cursor "p2") prove the bridge follows nextCursor.
With KDEAICHAT_FAKE_MCP_LOG set, each start appends the pid to that file.
"""
import json
import os
import sys
import time

TOOL = {"type": "object", "properties": {"text": {"type": "string"}}}
PAGES = {None: ([{"name": "echo", "description": "Echo", "inputSchema": TOOL},
                 {"name": "boom", "description": "Fails", "inputSchema": TOOL}], "p2"),
         "p2": ([{"name": "slow", "description": "Slow", "inputSchema": TOOL},
                 {"name": "big", "description": "Big", "inputSchema": TOOL},
                 {"name": "crash", "description": "Exits", "inputSchema": TOOL}], None)}


def reply(rid, result):
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": rid, "result": result}) + "\n")
    sys.stdout.flush()


def main():
    if os.environ.get("KDEAICHAT_FAKE_MCP_LOG"):
        with open(os.environ["KDEAICHAT_FAKE_MCP_LOG"], "a") as f:
            f.write(f"{os.getpid()} {os.environ.get('FAKE_SECRET', '')}\n")
    for line in sys.stdin:
        msg = json.loads(line)
        method, rid, params = msg.get("method"), msg.get("id"), msg.get("params") or {}
        if method == "initialize":
            reply(rid, {"protocolVersion": params.get("protocolVersion"), "capabilities": {"tools": {}},
                        "serverInfo": {"name": "fake", "version": "0"}})
        elif method == "tools/list":
            tools, nxt = PAGES[params.get("cursor")]
            reply(rid, {"tools": tools, **({"nextCursor": nxt} if nxt else {})})
        elif method == "tools/call":
            name, args = params["name"], params.get("arguments") or {}
            if name == "echo":
                reply(rid, {"content": [{"type": "text", "text": "echo: " + str(args.get("text", ""))},
                                        {"type": "image", "data": "AAAA", "mimeType": "image/png"}]})
            elif name == "boom":
                reply(rid, {"content": [{"type": "text", "text": "it broke"}], "isError": True})
            elif name == "slow":
                time.sleep(5)
                reply(rid, {"content": [{"type": "text", "text": "late"}]})
            elif name == "big":
                reply(rid, {"content": [{"type": "text", "text": "x" * 50000}]})
            elif name == "crash":
                os._exit(3)


main()
