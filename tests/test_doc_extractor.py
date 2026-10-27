"""Unit tests for the KDE AI Chat document extractor."""

import sys
import os
import importlib.util
import tempfile

EXTRACTOR_PATH = os.path.join(os.path.dirname(__file__),
                              "..", "org.kde.plasma.kdeaichat", "contents", "ui",
                              "doc_extractor.py")

spec = importlib.util.spec_from_file_location("doc_extractor", EXTRACTOR_PATH)
ext = importlib.util.module_from_spec(spec)
sys.modules["doc_extractor"] = ext
spec.loader.exec_module(ext)

extract_single_file = ext.extract_single_file


class TestExtractSingleFile:
    def test_nonexistent_file(self):
        result = extract_single_file("/nonexistent/path.txt")
        assert result["status"] == "error"

    def test_empty_file(self):
        with tempfile.NamedTemporaryFile(suffix=".txt", mode="w", delete=False) as f:
            f.write("")
            tmpname = f.name
        try:
            result = extract_single_file(tmpname)
            assert result["status"] == "success"
            assert result["content"] == ""
        finally:
            os.unlink(tmpname)

    def test_plain_text_file(self):
        with tempfile.NamedTemporaryFile(suffix=".txt", mode="w", delete=False) as f:
            f.write("Hello, world!")
            tmpname = f.name
        try:
            result = extract_single_file(tmpname)
            assert result["status"] == "success"
            assert result["content"] == "Hello, world!"
        finally:
            os.unlink(tmpname)

    def test_unsupported_extension(self):
        with tempfile.NamedTemporaryFile(suffix=".xyz", mode="w", delete=False) as f:
            f.write("test")
            tmpname = f.name
        try:
            result = extract_single_file(tmpname)
            # .xyz falls through to text fallback, so tries UTF-8 read.
            # The file contains valid UTF-8, so it should succeed.
            assert result["status"] == "success"
            assert result["content"] == "test"
        finally:
            os.unlink(tmpname)

    def test_markdown_file(self):
        with tempfile.NamedTemporaryFile(suffix=".md", mode="w", delete=False) as f:
            f.write("# Hello\n\nWorld!")
            tmpname = f.name
        try:
            result = extract_single_file(tmpname)
            assert result["status"] == "success"
        finally:
            os.unlink(tmpname)

    def test_text_file_content(self):
        with tempfile.NamedTemporaryFile(suffix=".txt", mode="w", delete=False) as f:
            f.write("Line 1\nLine 2\nLine 3")
            tmpname = f.name
        try:
            result = extract_single_file(tmpname)
            assert result["status"] == "success"
            assert result["type"] == "text"
            assert "Line 1" in result["content"]
            assert result["mimeType"].startswith("text/")
        finally:
            os.unlink(tmpname)


class TestExtractEdgeCases:
    def test_unicode_content(self):
        with tempfile.NamedTemporaryFile(suffix=".txt", mode="w", delete=False, encoding="utf-8") as f:
            f.write("Hello \u4e16\u754c! \U0001f44b")
            tmpname = f.name
        try:
            result = extract_single_file(tmpname)
            assert result["status"] == "success"
            assert "\u4e16\u754c" in result["content"]
        finally:
            os.unlink(tmpname)

    def test_non_ascii_filename(self):
        with tempfile.NamedTemporaryFile(suffix=".txt", mode="w", delete=False, encoding="utf-8") as f:
            f.write("content")
            tmpname = f.name
        newname = tmpname.rsplit("/", 1)[0] + "/t\u00e9st.txt"
        os.rename(tmpname, newname)
        try:
            result = extract_single_file(newname)
            assert result["status"] == "success"
        finally:
            if os.path.exists(newname):
                os.unlink(newname)

    def test_binary_file_garbage(self):
        with tempfile.NamedTemporaryFile(suffix=".txt", mode="wb", delete=False) as f:
            f.write(b"\x80\x81\x82\x83 not valid utf-8")
            tmpname = f.name
        try:
            result = extract_single_file(tmpname)
            assert result["status"] in ("success", "error")
        finally:
            os.unlink(tmpname)

    def test_directory_not_file(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            result = extract_single_file(tmpdir)
            assert result["status"] == "error"

    def test_long_path(self):
        with tempfile.NamedTemporaryFile(suffix=".txt", mode="w", delete=False) as f:
            f.write("x" * 100000)
            tmpname = f.name
        try:
            result = extract_single_file(tmpname)
            assert result["status"] == "success"
            assert len(result["content"]) == 100000
        finally:
            os.unlink(tmpname)


class TestClipboardFiles:
    def test_clip_dir_prefers_the_runtime_folder(self, tmp_path, monkeypatch):
        monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
        assert ext.clip_dir() == str(tmp_path)
        monkeypatch.delenv("XDG_RUNTIME_DIR")
        assert ext.clip_dir() == tempfile.gettempdir()

    def test_cleanup_accepts_the_runtime_folder_only_for_our_names(self, tmp_path, monkeypatch):
        monkeypatch.setenv("XDG_RUNTIME_DIR", str(tmp_path))
        mine = tmp_path / "kdeaichat_clip_x.png"
        other = tmp_path / "other.png"
        mine.write_text("x")
        other.write_text("x")
        assert ext.cleanup_temporary_file(str(mine)) == {"status": "success"}
        assert not mine.exists()
        assert ext.cleanup_temporary_file(str(other))["status"] == "error" and other.exists()

    def test_sweep_stale_clips(self, tmp_path):
        old = tmp_path / "kdeaichat_clip_old.png"
        new = tmp_path / "kdeaichat_clip_new.png"
        keep = tmp_path / "unrelated.png"
        for p in (old, new, keep):
            p.write_text("x")
        os.utime(old, (1, 1))
        os.utime(keep, (1, 1))
        assert ext.sweep_stale_clips(str(tmp_path)) == 1
        assert not old.exists() and new.exists() and keep.exists()
