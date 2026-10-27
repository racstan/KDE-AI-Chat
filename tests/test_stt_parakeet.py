"""The Parakeet dictation engine: finding Handy's GGUF on disk (no download), the checked download,
the setup size, engine selection, and the service with a fake transcribe.cpp model."""
import hashlib
import io
import os
import re
import subprocess
import sys
import threading
import wave

import pytest

from kdeaichat import stt_engines, stt_http, stt_models, stt_parakeet, stt_settings, stt_setup, stt_units, voice_data
from kdeaichat.stt_settings import SettingsError, from_payload

UI = os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui")
VOICE = os.path.join(UI, "voice")
TEST_WAV = os.path.join(VOICE, "stt-test.wav")
sys.path.insert(0, VOICE)
import stt_parakeet_model  # noqa: E402
import stt_service  # noqa: E402
import stt_whisper  # noqa: E402
from stt_parakeet_model import ParakeetHolder, read_pcm  # noqa: E402

HANDY_SNAPSHOT = os.path.join("models--handy-computer--parakeet-unified-en-0.6b-gguf", "snapshots", "7e948f2")


def touch(path, data=b"GGUF" + b"x" * 1996):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return path


@pytest.fixture
def home(tmp_path, monkeypatch):
    monkeypatch.setenv("HOME", str(tmp_path / "home"))
    monkeypatch.setenv("XDG_DATA_HOME", str(tmp_path / "home" / "data"))
    monkeypatch.setenv("HF_HUB_CACHE", str(tmp_path / "hf"))
    monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path / "run"))
    (tmp_path / "run").mkdir(mode=0o700)
    monkeypatch.setenv("KDEAICHAT_SYSTEMCTL", "true")
    monkeypatch.setenv("KDEAICHAT_UNIT_DIR", str(tmp_path / "units"))
    return tmp_path


def test_names_match_the_settings_and_the_qml_defaults():
    assert stt_parakeet.NAME == stt_settings.PARAKEET_DEFAULT
    # The helper falls back to Parakeet when a payload names no engine; the widget defaults to Speech Note.
    assert stt_settings.ENGINES[0] == stt_settings.DEFAULT_ENGINE == "parakeet"
    with open(os.path.join(UI, "voice", "SttEngines.js")) as f:
        js = f.read()
    assert 'var defaultEngine = "speechnote";' in js and 'var localDefault = "parakeet";' in js and 'var parakeetDefault = "%s";' % stt_parakeet.NAME in js
    with open(os.path.join(UI, "..", "config", "main.xml")) as f:
        xml = f.read()
    assert '<entry name="sttEngine" type="String"><default>speechnote</default></entry>' in xml
    assert '<entry name="sttParakeetModel" type="String"><default>%s</default></entry>' % stt_parakeet.NAME in xml
    assert stt_parakeet.MB == 731 and stt_parakeet.REVISION in stt_parakeet.URL


def test_handys_copy_in_the_hf_cache_is_reused_without_download(home):
    gguf = touch(str(home / "hf" / HANDY_SNAPSHOT / stt_parakeet.FILE))
    assert stt_parakeet.resolve(stt_parakeet.NAME) == gguf
    row = stt_parakeet.catalogue()[0]
    assert row["downloaded"] and row["source"] == "Handy, HuggingFace cache" and row["path"] == gguf and row["mb"] == 731
    size = stt_setup.estimate_parakeet(stt_parakeet.NAME, str(home / "venv"), gguf)
    assert size["model_mb"] == 0 and "already on this computer" in size["model_note"]
    assert [i["name"] for i in size["items"]] == ["transcribe-cpp", "transcribe-cpp-native"]
    assert size["total_mb"] == 24 and size["gpu"] is False


