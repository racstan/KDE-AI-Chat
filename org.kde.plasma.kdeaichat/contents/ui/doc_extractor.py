#!/usr/bin/env python3
"""doc_extractor — extract text from documents for KDE AI Chat attachments.

Supports PDF, DOCX, plain text, source code, and raster images.
Returns a JSON object on stdout with a ``status`` field; the plasmoid
parses the JSON to attach the result to a chat message.

This module is intentionally dependency-free (stdlib only) so it can
run inside the plasmoid install without an extra virtualenv.
"""
import argparse
import os
import json
import base64
import subprocess
import mimetypes
import zipfile
import xml.etree.ElementTree as ET
import urllib.parse
from typing import Any, Dict, List, Optional, Tuple

SUBPROCESS_TIMEOUT = 30


def extract_docx_text(path: str) -> str:
    """Extract paragraph text from a .docx file.

    Tries ``pandoc`` first; falls back to a direct read of
    ``word/document.xml`` (the Office Open XML schema) when pandoc is
    unavailable. Raises on total failure.
    """
    try:
        result = subprocess.run(
            ["pandoc", "-f", "docx", "-t", "markdown", path],
            capture_output=True, text=True, check=True, timeout=SUBPROCESS_TIMEOUT
        )
        return result.stdout
    except Exception:
        pass

    try:
        with zipfile.ZipFile(path) as docx:
            xml_content = docx.read("word/document.xml")
            root = ET.fromstring(xml_content)
            paragraphs: List[str] = []
            namespace = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
            for p in root.iter(namespace + "p"):
                p_text: List[str] = []
                for t in p.iter(namespace + "t"):
                    if t.text:
                        p_text.append(t.text)
                paragraphs.append("".join(p_text))
            return "\n".join(paragraphs)
    except Exception as e:
        raise Exception(
            "Failed to read docx. Try installing 'pandoc' (Debian/Ubuntu: "
            "apt install pandoc, Arch: pacman -S pandoc-cli, Fedora: dnf "
            f"install pandoc) for robust parsing. Error: {str(e)}"
        )


def extract_pdf_text(path: str) -> str:
    """Extract text from a PDF using ``pdftotext`` (poppler-utils)."""
    try:
        result = subprocess.run(
            ["pdftotext", path, "-"],
            capture_output=True, text=True, check=True, timeout=SUBPROCESS_TIMEOUT
        )
        return result.stdout
    except FileNotFoundError:
        raise Exception(
            "pdftotext is not installed. Please install 'poppler-utils' "
            "(Debian/Ubuntu: apt install poppler-utils, Arch: pacman -S "
            "poppler, Fedora: dnf install poppler-utils) to enable PDF "
            "attachment reading."
        )
    except Exception as e:
        raise Exception(f"Failed to extract PDF contents. Error: {str(e)}")


def _build_success(filename: str, path: str, size: int, mime_type: str,
                   content: str, kind: str = "text") -> Dict[str, Any]:
    """Build a uniform success record for the QML consumer."""
    return {
        "status": "success",
        "type": kind,
        "filename": filename,
        "path": path,
        "size": size,
        "mimeType": mime_type,
        "content": content,
    }


def _build_error(message: str) -> Dict[str, Any]:
    """Build a uniform error record for the QML consumer."""
    return {"status": "error", "message": message}


def _guess_mime(filename: str, ext: str) -> str:
    """Return a best-effort MIME type for the file, falling back to common types."""
    mime_type, _ = mimetypes.guess_type(filename)
    if mime_type:
        return mime_type
    if ext == ".docx":
        return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    if ext == ".csv":
        return "text/csv"
    if ext == ".pdf":
        return "application/pdf"
    return "application/octet-stream"


def extract_single_file(file_path: str) -> Dict[str, Any]:
    """Extract the contents of a single file and return a JSON-friendly dict.

    Dispatch rules (in order):
      1. Image (any ``image/*`` mime or common raster extension) → base64
      2. PDF → pdftotext
      3. DOCX → pandoc / XML
      4. Text-like (mimetype or known extension) → UTF-8 (latin-1 fallback)
      5. Anything else → try text, otherwise report unsupported.
    """
    if not os.path.exists(file_path):
        return _build_error(f"File not found: {file_path}")

    filename = os.path.basename(file_path)
    file_size = os.path.getsize(file_path)
    ext = os.path.splitext(filename)[1].lower()
    mime_type = _guess_mime(filename, ext)

    try:
        if mime_type.startswith("image/") or ext in [".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"]:
            with open(file_path, "rb") as f:
                img_data = f.read()
                base64_data = base64.b64encode(img_data).decode("utf-8")
            actual_mime = mime_type if mime_type.startswith("image/") else "image/jpeg"
            return _build_success(filename, file_path, file_size, actual_mime, base64_data, "image")

        if ext == ".pdf":
            text = extract_pdf_text(file_path)
            return _build_success(filename, file_path, file_size, "application/pdf", text, "text")

        if ext == ".docx":
            text = extract_docx_text(file_path)
            return _build_success(filename, file_path, file_size, mime_type, text, "text")

        if mime_type.startswith("text/") or ext in [".csv", ".txt", ".md", ".json", ".xml",
                                                    ".yaml", ".yml", ".js", ".ts", ".py",
                                                    ".sh", ".html", ".css"]:
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    text = f.read()
            except UnicodeDecodeError:
                with open(file_path, "r", encoding="latin-1") as f:
                    text = f.read()
            return _build_success(filename, file_path, file_size, mime_type or "text/plain", text, "text")

        try:
            with open(file_path, "r", encoding="utf-8") as f:
                text = f.read()
            return _build_success(filename, file_path, file_size, "text/plain", text, "text")
        except Exception:
            return _build_error(f"Unsupported file type: {mime_type}")
    except Exception as e:
        return _build_error(str(e))


