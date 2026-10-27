"""Ask about the selected text: kdeaichat/selection.py and `kdeaichat-ask --selection`, with fake wl-paste /
xclip / xsel / notify-send on a temporary PATH: the real selection and clipboard are never read."""
import os
import subprocess
import sys

import pytest

from kdeaichat import ask_inbox, selection

UI = os.path.join(os.path.dirname(__file__), "..", "org.kde.plasma.kdeaichat", "contents", "ui")
ASK = os.path.join(UI, "scripts", "kdeaichat-ask")


def fake_tool(folder, name, primary, clipboard):
    """A script that prints `primary` or `clipboard` depending on which selection it is asked for."""
    path = folder / name
    path.write_text("#!/bin/sh\ncase \"$*\" in *primary*|*\"-p\"*) printf %%s '%s' ;; *) printf %%s '%s' ;; esac\n"
                    % (primary, clipboard))
    path.chmod(0o755)


@pytest.fixture
def tools(tmp_path, monkeypatch):
    folder = tmp_path / "bin"
    folder.mkdir()
    monkeypatch.setenv("KDEAICHAT_SELECTION_PATH", str(folder))
    monkeypatch.setenv("KDEAICHAT_ASK_DIR", str(tmp_path / "ask"))
    return folder


def test_wayland_reads_the_primary_selection(tools, monkeypatch):
    monkeypatch.setenv("WAYLAND_DISPLAY", "wayland-test")
    fake_tool(tools, "wl-paste", "selected words", "clipboard words")
    assert selection.read_selection() == ("selected words", "selection")


def test_x11_uses_xclip_then_xsel(tools, monkeypatch):
    monkeypatch.delenv("WAYLAND_DISPLAY", raising=False)
    fake_tool(tools, "xsel", "from xsel", "xsel clip")
    assert selection.read_selection() == ("from xsel", "selection")
    fake_tool(tools, "xclip", "from xclip", "xclip clip")
    assert selection.read_selection() == ("from xclip", "selection")


def test_empty_selection_falls_back_to_the_clipboard_and_says_so(tools, monkeypatch):
    monkeypatch.setenv("WAYLAND_DISPLAY", "wayland-test")
    fake_tool(tools, "wl-paste", "", "only the clipboard")
    assert selection.read_selection() == ("only the clipboard", "clipboard")


def test_nothing_selected_and_no_tools(tools, monkeypatch):
    assert selection.read_selection() == ("", None)
    monkeypatch.setenv("WAYLAND_DISPLAY", "wayland-test")
    fake_tool(tools, "wl-paste", "  ", "")
    assert selection.read_selection() == ("", None)


def test_quote_format():
    assert selection.quote("one\ntwo\n\nfour\n") == "> one\n> two\n>\n> four\n\n"
    assert selection.quote("a\r\nb") == "> a\n> b\n\n"


def run_ask(tmp_path, *args):
    return subprocess.run([sys.executable, ASK, *args], capture_output=True, text=True, env={
        **os.environ, "KDEAICHAT_ASK_DIR": str(tmp_path / "ask"),
        "KDEAICHAT_SELECTION_PATH": str(tmp_path / "bin")})


def test_command_quotes_the_selection_without_sending(tools, tmp_path, monkeypatch):
    monkeypatch.setenv("WAYLAND_DISPLAY", "wayland-test")
    fake_tool(tools, "wl-paste", "line one\nline two", "clip")
    done = run_ask(tmp_path, "--selection")
    assert done.returncode == 0 and done.stderr == ""
    assert ask_inbox.take_all() == [{"text": "> line one\n> line two\n\n", "files": [], "newChat": False, "send": False}]


def test_command_says_so_when_it_used_the_clipboard(tools, tmp_path, monkeypatch):
    monkeypatch.setenv("WAYLAND_DISPLAY", "wayland-test")
    log = tmp_path / "notify.log"
    fake_tool(tools, "wl-paste", "", "clip text")
    (tools / "notify-send").write_text('#!/bin/sh\necho "$@" >> "%s"\n' % log)
    (tools / "notify-send").chmod(0o755)
    done = run_ask(tmp_path, "--selection")
    assert done.returncode == 0 and "clipboard" in done.stderr
    assert "clipboard" in log.read_text() and "clip text" not in log.read_text(), "the notice never holds the text"
    assert ask_inbox.take_all()[0]["text"] == "> clip text\n\n"


def test_command_with_nothing_selected_fails_with_a_notice(tools, tmp_path):
    done = run_ask(tmp_path, "--selection")
    assert done.returncode == 1 and "Nothing is selected" in done.stderr
    assert ask_inbox.take_all() == []
