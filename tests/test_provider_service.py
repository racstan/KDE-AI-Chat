"""Regression tests for provider settings reaching runtime configuration."""

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
PROVIDER_SERVICE = os.path.join(UI_DIR, "ProviderService.js")


def _run_provider_config(provider, configuration):
    with open(PROVIDER_SERVICE, encoding="utf-8") as source_file:
        source = re.sub(
            r"^\s*\.pragma\s+library\s*\n",
            "",
            source_file.read(),
            count=1,
        )

    driver = (
        "\nconsole.log(JSON.stringify(getProviderConfig("
        + json.dumps(provider)
        + ", "
        + json.dumps(configuration)
        + ")));\n"
    )
    with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as script:
        script.write(source)
        script.write(driver)
        script_path = script.name

    try:
        result = subprocess.run(
            ["node", script_path],
            capture_output=True,
            check=True,
            text=True,
            timeout=10,
        )
        return json.loads(result.stdout)
    finally:
        os.unlink(script_path)


def test_local_provider_uses_configured_endpoint():
    config = _run_provider_config(
        "local",
        {"localBaseUrl": "http://127.0.0.1:8080/v1", "localModel": "local-model"},
    )
    assert config["baseUrl"] == "http://127.0.0.1:8080/v1"
    assert config["model"] == "local-model"
    assert config["allowEmptyKey"] is True


def test_ollama_provider_uses_configured_endpoint():
    config = _run_provider_config(
        "ollama",
        {"ollamaBaseUrl": "http://ollama.internal:11434/v1", "ollamaModel": "qwen3"},
    )
    assert config["baseUrl"] == "http://ollama.internal:11434/v1"
    assert config["model"] == "qwen3"


def test_image_provider_uses_its_own_settings():
    config = _run_provider_config(
        "stability-image",
        {
            "stabilityImageBaseUrl": "https://images.example.test",
            "stabilityApiKey": "secret",
            "stabilityImageModel": "stable-model",
        },
    )
    assert config == {
        "type": "image-gen",
        "baseUrl": "https://images.example.test",
        "apiKey": "secret",
        "model": "stable-model",
        "headers": None,
        "allowEmptyKey": False,
    }
