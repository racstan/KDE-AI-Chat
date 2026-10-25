"""Image files in chats (kdeaichat/images.py): saving, magic bytes, size cap, deletion, export."""
import base64
import contextlib
import io
import json
import os
import stat
import sys
import tempfile
from unittest.mock import patch

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui"))

from kdeaichat import chats, images  # noqa: E402

PNG = b"\x89PNG\r\n\x1a\n" + b"\x00" * 32
JPEG = b"\xff\xd8\xff\xe0" + b"\x00" * 32
GIF = b"GIF89a" + b"\x00" * 32
WEBP = b"RIFF\x24\x00\x00\x00WEBPVP8 " + b"\x00" * 32


@pytest.fixture
def chat_dir():
    with tempfile.TemporaryDirectory() as data, patch.dict(os.environ, {"XDG_DATA_HOME": data}):
        directory = os.path.join(chats.chats_root(), "applet-7")
        chats.cmd_prepare_chat_dir({"directory": directory})
        yield directory


def run(command, payload):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        command(payload)
    return json.loads(out.getvalue())


def stage(directory, data, name="staging-t1.ini", quoted=False):
    text = base64.b64encode(data).decode()
    with open(os.path.join(directory, name), "w") as f:
        f.write("[General]\ndata=" + ('"%s"' % text if quoted else text) + "\n")
    return name


def save(directory, data, **extra):
    payload = {"directory": directory, "chat": "s-1-2", "message": "m-abc-1", "n": 0, "staging": stage(directory, data)}
    payload.update(extra)
    return run(images.cmd_image_save, payload)


@pytest.mark.parametrize("data,mime,ext", [(PNG, "image/png", "png"), (JPEG, "image/jpeg", "jpg"),
                                           (GIF, "image/gif", "gif"), (WEBP, "image/webp", "webp")])
def test_save_detects_type_by_magic_bytes(chat_dir, data, mime, ext):
    result = save(chat_dir, data)
    assert result == {"path": "images/s-1-2/m-abc-1-0." + ext, "mime": mime, "bytes": len(data)}
    full = os.path.join(chat_dir, result["path"])
    assert open(full, "rb").read() == data
    assert stat.S_IMODE(os.stat(full).st_mode) == 0o600
    assert stat.S_IMODE(os.stat(os.path.dirname(full)).st_mode) == 0o700
    # The staging file is gone.
    assert not [n for n in os.listdir(chat_dir) if n.startswith("staging-")]


def test_save_reads_quoted_value(chat_dir):
    payload = {"directory": chat_dir, "chat": "c", "message": "m", "n": 1, "staging": stage(chat_dir, PNG, quoted=True)}
    assert run(images.cmd_image_save, payload)["path"] == "images/c/m-1.png"


@pytest.mark.parametrize("data", [b"<svg xmlns='http://www.w3.org/2000/svg'/>", b"<html>hi</html>", b"MZ\x90\x00", b"RIFF\x00\x00\x00\x00WAVE", b""])
def test_save_rejects_other_files(chat_dir, data):
    result = save(chat_dir, data)
    assert result["code"] == "not_image"
    assert not os.path.exists(os.path.join(chat_dir, "images"))


def test_save_rejects_a_wrong_extension_claim(chat_dir):
    # Whatever the message name says, the type comes from the bytes.
    result = save(chat_dir, PNG, message="evil.svg")
    assert result["path"].endswith(".png") and result["path"].startswith("images/s-1-2/evil.svg-0")


def test_save_size_cap(chat_dir):
    with patch.object(images, "MAX_IMAGE_BYTES", 1000), patch.object(images, "MAX_STAGING_BYTES", 5000):
        assert save(chat_dir, PNG + b"\x00" * 2000)["code"] == "too_large"
        assert save(chat_dir, PNG)["bytes"] == len(PNG)


def test_save_bad_base64(chat_dir):
    with open(os.path.join(chat_dir, "staging-x.ini"), "w") as f:
        f.write("[General]\ndata=!!!not base64!!!\n")
    result = run(images.cmd_image_save, {"directory": chat_dir, "chat": "c", "message": "m", "n": 0, "staging": "staging-x.ini"})
    assert result["code"] == "bad_data"
    assert not os.path.exists(os.path.join(chat_dir, "staging-x.ini"))