def test_lookup_order_and_other_files_found(home):
    handy = touch(str(home / "home" / ".local" / "share" / "com.pais.handy" / "models" / stt_parakeet.FILE))
    assert stt_parakeet.find_default()["source"] == "Handy"
    hf = touch(str(home / "hf" / HANDY_SNAPSHOT / stt_parakeet.FILE))
    assert stt_parakeet.find_default()["path"] == hf      # the HF cache before Handy's folder
    own = touch(os.path.join(stt_parakeet.own_dir(), stt_parakeet.FILE))
    assert stt_parakeet.find_default()["path"] == own     # our own download first
    other = touch(str(home / "hf" / HANDY_SNAPSHOT / "parakeet-unified-en-0.6b-Q4_K_M.gguf"))
    touch(str(home / "home" / ".local" / "share" / "com.pais.handy" / "models" / "whisper-small-Q8_0.gguf"))
    found = [r for r in stt_models.discover(str(home / "home"), str(home / "hf")) if r["engine"] == "parakeet"]
    assert sorted((r["source"], r["name"]) for r in found) == [
        ("Handy", "parakeet-unified-en-0.6b-Q8_0"), ("HuggingFace", "parakeet-unified-en-0.6b-Q4_K_M"),
        ("HuggingFace", "parakeet-unified-en-0.6b-Q8_0")]
    assert {r["model"] for r in found} == {other, hf, handy}   # the default's own copy is not listed twice


def test_nothing_on_disk_means_a_download_with_its_size(home):
    assert stt_parakeet.resolve(stt_parakeet.NAME) == ""
    assert stt_parakeet.catalogue()[0]["downloaded"] is False
    size = stt_setup.estimate_parakeet(stt_parakeet.NAME, str(home / "venv"), "")
    model = [i for i in size["items"] if i["kind"] == "model"][0]
    assert model["mb"] == 731 and model["to"] == stt_parakeet.own_dir() and size["total_mb"] == 755


def fake_opener(data):
    def opener(url, timeout):
        assert url == stt_parakeet.URL and timeout > 0
        return io.BytesIO(data)
    return opener


def test_download_is_checked_before_use(home):
    data = b"GGUF" + os.urandom(5000)
    good = hashlib.sha256(data).hexdigest()
    with pytest.raises(stt_parakeet.DownloadError):
        stt_parakeet.download(fake_opener(data), sha256="0" * 64, size=len(data))
    assert os.listdir(stt_parakeet.own_dir()) == []     # no .part left behind, nothing used
    with pytest.raises(stt_parakeet.DownloadError):
        stt_parakeet.download(fake_opener(data), sha256=good, size=len(data) - 1)
    reply = stt_parakeet.download(fake_opener(data), sha256=good, size=len(data))
    assert reply["path"] == os.path.join(stt_parakeet.own_dir(), stt_parakeet.FILE)
    assert stt_parakeet.resolve(stt_parakeet.NAME) == reply["path"]
    assert stt_parakeet.download(fake_opener(b""))["already"] is True


def test_settings_and_engine_selection(home):
    s = from_payload({})
    assert s["engine"] == "parakeet" and s["parakeet_model"] == stt_parakeet.NAME
    assert from_payload({"sttParakeetModel": "/models/x.gguf", "sttDevice": "gpu"})["parakeet_model"] == "/models/x.gguf"
    for bad in ("/models/x.bin", "relative.gguf", "../x.gguf"):
        with pytest.raises(SettingsError):
            from_payload({"sttParakeetModel": bad})
    # Not downloaded: says so, with the size; a missing own file is named.
    with pytest.raises(stt_http.EngineError) as err:
        stt_engines.parakeet(TEST_WAV, s)
    assert err.value.code == "model_missing" and "731 MB" in str(err.value)
    reply = stt_engines.transcribe(TEST_WAV, from_payload({"sttParakeetModel": "/nonexistent/x.gguf"}))
    assert reply["type"] == "stt_error" and reply["code"] == "model_missing"


def test_engine_rows(home):
    venv = home / "venv"
    rows = {r["id"]: r for r in stt_engines.available(from_payload({"venv": str(venv)}))}
    assert list(rows)[0] == "parakeet" and rows["parakeet"]["available"] is False
    site = venv / "lib" / "python3.13" / "site-packages"
    touch(str(venv / "bin" / "python3"))
    for name in ("transcribe_cpp", "transcribe_cpp_native"):
        (site / name).mkdir(parents=True)
    rows = {r["id"]: r for r in stt_engines.available(from_payload({"venv": str(venv)}))}
    assert rows["parakeet"]["installed"] and not rows["parakeet"]["available"]
    assert rows["parakeet"]["reason"] == "the model is not downloaded yet"
    touch(str(home / "hf" / HANDY_SNAPSHOT / stt_parakeet.FILE))
    rows = {r["id"]: r for r in stt_engines.available(from_payload({"venv": str(venv)}))}
    assert rows["parakeet"]["available"] and rows["parakeet"]["model_found"]
    assert rows["faster-whisper"]["installed"] is False


