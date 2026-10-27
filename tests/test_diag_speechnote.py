"""Setup checks for the Speech Note engine: Speech Note's state is faked, nothing is started."""
import pytest

from kdeaichat import diag_speechnote, diag_system, speechnote
from kdeaichat.speechnote_bus import SpeechNoteError


def fake_status(monkeypatch, reply=None, error=None):
    calls = []

    def status(payload):
        calls.append(payload)
        if error:
            raise error
        return reply

    monkeypatch.setattr(speechnote, "status", status)
    return calls


def codes(rows):
    return [(r["status"], r["code"]) for r in rows]


READY = {"installed": True, "kind": "flatpak", "models_known": True, "stt_models": [{"id": "a"}], "tts_models": [{"id": "b"}]}


def test_not_installed_is_an_error_for_dictation_and_a_warning_for_read_aloud(monkeypatch):
    fake_status(monkeypatch, error=SpeechNoteError("not_installed", "x"))
    assert codes(diag_speechnote.check("stt")) == [("error", "speechnote-missing-stt")]
    assert codes(diag_speechnote.check("tts")) == [("warn", "speechnote-missing-tts")]


def test_the_check_starts_the_service_to_list_the_models(monkeypatch):
    calls = fake_status(monkeypatch, reply=READY)
    assert codes(diag_speechnote.check("stt")) == [("ok", "speechnote-ready-stt")]
    assert calls == [{"start": True}]


def test_a_missing_model_for_the_role_warns(monkeypatch):
    fake_status(monkeypatch, reply=dict(READY, tts_models=[]))
    assert codes(diag_speechnote.check("tts")) == [("warn", "speechnote-no-model-tts")]
    assert codes(diag_speechnote.check("stt")) == [("ok", "speechnote-ready-stt")]
    fake_status(monkeypatch, reply=dict(READY, stt_models=[]))
    assert codes(diag_speechnote.check("stt")) == [("warn", "speechnote-no-model-stt")]


def test_models_that_could_not_be_read_are_not_reported_missing(monkeypatch):
    fake_status(monkeypatch, reply=dict(READY, models_known=False, stt_models=[]))
    assert codes(diag_speechnote.check("stt")) == [("ok", "speechnote-ready-stt")]


@pytest.mark.parametrize("code,expected", [("not_configured", "speechnote-no-model-tts"),
                                           ("service_failed_to_start", "speechnote-service"),
                                           ("timeout", "speechnote-service")])
def test_service_errors(monkeypatch, code, expected):
    fake_status(monkeypatch, error=SpeechNoteError(code, "plain message"))
    assert codes(diag_speechnote.check("tts")) == [("warn", expected)]


def test_the_system_checks_route_to_it(monkeypatch):
    fake_status(monkeypatch, reply=READY)
    assert codes(diag_system.check_dictation({"sttEngine": "speechnote"})) == [("ok", "speechnote-ready-stt")]
    assert codes(diag_system.check_read_aloud({"voiceTtsEngine": "speechnote"})) == [("ok", "speechnote-ready-tts")]
