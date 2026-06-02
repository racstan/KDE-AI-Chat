#!/usr/bin/env python3
"""
kde-ai-kwallet.py — KWallet helper for KDE AI Chat
Replaces shell-built qdbus commands with safe subprocess args-list calls.
Outputs JSON to stdout for QML DataSource parsing.
"""

import json
import os
import re
import subprocess
import sys

WALLET_SERVICE = "org.kde.kwalletd6"
WALLET_PATH = "/modules/kwalletd6"
WALLET_IFACE = "org.kde.KWallet"
FOLDER = "KaiChat"
APP_ID = "org.kde.plasma.kdeaichat"

_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

def _load_provider_ids():
    path = os.path.join(_SCRIPT_DIR, "ProviderData.js")
    if not os.path.exists(path):
        return ["openai", "anthropic"]
    with open(path, "r") as f:
        content = f.read()
    return re.findall(r'\{\s*id\s*:\s*"([^"]+)"', content)

PROVIDER_IDS = _load_provider_ids()


def qdbus(*args):
    try:
        result = subprocess.run(
            ["qdbus6", *args],
            capture_output=True, text=True, check=False, timeout=15,
        )
        if result.returncode == 0:
            return result.stdout.strip()
        result = subprocess.run(
            ["qdbus", *args],
            capture_output=True, text=True, check=False, timeout=15,
        )
        if result.returncode == 0:
            return result.stdout.strip()
        return None
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None


def find_qdbus():
    try:
        subprocess.run(["qdbus6", "--help"], capture_output=True, check=True, timeout=5)
        return "qdbus6"
    except (FileNotFoundError, subprocess.TimeoutExpired):
        try:
            subprocess.run(["qdbus", "--help"], capture_output=True, check=True, timeout=5)
            return "qdbus"
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return None


def cmd_wallets():
    out = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.wallets")
    if out is None:
        return {"status": "error", "message": "qdbus6 not available"}
    wallets = [w.strip() for w in out.splitlines() if w.strip()]
    return {"status": "ok", "wallets": wallets}


def cmd_read(wallet, key):
    handle = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.open", wallet, "0", APP_ID)
    if handle is None or not handle.strip():
        return {"status": "error", "message": "open_failed", "wallet": wallet, "key": key}
    handle = handle.strip().splitlines()[-1]
    try:
        int(handle)
    except ValueError:
        return {"status": "error", "message": "invalid_handle", "wallet": wallet, "key": key}
    has = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.hasFolder", handle, FOLDER, APP_ID)
    if has != "true":
        qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.close", handle, "false", APP_ID)
        return {"status": "error", "message": "no_folder", "wallet": wallet, "key": key}
    secret = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.readPassword", handle, FOLDER, key, APP_ID)
    qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.close", handle, "false", APP_ID)
    if secret is None:
        return {"status": "error", "message": "no_entry", "wallet": wallet, "key": key}
    return {"status": "ok", "wallet": wallet, "key": key, "value": secret}


def cmd_write(wallet, key, value):
    handle = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.open", wallet, "0", APP_ID)
    if handle is None or not handle.strip():
        return {"status": "error", "message": "open_failed", "wallet": wallet, "key": key}
    handle = handle.strip().splitlines()[-1]
    try:
        int(handle)
    except ValueError:
        return {"status": "error", "message": "invalid_handle", "wallet": wallet, "key": key}
    has = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.hasFolder", handle, FOLDER, APP_ID)
    if has != "true":
        qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.createFolder", handle, FOLDER, APP_ID)
    result = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.writePassword", handle, FOLDER, key, value, APP_ID)
    qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.close", handle, "false", APP_ID)
    if result is None or result.strip() != "0":
        return {"status": "error", "message": "write_failed", "wallet": wallet, "key": key}
    return {"status": "ok", "wallet": wallet, "key": key}


def cmd_init(wallet):
    handle = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.open", wallet, "0", APP_ID)
    if handle is None or not handle.strip():
        return {"status": "error", "message": "open_failed", "wallet": wallet}
    handle = handle.strip().splitlines()[-1]
    try:
        int(handle)
    except ValueError:
        return {"status": "error", "message": "invalid_handle", "wallet": wallet}
    has = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.hasFolder", handle, FOLDER, APP_ID)
    if has == "true":
        result_msg = "ready"
    else:
        created = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.createFolder", handle, FOLDER, APP_ID)
        result_msg = "created" if created == "true" else "create_failed"
    qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.close", handle, "false", APP_ID)
    return {"status": "ok", "wallet": wallet, "message": result_msg}