def test_units_are_made_for_parakeet(home, tmp_path):
    venv = home / "home" / "data" / "kdeaichat" / "venv"
    touch(str(venv / "bin" / "python3"))
    calls = []
    result = stt_units.sync({"sttEnabled": True, "sttEngine": "parakeet"}, directory=str(tmp_path / "u"),
                            run=lambda argv: calls.append(argv) or 0)
    assert result["installed"] and ["enable", "--now", "kde-ai-stt.socket"] in calls
    result = stt_units.sync({"sttEnabled": True, "sttEngine": "remote"}, directory=str(tmp_path / "u"),
                            run=lambda argv: calls.append(argv) or 0)
    assert result["removed"] and result["reason"] == "another engine is chosen"


def test_remove_data_deletes_our_parakeet_download_only(home, capsys):
    hf = touch(str(home / "hf" / HANDY_SNAPSHOT / stt_parakeet.FILE))
    own = touch(os.path.join(stt_parakeet.own_dir(), stt_parakeet.FILE), b"x" * 3_000_000)
    info = voice_data.faster_whisper_data()
    assert [m["name"] for m in info["models"]] == [stt_parakeet.NAME] and info["models_mb"] == 3
    voice_data.COMMANDS["voice_data_remove"]({"engine": "parakeet", "confirm": True})
    assert '"voice_data_removed"' in capsys.readouterr().out
    assert not os.path.exists(own) and os.path.exists(hf)   # Handy's copy is never touched


# --- the service side, with a fake transcribe.cpp ------------------------------------------------

class FakeModel:
    def __init__(self, path, device, fail_run=False):
        self.path, self.backend, self.fail_run, self.closed = path, {"gpu": "Vulkan0"}.get(device, "CPU"), fail_run, False

    def session(self):
        return self

    def run(self, pcm):
        if self.fail_run:
            raise RuntimeError("vk::DeviceLostError")
        return type("R", (), {"text": " heard %d samples on %s " % (len(pcm), self.backend)})()

    def close(self):
        self.closed = True


def wav_file(path, rate=16000, channels=1, seconds=1.0):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"\x10\x00" * int(rate * seconds) * channels)
    os.chmod(str(path), 0o600)
    return str(path)


def test_read_pcm_resamples_and_mixes_down(tmp_path):
    assert len(read_pcm(wav_file(tmp_path / "a.wav"))) == 16000
    assert len(read_pcm(wav_file(tmp_path / "b.wav", rate=22050, channels=2))) == 16000
    samples = read_pcm(TEST_WAV)
    assert samples.typecode == "f" and len(samples) > 16000 and max(samples) <= 1.0


def test_holder_lazy_load_reload_and_gpu_fallback(tmp_path):
    gguf = touch(str(tmp_path / "m.gguf"))
    wav = wav_file(tmp_path / "s.wav")
    loads = []

    def loader(path, device):
        loads.append(device)
        if device != "cpu" and len(loads) > 2:
            raise RuntimeError("no Vulkan graphics card")
        return FakeModel(path, device)

    holder = ParakeetHolder(loader=loader)
    assert holder.status()["loaded"] is False and loads == []
    reply = holder.transcribe({"wav": wav, "model": gguf, "device": "cuda"})   # cuda means the graphics card
    assert reply["text"] == "heard 16000 samples on Vulkan0" and reply["device"] == "gpu" and reply["engine"] == "parakeet"
    holder.transcribe({"wav": wav, "model": gguf, "device": "gpu"})
    assert loads == ["gpu"]                                                    # same settings: no reload
    assert holder.transcribe({"wav": wav, "model": gguf, "device": "cpu"})["device"] == "cpu"
    reply = holder.transcribe({"wav": wav, "model": gguf, "device": "auto"})  # GPU load fails: CPU, with a note
    assert reply["device"] == "cpu" and "graphics card failed" in reply["note"]
    assert holder.transcribe({"wav": wav, "model": gguf, "device": "gpu"})["device"] == "cpu"  # remembered
    with pytest.raises(stt_whisper.SttError):
        holder.transcribe({"wav": wav, "model": str(tmp_path / "missing.gguf")})
    with pytest.raises(stt_whisper.SttError):
        holder.transcribe({"wav": wav, "model": gguf, "device": "tpu"})


