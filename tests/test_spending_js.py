"""Runs tests/js/spending.test.js (chat/Spending.js: budgets, helper replies, provider lines, day bars) in node."""
import os
import subprocess


def test_spending_js():
    script = os.path.join(os.path.dirname(__file__), "js", "spending.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