def cmd_status(wallet):
    out = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.wallets")
    if out is None:
        return {"status": "error", "message": "qdbus_not_available", "wallet": wallet}
    wallets = [w.strip() for w in out.splitlines() if w.strip()]
    if wallet not in wallets:
        return {"status": "ok", "wallet": wallet, "message": "no_wallet", "available": wallets}
    handle = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.open", wallet, "0", APP_ID)
    if handle is None or not handle.strip():
        return {"status": "error", "message": "open_failed", "wallet": wallet, "available": wallets}
    handle = handle.strip().splitlines()[-1]
    try:
        int(handle)
    except ValueError:
        return {"status": "error", "message": "invalid_handle", "wallet": wallet, "available": wallets}
    has = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.hasFolder", handle, FOLDER, APP_ID)
    qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.close", handle, "false", APP_ID)
    if has == "true":
        return {"status": "ok", "wallet": wallet, "message": "ready", "available": wallets}
    return {"status": "ok", "wallet": wallet, "message": "no_folder", "available": wallets}


def cmd_bulk_read(wallet):
    handle = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.open", wallet, "0", APP_ID)
    if handle is None or not handle.strip():
        return {"status": "error", "message": "open_failed", "wallet": wallet}
    handle = handle.strip().splitlines()[-1]
    try:
        int(handle)
    except ValueError:
        return {"status": "error", "message": "invalid_handle", "wallet": wallet}
    has = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.hasFolder", handle, FOLDER, APP_ID)
    if has != "true":
        qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.close", handle, "false", APP_ID)
        return {"status": "error", "message": "no_folder", "wallet": wallet}
    secrets = {}
    for pid in PROVIDER_IDS:
        key = f"kai-chat-{pid}-api-key"
        has_entry = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.hasEntry", handle, FOLDER, key, APP_ID)
        if has_entry == "true":
            secret = qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.readPassword", handle, FOLDER, key, APP_ID)
            if secret is not None:
                secrets[pid] = secret
    qdbus(WALLET_SERVICE, WALLET_PATH, f"{WALLET_IFACE}.close", handle, "false", APP_ID)
    return {"status": "ok", "wallet": wallet, "secrets": secrets}


def main():
    if len(sys.argv) < 2:
        print(json.dumps({"status": "error", "message": "Usage: kde-ai-kwallet.py <command> [args...]"}))
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "find":
        found = find_qdbus()
        print(json.dumps({"status": "ok" if found else "error", "qdbus": found}))
    elif cmd == "wallets":
        print(json.dumps(cmd_wallets()))
    elif cmd == "read":
        if len(sys.argv) < 4:
            print(json.dumps({"status": "error", "message": "Usage: read <wallet> <key>"}))
            sys.exit(1)
        print(json.dumps(cmd_read(sys.argv[2], sys.argv[3])))
    elif cmd == "write":
        if len(sys.argv) < 5:
            print(json.dumps({"status": "error", "message": "Usage: write <wallet> <key> <value>"}))
            sys.exit(1)
        print(json.dumps(cmd_write(sys.argv[2], sys.argv[3], sys.argv[4])))
    elif cmd == "init":
        if len(sys.argv) < 3:
            print(json.dumps({"status": "error", "message": "Usage: init <wallet>"}))
            sys.exit(1)
        print(json.dumps(cmd_init(sys.argv[2])))
    elif cmd == "status":
        if len(sys.argv) < 3:
            print(json.dumps({"status": "error", "message": "Usage: status <wallet>"}))
            sys.exit(1)
        print(json.dumps(cmd_status(sys.argv[2])))
    elif cmd == "bulk-read":
        if len(sys.argv) < 3:
            print(json.dumps({"status": "error", "message": "Usage: bulk-read <wallet>"}))
            sys.exit(1)
        print(json.dumps(cmd_bulk_read(sys.argv[2])))
    else:
        print(json.dumps({"status": "error", "message": f"Unknown command: {cmd}"}))
        sys.exit(1)


if __name__ == "__main__":
    main()
