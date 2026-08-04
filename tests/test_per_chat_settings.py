"""Regression tests for per-chat settings (on-the-fly provider/model switching and per-chat memory)."""

import json
import os
import re
import subprocess
import tempfile

UI_DIR = os.path.join(
    os.path.dirname(__file__),
    "..",
    "org.kde.plasma.kdeaichat",
    "contents",
    "ui",
)
CHAT_ENGINE = os.path.join(UI_DIR, "ChatEngine.js")
PROVIDER_SERVICE = os.path.join(UI_DIR, "ProviderService.js")
SESSION_MANAGER = os.path.join(UI_DIR, "SessionManager.js")


def _read_js(path):
    with open(path, encoding="utf-8") as f:
        return re.sub(r"^\s*\.pragma\s+library\s*\n", "", f.read(), count=1)


def test_per_chat_provider_and_model_resolution():
    engine_src = _read_js(CHAT_ENGINE)
    provider_src = _read_js(PROVIDER_SERVICE)
    session_src = _read_js(SESSION_MANAGER)

    harness = (
        "var ProviderService = (function() {\n"
        + provider_src
        + "\nreturn { getProviderConfig: getProviderConfig, getSupportedProviders: getSupportedProviders };\n})();\n"
        + session_src
        + """
        var root = {
            currentSessionId: "s-12345",
            sessions: [
                {
                    value: "s-12345",
                    text: "Chat A",
                    chatProvider: "anthropic",
                    chatModel: "claude-3-5-sonnet",
                    chatMemory: "User likes Python"
                }
            ],
            plasmoid: {
                configuration: {
                    provider: "openai",
                    model: "gpt-4o",
                    anthropicApiKey: "test-anthropic-key"
                }
            }
        };
        var plasmoid = root.plasmoid;
        """
        + engine_src
        + """
        var effProvider = getEffectiveProvider("s-12345");
        var effModel = getEffectiveModel("s-12345");
        var cfg = getProviderConfig(effProvider, "s-12345");
        var memInjected = injectMemoriesToUserMessage("Hello", "s-12345");

        console.log(JSON.stringify({
            effProvider: effProvider,
            effModel: effModel,
            cfgModel: cfg.model,
            cfgType: cfg.type,
            memInjected: memInjected
        }));
        """
    )

    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as script:
        script.write(harness)
        script_path = script.name

    try:
        result = subprocess.run(
            ["node", script_path],
            capture_output=True,
            check=True,
            text=True,
            timeout=10,
        )
        data = json.loads(result.stdout)
        assert data["effProvider"] == "anthropic"
        assert data["effModel"] == "claude-3-5-sonnet"
        assert data["cfgModel"] == "claude-3-5-sonnet"
        assert data["cfgType"] == "anthropic"
        assert "User likes Python" in data["memInjected"]
    finally:
        os.unlink(script_path)


def test_per_chat_fallback_to_global_defaults():
    engine_src = _read_js(CHAT_ENGINE)
    provider_src = _read_js(PROVIDER_SERVICE)
    session_src = _read_js(SESSION_MANAGER)

    harness = (
        "var ProviderService = (function() {\n"
        + provider_src
        + "\nreturn { getProviderConfig: getProviderConfig, getSupportedProviders: getSupportedProviders };\n})();\n"
        + session_src
        + """
        var root = {
            currentSessionId: "s-67890",
            sessions: [
                {
                    value: "s-67890",
                    text: "Chat B"
                }
            ],
            plasmoid: {
                configuration: {
                    provider: "groq",
                    groqModel: "llama-3.3-70b-versatile",
                    groqApiKey: "test-groq-key"
                }
            }
        };
        var plasmoid = root.plasmoid;
        """
        + engine_src
        + """
        var effProvider = getEffectiveProvider("s-67890");
        var effModel = getEffectiveModel("s-67890");
        var cfg = getProviderConfig(effProvider, "s-67890");

        console.log(JSON.stringify({
            effProvider: effProvider,
            effModel: effModel,
            cfgModel: cfg.model
        }));
        """
    )

    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as script:
        script.write(harness)
        script_path = script.name

    try:
        result = subprocess.run(
            ["node", script_path],
            capture_output=True,
            check=True,
            text=True,
            timeout=10,
        )
        data = json.loads(result.stdout)
        assert data["effProvider"] == "groq"
        assert data["effModel"] == "llama-3.3-70b-versatile"
        assert data["cfgModel"] == "llama-3.3-70b-versatile"
    finally:
        os.unlink(script_path)
