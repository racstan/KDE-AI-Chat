"""How a tools/call result becomes the text the model gets (mcp_clients.format_result)."""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "org.kde.plasma.kdeaichat", "contents", "ui", "kdeaichat"))
from mcp_clients import format_result  # noqa: E402


def test_text_items_are_joined_and_error_flag_kept():
    assert format_result({"content": [{"type": "text", "text": "a"}, {"type": "text", "text": "b"}], "isError": True}) == ("a\nb", True)


def test_media_and_links_become_placeholders():
    text, error = format_result({"content": [{"type": "image", "mimeType": "image/png", "data": "A" * 4096},
                                             {"type": "resource_link", "uri": "file:///x", "mimeType": "text/plain"}]})
    assert text == "[image: image/png, 3 KB]\n[resource: file:///x, text/plain]"
    assert error is False


def test_embedded_resource_text_is_returned():
    text, _ = format_result({"content": [{"type": "resource", "resource": {"uri": "file:///notes.txt", "text": "hello"}},
                                         {"type": "resource", "resource": {"uri": "file:///a.bin", "mimeType": "application/octet-stream", "blob": "AA=="}}]})
    assert text == "hello\n[resource: file:///a.bin, application/octet-stream]"


def test_structured_content_only_without_text():
    assert format_result({"content": [], "structuredContent": {"n": 1}}) == ('{"n": 1}', False)
    assert format_result({"content": [{"type": "text", "text": "t"}], "structuredContent": {"n": 1}}) == ("t", False)
