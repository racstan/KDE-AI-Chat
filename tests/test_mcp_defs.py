"""Runs tests/js/mcp_defs.test.js (mcp/McpDefs.js and config/McpForm.js) in node."""
import os
import subprocess


def test_mcp_defs_and_form_logic():
    script = os.path.join(os.path.dirname(__file__), "js", "mcp_defs.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
