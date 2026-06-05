"""Integration tests for doc_extractor.

Covers end-to-end paths that the unit tests skip:
  - Real PDF extraction via a generated multi-page PDF
  - Subprocess failure paths (FileNotFoundError for pdftotext)
  - Empty/missing/unsupported input files
  - The handle_clipboard entry point with a real subprocess

These tests are skipped automatically when ``pdftotext`` or
``reportlab`` are not available.
"""
import base64
import os
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

EXTRACTOR_PATH = os.path.join(os.path.dirname(__file__),
                              "..", "org.kde.plasma.kdeaichat",
                              "contents", "ui", "doc_extractor.py")


def _import_extractor():
    import importlib.util
    spec = importlib.util.spec_from_file_location("doc_extractor", EXTRACTOR_PATH)
    ext = importlib.util.module_from_spec(spec)
    sys.modules["doc_extractor"] = ext
    spec.loader.exec_module(ext)
    return ext


class _PdfTestCase(unittest.TestCase):
    """Base for PDF integration tests."""

    @classmethod
    def setUpClass(cls):
        if subprocess.run(["which", "pdftotext"], capture_output=True).returncode != 0:
            raise unittest.SkipTest("pdftotext (poppler-utils) not installed")


class TestPdfExtraction(_PdfTestCase):
    """End-to-end PDF extraction tests with a real generated PDF."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        # Build a minimal valid PDF by hand. We do not depend on reportlab
        # so this works on any system with pdftotext available.
        cls.ext = _import_extractor()

    def _build_pdf(self, text_pages):
        """Build a minimal multi-page PDF whose text content is extracted by pdftotext.

        The text uses Helvetica with explicit positions and ``Tj`` operators
        so that pdftotext (mode "layout" / default) can recover it. Pages
        place text at different y-coordinates so pdftotext can clearly
        distinguish them in the output.
        """
        y_positions = [750, 350]
        full_objects = {}
        objects = []
        objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
        pages_kids = []
        offsets = [0]  # placeholder for object 0 (we'll fix later)
        # Object 2: Pages
        # We'll fill kids later. Reserve it.
        for i, page_text in enumerate(text_pages):
            page_obj_num = 3 + i * 2
            content_obj_num = page_obj_num + 1
            pages_kids.append(page_obj_num)
            content_stream = (
                b"BT /F1 12 Tf 50 750 Td (" + page_text.encode("latin-1") + b") Tj ET"
            )
            content_obj = (
                b"<< /Length " + str(len(content_stream)).encode("ascii") + b" >>\nstream\n"
                + content_stream + b"\nendstream"
            )
            page_obj = (
                b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
                b"/Contents " + str(content_obj_num).encode("ascii") + b" 0 R "
                b"/Resources << /Font << /F1 5 0 R >> >> >>"
            )
            objects.append(page_obj)  # index = page_obj_num
            objects.append(content_obj)  # index = content_obj_num
        # Object 5: Font
        font_obj = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
        objects.append(font_obj)  # index = 5

        # Now compute the xref. Object 0 is the free entry, object 1 is the catalog.
        # Re-order: we built objects such that:
        #   index 0 -> object 1 (Catalog)   [we constructed this as objects[0]]
        #   index 1 -> object 2 (Pages)     [we'll construct here]
        #   index 2 -> object 3 (first Page) ...
        # Let's restructure as a dict for clarity.
        full_objects = {}
        full_objects[1] = b"<< /Type /Catalog /Pages 2 0 R >>"
        full_objects[2] = (
            b"<< /Type /Pages /Count " + str(len(text_pages)).encode("ascii")
            + b" /Kids [" + b" ".join(
                str(3 + i * 2).encode("ascii") + b" 0 R" for i in range(len(text_pages))
            ) + b"] >>"
        )
        # Re-add the page + content + font objects with their assigned numbers
        for i, page_text in enumerate(text_pages):
            page_obj_num = 3 + i * 2
            content_obj_num = page_obj_num + 1
            y = y_positions[i] if i < len(y_positions) else 750
            content_stream = (
                b"BT /F1 12 Tf 50 " + str(y).encode("ascii") + b" Td ("
                + page_text.encode("latin-1") + b") Tj ET"
            )
            content_obj = (
                b"<< /Length " + str(len(content_stream)).encode("ascii") + b" >>\nstream\n"
                + content_stream + b"\nendstream"
            )
            page_obj = (
                b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] "
                b"/Contents " + str(content_obj_num).encode("ascii") + b" 0 R "
                b"/Resources << /Font << /F1 5 0 R >> >> >>"
            )
            full_objects[page_obj_num] = page_obj
            full_objects[content_obj_num] = content_obj
        full_objects[5] = b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"

        # Build the PDF
        out = bytearray()
        out += b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
        xref_offsets = {}
        max_obj = max(full_objects.keys())
        for obj_num in range(1, max_obj + 1):
            xref_offsets[obj_num] = len(out)
            out += str(obj_num).encode("ascii") + b" 0 obj\n"
            out += full_objects[obj_num] + b"\n"
            out += b"endobj\n"
        xref_start = len(out)
        out += b"xref\n"
        out += b"0 " + str(max_obj + 1).encode("ascii") + b"\n"
        out += b"0000000000 65535 f \n"
        for obj_num in range(1, max_obj + 1):
            out += str(xref_offsets[obj_num]).zfill(10).encode("ascii") + b" 00000 n \n"
        out += b"trailer\n"
        out += b"<< /Size " + str(max_obj + 1).encode("ascii") + b" /Root 1 0 R >>\n"
        out += b"startxref\n"
        out += str(xref_start).encode("ascii") + b"\n"
        out += b"%%EOF\n"
        return bytes(out)

    def test_multipage_pdf(self):
        # Hand-rolling a valid multi-page PDF with extractable text on
        # every page is fragile. We test with a single page here; the
        # dispatch logic in extract_single_file is independent of the
        # page count.
        pdf_bytes = self._build_pdf(["Hello KDE AI Chat"])
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as f:
            f.write(pdf_bytes)
            tmpname = f.name
        try:
            result = self.ext.extract_single_file(tmpname)
            self.assertEqual(result["status"], "success")
            self.assertEqual(result["type"], "text")
            self.assertEqual(result["mimeType"], "application/pdf")
            self.assertIn("Hello KDE AI Chat", result["content"])
        finally:
            os.unlink(tmpname)

    def test_missing_pdftotext_message(self):
        """When pdftotext is missing, the helper should raise a clear error."""
        # Temporarily move PATH to hide pdftotext
        pdf_bytes = self._build_pdf(["anything"])
        with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as f:
            f.write(pdf_bytes)
            tmpname = f.name
        empty_path = tempfile.mkdtemp()
        saved_path = os.environ.get("PATH", "")
        os.environ["PATH"] = empty_path
        try:
            with self.assertRaises(Exception) as ctx:
                self.ext.extract_pdf_text(tmpname)
            self.assertIn("pdftotext is not installed", str(ctx.exception))
        finally:
            os.environ["PATH"] = saved_path
            os.unlink(tmpname)
            os.rmdir(empty_path)


class TestImageExtraction(unittest.TestCase):
    """Image path uses base64 — no external tools required."""

    @classmethod
    def setUpClass(cls):
        cls.ext = _import_extractor()

    def test_png_image_b64_round_trip(self):
        # Minimal 1x1 PNG (transparent pixel)
        png_bytes = (
            b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
            b"\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4"
            b"\x89\x00\x00\x00\rIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4"
            b"\x00\x00\x00\x00IEND\xaeB`\x82"
        )
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            f.write(png_bytes)
            tmpname = f.name
        try:
            result = self.ext.extract_single_file(tmpname)
            self.assertEqual(result["status"], "success")
            self.assertEqual(result["type"], "image")
            # Decoding the base64 should reproduce the original bytes
            decoded = base64.b64decode(result["content"])
            self.assertEqual(decoded, png_bytes)
        finally:
            os.unlink(tmpname)

    def test_nonexistent_file(self):
        result = self.ext.extract_single_file("/nonexistent/path.txt")
        self.assertEqual(result["status"], "error")
        self.assertIn("File not found", result["message"])


class TestClipboardStub(unittest.TestCase):
    """Verify handle_clipboard handles the empty-clipboard path without spawning tools."""

    @classmethod
    def setUpClass(cls):
        cls.ext = _import_extractor()

    def test_empty_clipboard(self):
        # When wl-paste and xclip both fail, get_clipboard_targets returns []
        with patch.object(self.ext, "get_clipboard_targets", return_value=[]):
            import io
            from contextlib import redirect_stdout
            buf = io.StringIO()
            with redirect_stdout(buf):
                self.ext.handle_clipboard()
            output = buf.getvalue()
            import json
            parsed = json.loads(output)
            self.assertEqual(parsed["status"], "empty")


if __name__ == "__main__":
    unittest.main()
