"""Runs tests/js/agent_events.test.js (backends/AgentEvents.js) in node."""
import os
import subprocess


def test_agent_events():
    script = os.path.join(os.path.dirname(__file__), "js", "agent_events.test.js")
    result = subprocess.run(["node", script], capture_output=True, text=True, timeout=60)
    assert result.returncode == 0, result.stdout + result.stderr