def test_names_are_confined_to_the_images_folder(chat_dir):
    result = save(chat_dir, PNG, chat="../../etc", message="../../x")
    assert ".." not in result["path"].split("/") and result["path"].count("/") == 2
    assert os.path.realpath(os.path.join(chat_dir, result["path"])).startswith(os.path.realpath(chat_dir) + os.sep)


def test_directory_must_be_a_chat_folder(chat_dir):
    with pytest.raises(ValueError):
        run(images.cmd_image_save, {"directory": "/tmp", "chat": "c", "message": "m", "n": 0, "staging": "staging-a.ini"})


@pytest.mark.parametrize("name", ["../x.ini", "staging-.ini", "chat-a.ini", "staging-a/b.ini", "staging-a.txt"])
def test_staging_name_is_validated(chat_dir, name):
    result = run(images.cmd_image_save, {"directory": chat_dir, "chat": "c", "message": "m", "n": 0, "staging": name})
    assert result["code"] == "bad_data"
    assert not os.path.exists(os.path.join(chat_dir, "images"))


def test_n_range(chat_dir):
    with pytest.raises(ValueError):
        save(chat_dir, PNG, n=100)


class FakeResponse(io.BytesIO):
    def __init__(self, data, headers=None):
        super().__init__(data)
        self.headers = headers or {}

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False


def test_save_from_https_url(chat_dir):
    with patch.object(images, "_open_url", return_value=FakeResponse(JPEG)) as opened:
        result = run(images.cmd_image_save, {"directory": chat_dir, "chat": "c", "message": "m", "n": 0, "url": "https://example.com/a.png"})
    opened.assert_called_once_with("https://example.com/a.png")
    assert result["mime"] == "image/jpeg" and result["path"] == "images/c/m-0.jpg"


@pytest.mark.parametrize("url", ["http://example.com/a.png", "file:///etc/passwd", "ftp://example.com/a.png", "https://user:pw@example.com/a.png",
                                 "https:///a.png", "https://exa mple.com/a.png", "javascript:alert(1)", ""])
def test_urls_must_be_plain_https(chat_dir, url):
    with patch.object(images, "_open_url") as opened:
        result = run(images.cmd_image_save, {"directory": chat_dir, "chat": "c", "message": "m", "n": 0, "url": url}) if url else None
        if result is not None:
            assert result["code"] == "bad_data"
    opened.assert_not_called()


def test_url_size_cap_by_header_and_body(chat_dir):
    with patch.object(images, "MAX_IMAGE_BYTES", 100):
        with patch.object(images, "_open_url", return_value=FakeResponse(PNG, {"Content-Length": "5000"})):
            assert run(images.cmd_image_save, {"directory": chat_dir, "chat": "c", "message": "m", "n": 0, "url": "https://a.example/x"})["code"] == "too_large"
        with patch.object(images, "_open_url", return_value=FakeResponse(PNG + b"\x00" * 500)):
            assert run(images.cmd_image_save, {"directory": chat_dir, "chat": "c", "message": "m", "n": 0, "url": "https://a.example/x"})["code"] == "too_large"


def test_url_that_is_not_an_image(chat_dir):
    with patch.object(images, "_open_url", return_value=FakeResponse(b"<html>login</html>")):
        assert run(images.cmd_image_save, {"directory": chat_dir, "chat": "c", "message": "m", "n": 0, "url": "https://a.example/x"})["code"] == "not_image"


def test_only_public_addresses_are_used():
    for host in ("localhost", "127.0.0.1"):
        with pytest.raises(ValueError):
            images._global_address(host, 443)
    with patch.object(images.socket, "getaddrinfo", return_value=[(2, 1, 6, "", ("10.0.0.5", 443)), (2, 1, 6, "", ("192.168.1.2", 443))]):
        with pytest.raises(ValueError):
            images._global_address("internal.example", 443)
    with patch.object(images.socket, "getaddrinfo", return_value=[(2, 1, 6, "", ("10.0.0.5", 443)), (2, 1, 6, "", ("93.184.216.34", 443))]):
        assert images._global_address("mixed.example", 443) == "93.184.216.34"