def test_holder_falls_back_when_the_gpu_fails_while_transcribing(tmp_path):
    gguf = touch(str(tmp_path / "m.gguf"))
    wav = wav_file(tmp_path / "s.wav")
    holder = ParakeetHolder(loader=lambda path, device: FakeModel(path, device, fail_run=device == "gpu"))
    reply = holder.transcribe({"wav": wav, "model": gguf, "device": "gpu"})
    assert reply["device"] == "cpu" and reply["text"].endswith("on CPU") and "DeviceLost" in reply["note"]


def test_service_routes_by_engine_and_keeps_one_model_loaded(home, monkeypatch):
    from kdeaichat import voice_services

    class Whisper:
        def transcribe(self, audio, **kw):
            return iter([type("S", (), {"text": "from whisper"})()]), type("I", (), {"language": "en"})()

    gguf = touch(str(home / "hf" / HANDY_SNAPSHOT / stt_parakeet.FILE))
    token = voice_services.ensure_voice_http_token(stt_engines.token_path())
    whisper = stt_whisper.ModelHolder(loader=lambda *a: Whisper(), cuda_count=lambda: 0)
    parakeet = ParakeetHolder(loader=lambda path, device: FakeModel(path, device))
    srv = stt_service.SttServer(None, 0, token, whisper, 60, parakeet=parakeet)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    monkeypatch.setenv("KDEAICHAT_STT_PORT", str(srv.server_address[1]))
    try:
        reply = stt_engines.transcribe(TEST_WAV, from_payload({"sttDevice": "cuda"}))
        assert reply["type"] == "stt_result" and reply["engine"] == "parakeet", reply
        assert reply["text"].startswith("heard") and reply["device"] == "gpu" and parakeet.key == (gguf, "gpu")
        token_status = stt_http.service_status(token, srv.server_address[1])
        assert token_status["engine"] == "parakeet" and token_status["loaded"]
        reply = stt_engines.transcribe(TEST_WAV, from_payload({"sttEngine": "faster-whisper", "sttModel": "tiny",
                                                               "sttDevice": "gpu"}))
        assert reply["text"] == "from whisper" and parakeet.model is None   # the other model was freed
        assert stt_http.service_status(token, srv.server_address[1])["engine"] == "faster-whisper"
    finally:
        srv.shutdown()
        srv.server_close()


def test_no_torch_or_numpy_needed_by_the_parakeet_service():
    with open(os.path.join(VOICE, "stt_parakeet_model.py")) as f:
        source = f.read()
    assert not re.search(r"^\s*(import|from)\s+(torch|numpy|nemo)", source, re.M)
    code = "import sys; sys.path.insert(0, %r); import stt_service; print('torch' in sys.modules)" % VOICE
    assert subprocess.run([sys.executable, "-c", code], capture_output=True, text=True).stdout.strip() == "False"


def test_setup_script_pins_transcribe_cpp():
    with open(os.path.join(VOICE, "venv_setup.sh")) as f:
        script = f.read()
    assert 'TRANSCRIBE_CPP_VERSION="%s"' % stt_parakeet.VERSION in script
    assert '"transcribe-cpp==$TRANSCRIBE_CPP_VERSION" "transcribe-cpp-native==$TRANSCRIBE_CPP_VERSION"' in script


def test_voice_errors_are_notified_by_the_widget():
    """main.qml shows VoiceManager's errors through the notifier (tests/qml/tst_voice_error.qml drives it)."""
    with open(os.path.join(UI, "main.qml")) as f:
        main = f.read()
    handler = main[main.index("VoiceManager {"):]
    handler = handler[handler.index("onErrorOccurred"):handler.index("onErrorOccurred") + 400]
    assert "notifier.sender(voiceManager.errorTitle, errorText || voiceManager.errorTitle, \"\", true)" in handler
    for folder, _, files in os.walk(UI):
        for name in files:
            if name.endswith((".qml", ".js")):
                with open(os.path.join(folder, name)) as f:
                    assert "fileReaderDs" not in f.read(), name
