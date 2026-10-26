"""A provider's API key from KWallet, for a scheduled run (no widget, no prompt).

Same place as store/Wallet.qml: the network wallet, folder "KDEAIChat",
entry = provider id. Talks to kwalletd6 over D-Bus with ``busctl --json``
(argv lists, no shell). A wallet that is not open counts as locked: the run
is skipped (owner decision), it never asks for the wallet password.

The key only ever lives in this process's memory: it is not logged, printed,
put on a command line or written anywhere.

Overrides (tests and the dev sandbox): ``KDEAICHAT_WALLET_FOLDER`` (default
"KDEAIChat"; dev runs use "KDEAIChat-dev") and ``KDEAICHAT_BUSCTL``.
"""
import json
import os
import subprocess
from typing import Any, List

SERVICE = "org.kde.kwalletd6"
PATH = "/modules/kwalletd6"
IFACE = "org.kde.KWallet"
APP_ID = "org.kde.plasma.kdeaichat"
TIMEOUT = 25


class WalletUnavailable(Exception):
    """The wallet can't be read now: ``reason`` is "wallet locked" or "wallet unavailable"."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


def folder() -> str:
    return os.environ.get("KDEAICHAT_WALLET_FOLDER") or "KDEAIChat"


def _call(method: str, signature: str = "", *args: Any) -> Any:
    argv = [os.environ.get("KDEAICHAT_BUSCTL") or "busctl", "--user", "--json=short", f"--timeout={TIMEOUT}",
            "call", SERVICE, PATH, IFACE, method]
    if signature:
        argv += [signature] + [str(a).lower() if isinstance(a, bool) else str(a) for a in args]
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=TIMEOUT + 5)
    except (OSError, subprocess.SubprocessError):
        raise WalletUnavailable("wallet unavailable") from None
    if result.returncode != 0:
        raise WalletUnavailable("wallet unavailable")
    try:
        data: List[Any] = json.loads(result.stdout)["data"]
    except (ValueError, KeyError, TypeError):
        raise WalletUnavailable("wallet unavailable") from None
    return data[0] if data else None


def read_key(provider_id: str) -> str:
    """The stored key ("" when there is none). Raises WalletUnavailable."""
    wallet = _call("networkWallet") or "kdewallet"
    if _call("isOpen", "s", wallet) is not True:
        raise WalletUnavailable("wallet locked")
    handle = _call("open", "sxs", wallet, 0, APP_ID)
    if not isinstance(handle, int) or handle < 0:
        raise WalletUnavailable("wallet locked")
    try:
        if _call("hasEntry", "isss", handle, folder(), provider_id, APP_ID) is not True:
            return ""
        value = _call("readPassword", "isss", handle, folder(), provider_id, APP_ID)
        return value.strip() if isinstance(value, str) else ""
    finally:
        try:
            _call("close", "ibs", handle, False, APP_ID)
        except WalletUnavailable:
            pass
