#!/usr/bin/env python3
"""A fake stdio MCP server (newline-delimited JSON-RPC) for the tool bridge tests.

Tools: echo, fail, big, image, structured, slow, crash, pid, env, "odd name.v2" (a name that needs sanitising).
tools/list pages hold FAKE_MCP_PAGE tools (default 2) and use the cursor "next:<n>".
FAKE_MCP_LOG (a file): "start <pid>", and "client-reply <json>" for the answer to the server's own request.
"""
import json
import os
import sys
import time

TOOLS = [
    ("echo", "Echoes text back"), ("fail", "Always fails"), ("big", "A very long answer"), ("image", "An image"),
    ("structured", "Structured only"), ("slow", "Sleeps"), ("crash", "Exits at once"), ("pid", "The process id"),
    ("env", "Reads FAKE_MCP_VAR"), ("odd name.v2", "Needs a safe name"),
]
LOG = os.environ.get("FAKE_MCP_LOG")


def log(line):
    if LOG:
        with open(LOG, "a") as f:
            f.write(line + "\n")


def send(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


def text(value, error=False):
    return {"content": [{"type": "text", "text": value}], "isError": error}


def call(name, args):
    if name == "echo":
        return text("echo: " + str(args.get("text", "")))
    if name == "fail":
        return text("boom", True)
    if name == "big":
        return text("x" * int(args.get("size", 200000)))
    if name == "image":
        return {"content": [{"type": "text", "text": "here"}, {"type": "image", "mimeType": "image/png", "data": "A" * 16384}]}
    if name == "structured":
        return {"content": [], "structuredContent": {"a": 1}}
    if name == "slow":
        time.sleep(float(args.get("seconds", 5)))
        return text("done")
    if name == "crash":
        os._exit(3)
    if name == "pid":
        return text(str(os.getpid()))
    if name == "env":
        return text(os.environ.get("FAKE_MCP_VAR", ""))
    return text("called " + name)


log("start %d" % os.getpid())
page = int(os.environ.get("FAKE_MCP_PAGE", 2))
for line in sys.stdin:
    try:
        msg = json.loads(line)
    except ValueError:
        continue
    method, rid = msg.get("method"), msg.get("id")
    if method is None:
        log("client-reply " + json.dumps(msg))
        continue
    if rid is None:
        continue
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": rid, "result": {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                                                       "serverInfo": {"name": "fake", "version": "1"}}})
        send({"jsonrpc": "2.0", "id": "srv-1", "method": "roots/list"})
    elif method == "tools/list":
        start = int((msg.get("params") or {}).get("cursor", "next:0").split(":")[1])
        chunk = TOOLS[start:start + page]
        result = {"tools": [{"name": n, "description": d, "inputSchema": {"type": "object", "properties": {"text": {"type": "string"}}}} for n, d in chunk]}
        if start + page < len(TOOLS):
            result["nextCursor"] = "next:%d" % (start + page)
        send({"jsonrpc": "2.0", "id": rid, "result": result})
    elif method == "tools/call":
        params = msg.get("params") or {}
        send({"jsonrpc": "2.0", "id": rid, "result": call(params.get("name"), params.get("arguments") or {})})
    else:
        send({"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "unknown method"}})