def test_delete_one_message_or_the_whole_chat(chat_dir):
    for message, n in (("m1", 0), ("m1", 1), ("m2", 0)):
        save(chat_dir, PNG, chat="c", message=message, n=n, staging=stage(chat_dir, PNG, "staging-%s%d.ini" % (message, n)))
    other = save(chat_dir, PNG, chat="other", message="m1", n=0)
    folder = os.path.join(chat_dir, "images", "c")
    assert sorted(os.listdir(folder)) == ["m1-0.png", "m1-1.png", "m2-0.png"]

    assert run(images.cmd_image_delete, {"directory": chat_dir, "chat": "c", "message": "m1"}) == {"deleted": 2}
    assert os.listdir(folder) == ["m2-0.png"]

    assert run(images.cmd_image_delete, {"directory": chat_dir, "chat": "c"}) == {"deleted": 1}
    assert not os.path.exists(folder)
    assert os.path.exists(os.path.join(chat_dir, other["path"]))
    # Nothing there: still fine.
    assert run(images.cmd_image_delete, {"directory": chat_dir, "chat": "c"}) == {"deleted": 0}


def test_delete_does_not_follow_links(chat_dir):
    outside = os.path.join(os.path.dirname(chat_dir), "secret.txt")
    open(outside, "w").write("keep")
    folder = os.path.join(chat_dir, "images", "c")
    os.makedirs(folder)
    os.symlink(outside, os.path.join(folder, "m-0.png"))
    run(images.cmd_image_delete, {"directory": chat_dir, "chat": "c", "message": "m"})
    assert open(outside).read() == "keep"
    # A linked chat folder is left alone too.
    os.unlink(os.path.join(folder, "m-0.png"))
    os.rmdir(folder)
    target = os.path.join(os.path.dirname(chat_dir), "elsewhere")
    os.makedirs(target)
    open(os.path.join(target, "m-0.png"), "wb").write(PNG)
    os.symlink(target, folder)
    run(images.cmd_image_delete, {"directory": chat_dir, "chat": "c"})
    assert os.path.exists(os.path.join(target, "m-0.png"))


def test_export_copies_a_validated_image(chat_dir):
    saved = save(chat_dir, WEBP)
    with tempfile.TemporaryDirectory() as out:
        dest = os.path.join(out, "picture.webp")
        assert run(images.cmd_image_export, {"directory": chat_dir, "path": saved["path"], "dest": dest}) == {"saved": dest}
        assert open(dest, "rb").read() == WEBP
        for bad in (os.path.join(out, "x.txt"), out, "relative.png", os.path.join(out, "..", "x.png")):
            with pytest.raises(ValueError):
                run(images.cmd_image_export, {"directory": chat_dir, "path": saved["path"], "dest": bad})


@pytest.mark.parametrize("path", ["../x.png", "images/../../x.png", "images/c/x.svg", "chat-a.ini", "/etc/passwd", "images/c/missing.png"])
def test_export_and_copy_only_serve_saved_images(chat_dir, path):
    for command in (images.cmd_image_export, images.cmd_image_copy):
        with pytest.raises(ValueError):
            run(command, {"directory": chat_dir, "path": path, "dest": "/tmp/x.png"})


def test_copy_uses_wl_copy_or_xclip(chat_dir):
    saved = save(chat_dir, PNG)
    calls = []

    def fake_run(command, **kwargs):
        calls.append((command, kwargs["stdin"].read()))
        return type("R", (), {"returncode": 0})()

    with patch.dict(os.environ, {"WAYLAND_DISPLAY": "wayland-0"}), patch.object(images.shutil, "which", side_effect=lambda n: "/usr/bin/" + n), \
            patch("subprocess.run", fake_run):
        assert run(images.cmd_image_copy, {"directory": chat_dir, "path": saved["path"]}) == {"tool": "wl-copy"}
    assert calls == [(["wl-copy", "--type", "image/png"], PNG)]

    env = {k: v for k, v in os.environ.items() if k != "WAYLAND_DISPLAY"}
    env["DISPLAY"] = ":0"
    with patch.dict(os.environ, env, clear=True), patch.object(images.shutil, "which", side_effect=lambda n: "/usr/bin/" + n if n == "xclip" else None), \
            patch("subprocess.run", fake_run):
        assert run(images.cmd_image_copy, {"directory": chat_dir, "path": saved["path"]}) == {"tool": "xclip"}
    assert calls[1][0][:2] == ["xclip", "-selection"]

    with patch.object(images.shutil, "which", return_value=None):
        assert run(images.cmd_image_copy, {"directory": chat_dir, "path": saved["path"]})["code"] == "no_tool"


def test_command_is_registered_with_the_helper():
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(__file__)), "org.kde.plasma.kdeaichat", "contents", "ui"))
    import kde_ai_helper
    source = open(kde_ai_helper.__file__).read()
    assert "images" in source and set(images.COMMANDS) == {"image_save", "image_delete", "image_copy", "image_export"}
