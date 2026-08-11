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
MAIN_QML = os.path.join(UI_DIR, "main.qml")
CHAT_SETTINGS_DIALOG = os.path.join(UI_DIR, "ChatSettingsDialog.qml")


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


def test_direct_provider_registry_includes_maritaca_and_perplexity():
    """Keep the direct-mode provider registry and endpoint defaults aligned."""
    provider_src = _read_js(PROVIDER_SERVICE)
    harness = (
        provider_src
        + """
        var configuration = {
            maritacaApiKey: "maritaca-test-key",
            perplexityApiKey: "perplexity-test-key"
        };
        var maritaca = getProviderConfig("maritaca", configuration);
        var perplexity = getProviderConfig("perplexity", configuration);
        console.log(JSON.stringify({
            maritaca: maritaca,
            perplexity: perplexity,
            maritacaKey: getApiKeyConfigKey("maritaca"),
            perplexityKey: getApiKeyConfigKey("perplexity")
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
        assert data["maritaca"]["type"] == "openai-compat"
        assert data["maritaca"]["baseUrl"] == "https://chat.maritaca.ai/api"
        assert data["maritaca"]["model"] == ""
        assert data["perplexity"]["type"] == "openai-compat"
        assert data["perplexity"]["baseUrl"] == "https://api.perplexity.ai/router/v1"
        assert data["perplexity"]["model"] == ""
        assert data["maritacaKey"] == "maritacaApiKey"
        assert data["perplexityKey"] == "perplexityApiKey"
    finally:
        os.unlink(script_path)


def test_per_chat_settings_save_is_atomic_and_callbacks_are_scoped():
    """Protect the dialog from model churn and stale async refresh results."""
    with open(MAIN_QML, encoding="utf-8") as f:
        main_source = f.read()
    with open(CHAT_SETTINGS_DIALOG, encoding="utf-8") as f:
        dialog_source = f.read()

    assert "function setSessionOverrides(sessionId, overrides)" in main_source
    assert "property var openCodeAgentFetchWaiters" in main_source
    assert "function _notifyOpenCodeAgentFetchWaiters()" in main_source
    assert "openCodeAgentFetchWaiters = (root.openCodeAgentFetchWaiters || []).concat([callback])" in main_source
    assert "function isSubagent(name, metadata)" in main_source
    assert "sub[-_ ]?agent" in main_source
    assert '"compaction", "explore", "general", "summary", "title"' in main_source
    assert "item['name'] = n; item['id'] = n" in main_source
    atomic_body = main_source.split("function setSessionOverrides(sessionId, overrides)", 1)[1].split(
        "function getEffectiveProvider", 1
    )[0]
    assert atomic_body.count("root.sessions = updated") == 1
    assert "persistSessions();" in atomic_body

    assert "property int _generation" in dialog_source
    assert "function _current(token)" in dialog_source
    assert dialog_source.count("_current(token)") >= 5
    assert "setSessionOverrides(_sessionId, overrides)" in dialog_source
    assert "saveCurrentSessionState" not in dialog_source
    assert "visible: page._mode !== \"opencode\"" in dialog_source