def get_clipboard_targets() -> List[str]:
    """Return the list of clipboard targets via wl-paste (Wayland) or xclip (X11)."""
    try:
        res = subprocess.run(
            ["wl-paste", "-l"], capture_output=True, text=True, check=True, timeout=SUBPROCESS_TIMEOUT
        )
        return res.stdout.splitlines()
    except Exception:
        pass
    try:
        res = subprocess.run(
            ["xclip", "-selection", "clipboard", "-t", "TARGETS", "-o"],
            capture_output=True, text=True, check=True, timeout=SUBPROCESS_TIMEOUT
        )
        return res.stdout.splitlines()
    except Exception:
        pass
    return []


def get_clipboard_data(mime_type: str) -> Optional[bytes]:
    """Return raw bytes for a clipboard mime type, or None if not available."""
    try:
        res = subprocess.run(
            ["wl-paste", "-t", mime_type], capture_output=True, check=True, timeout=SUBPROCESS_TIMEOUT
        )
        return res.stdout
    except Exception:
        pass
    try:
        res = subprocess.run(
            ["xclip", "-selection", "clipboard", "-t", mime_type, "-o"],
            capture_output=True, check=True, timeout=SUBPROCESS_TIMEOUT
        )
        return res.stdout
    except Exception:
        pass
    return None


def _decode_uri(uri: str) -> str:
    """Decode a ``file://`` URI to a local filesystem path."""
    if uri.startswith("file://"):
        return urllib.parse.unquote(uri[7:])
    return uri


def _split_clipboard_uri_list(raw: bytes) -> List[str]:
    """Parse a ``text/uri-list`` clipboard payload into a list of local paths."""
    try:
        uri_str = raw.decode("utf-8")
    except Exception:
        uri_str = raw.decode("latin-1")
    return [line.strip() for line in uri_str.splitlines() if line.strip()]


def _find_image_target(targets: List[str]) -> Tuple[bool, str]:
    """Scan clipboard targets for the first ``image/*`` mime type.

    Returns ``(found, mime)`` — ``found`` is True only when a usable
    image target exists, in which case ``mime`` is the chosen target.
    """
    for t in targets:
        if t.startswith("image/"):
            return True, t
    return False, "image/png"


def handle_clipboard() -> None:
    """Read clipboard contents (files or image) and print a JSON result to stdout."""
    targets = get_clipboard_targets()

    has_uri_list = any("uri-list" in t for t in targets)
    if has_uri_list:
        data = get_clipboard_data("text/uri-list")
        if data:
            lines = _split_clipboard_uri_list(data)
            files_extracted: List[Dict[str, Any]] = []
            for line in lines:
                if line.startswith("file://"):
                    path = _decode_uri(line)
                    file_info = extract_single_file(path)
                    if file_info and file_info.get("status") == "success":
                        files_extracted.append(file_info)
            if files_extracted:
                print(json.dumps({
                    "status": "success",
                    "mode": "files",
                    "files": files_extracted,
                }))
                return

    has_image, img_mime = _find_image_target(targets)
    if has_image:
        import tempfile
        img_bytes = get_clipboard_data(img_mime)
        if img_bytes:
            suffix = mimetypes.guess_extension(img_mime) or ".png"
            temp_path = ""
            try:
                with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp_file:
                    tmp_file.write(img_bytes)
                    temp_path = tmp_file.name

                base64_data = base64.b64encode(img_bytes).decode("utf-8")
                filename = os.path.basename(temp_path)
                print(json.dumps({
                    "status": "success",
                    "mode": "image",
                    "file": {
                        "type": "image",
                        "name": filename,
                        "path": temp_path,
                        "size": len(img_bytes),
                        "mimeType": img_mime,
                        "content": base64_data,
                    },
                }))
            finally:
                if temp_path and os.path.exists(temp_path):
                    try:
                        os.remove(temp_path)
                    except Exception:
                        pass
            return

    print(json.dumps({
        "status": "empty",
        "message": "Clipboard does not contain files or images",
    }))


def main() -> None:
    """CLI entry point: extract one file path or read the clipboard."""
    parser = argparse.ArgumentParser(
        description="Extract text from documents (PDF, DOCX, PPTX, XLSX, images, archives) for KDE AI Chat."
    )
    parser.add_argument("path", nargs="?", help="Path to a file to extract text from")
    parser.add_argument("--clipboard", action="store_true", help="Extract text from clipboard contents (files or images)")
    args = parser.parse_args()

    if args.clipboard:
        handle_clipboard()
    elif args.path:
        result = extract_single_file(args.path)
        print(json.dumps(result))
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
