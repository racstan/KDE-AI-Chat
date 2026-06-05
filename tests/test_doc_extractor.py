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
