"""Model discovery against fixture folders (Speech Note, Handy, HF cache, whisper.cpp) and the model list."""
import os

from kdeaichat import stt_models, stt_units


def touch(path, data=b"x" * 2000):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def ct2(folder):
    touch(os.path.join(folder, "model.bin"))
    touch(os.path.join(folder, "config.json"), b"{}")


def test_discover_reuses_other_apps_models(tmp_path, monkeypatch):
    home = str(tmp_path)
    monkeypatch.delenv("XDG_CACHE_HOME", raising=False)
    monkeypatch.delenv("XDG_DATA_HOME", raising=False)
    cache = os.path.join(home, "hf")
    # Speech Note (native and Flatpak, plus a folder set in its settings).
    native = os.path.join(home, ".cache", "net.mkiol", "dsnote", "speech-models")
    ct2(os.path.join(native, "multilang_fasterwhisper_small"))
    touch(os.path.join(native, "multilang_whisper_base.ggml"))
    touch(os.path.join(native, "en_parakeet_tdt.ggml"))          # Parakeet: not ours
    os.makedirs(os.path.join(native, "en_piper_us_amy_medium"))   # a Piper voice: TTS's business
    flatpak = os.path.join(home, ".var", "app", "net.mkiol.SpeechNote", "cache", "net.mkiol", "dsnote", "speech-models")
    touch(os.path.join(flatpak, "de_whisper_large3turbo.ggml"))
    custom = os.path.join(home, "Models")
    ct2(os.path.join(custom, "multilang_fasterwhisper_tiny"))
    touch(os.path.join(home, ".config", "net.mkiol", "dsnote", "settings.conf"),
          ("[service]\nmodels_dir=%s\n" % custom).encode())
    # Handy: legacy ggml .bin are whisper.cpp models; .gguf needs Handy's engine.
    handy = os.path.join(home, ".local", "share", "com.pais.handy", "models")
    touch(os.path.join(handy, "ggml-small.bin"))
    touch(os.path.join(handy, "whisper-small-Q8_0.gguf"))
    # HuggingFace cache: faster-whisper's own download and another CTranslate2 Whisper repo.
    ct2(os.path.join(cache, "models--Systran--faster-whisper-base", "snapshots", "abc"))
    ct2(os.path.join(cache, "models--someone--whisper-ct2-de", "snapshots", "def"))
    touch(os.path.join(cache, "models--handy-computer--parakeet-unified-en-0.6b-gguf", "snapshots", "x", "m.gguf"))
    # whisper.cpp's models folder.
    touch(os.path.join(home, "whisper.cpp", "models", "ggml-medium.en.bin"))
    touch(os.path.join(home, "whisper.cpp", "models", "ggml-silero-v5.1.2.bin"))  # its VAD model

    found = stt_models.discover(home, cache)
    summary = sorted((r["source"], r["engine"], r["name"]) for r in found)
    assert summary == [
        ("Handy", "whisper-cpp", "ggml-small"),
        ("HuggingFace", "faster-whisper", "base"),
        ("HuggingFace", "faster-whisper", "someone/whisper-ct2-de"),
        ("Speech Note", "faster-whisper", "multilang_fasterwhisper_small"),
        ("Speech Note", "faster-whisper", "multilang_fasterwhisper_tiny"),
        ("Speech Note", "whisper-cpp", "de_whisper_large3turbo"),
        ("Speech Note", "whisper-cpp", "multilang_whisper_base"),
        ("whisper.cpp", "whisper-cpp", "medium.en"),
    ]
    by_name = {r["name"]: r for r in found}
    assert by_name["base"]["model"] == "base"  # loads by name from the cache
    assert by_name["multilang_fasterwhisper_small"]["model"] == os.path.join(native, "multilang_fasterwhisper_small")
    assert all(r["mb"] >= 0 for r in found)


def test_catalogue():
    rows = stt_models.catalogue(gpu=False, cache="/nonexistent")
    names = [r["name"] for r in rows]
    assert "large" not in names and "turbo" not in names and "small" in names
    assert [r["name"] for r in rows if r["recommended"]] == ["small"]
    assert [r["name"] for r in stt_models.catalogue(gpu=True, cache="/nonexistent") if r["recommended"]] == ["large-v3-turbo"]
    assert all(r["mb"] > 0 and not r["downloaded"] for r in rows)


def test_idle_minutes():
    assert stt_units.idle_seconds({}) == 300
    assert stt_units.idle_seconds({"sttIdleMinutes": 15}) == 900
    assert stt_units.idle_seconds({"sttIdleMinutes": 0}) == 60
    assert stt_units.idle_seconds({"sttIdleMinutes": "x"}) == 300
    assert "--idle-timeout 900" in stt_units.service_text("/py", "/s.py", "/t", 900)
