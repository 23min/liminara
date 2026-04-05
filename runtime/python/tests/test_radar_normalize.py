"""Tests for Radar normalize op."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from ops.radar_normalize import execute as normalize_execute


class TestNormalize:
    def test_normalize_uses_canonical_success_shape(self):
        result = normalize_execute({"items": json.dumps([])})

        assert set(result.keys()) == {"outputs"}

    def test_rss_items_pass_through_summary(self):
        items = [
            {
                "title": "Article One",
                "url": "https://example.com/1",
                "summary": "This is a clean summary.",
                "published": "2026-04-01",
                "source_id": "src_1",
            }
        ]
        result = normalize_execute({"items": json.dumps(items)})
        normalized = json.loads(result["outputs"]["items"])

        assert len(normalized) == 1
        assert normalized[0]["title"] == "Article One"
        assert normalized[0]["clean_text"] == "This is a clean summary."
        assert normalized[0]["url"] == "https://example.com/1"
        assert normalized[0]["source_id"] == "src_1"
        assert "id" in normalized[0]

    def test_html_content_extracted(self):
        items = [
            {
                "title": "Blog Post",
                "url": "https://example.com/blog",
                "summary": "<p>This is <b>HTML</b> content with <a href='#'>links</a>.</p>",
                "published": "",
                "source_id": "src_2",
            }
        ]
        result = normalize_execute({"items": json.dumps(items)})
        normalized = json.loads(result["outputs"]["items"])

        assert len(normalized) == 1
        # HTML tags should be stripped
        text = normalized[0]["clean_text"]
        assert "<p>" not in text
        assert "<b>" not in text
        assert "HTML" in text

    def test_empty_items_returns_empty(self):
        result = normalize_execute({"items": json.dumps([])})
        normalized = json.loads(result["outputs"]["items"])
        assert normalized == []

    def test_item_gets_deterministic_id(self):
        items = [
            {
                "title": "Test",
                "url": "https://example.com/test",
                "summary": "Summary",
                "published": "",
                "source_id": "src_1",
            }
        ]
        result1 = normalize_execute({"items": json.dumps(items)})
        result2 = normalize_execute({"items": json.dumps(items)})

        items1 = json.loads(result1["outputs"]["items"])
        items2 = json.loads(result2["outputs"]["items"])

        assert items1[0]["id"] == items2[0]["id"]

    def test_special_characters_preserved(self):
        items = [
            {
                "title": 'Ölämning & "quotes"',
                "url": "https://example.com/ö",
                "summary": "Café résumé naïve",
                "published": "",
                "source_id": "src_1",
            }
        ]
        result = normalize_execute({"items": json.dumps(items)})
        normalized = json.loads(result["outputs"]["items"])

        assert "Café" in normalized[0]["clean_text"]
        assert "Ölämning" in normalized[0]["title"]

    def test_full_text_used_when_available(self):
        items = [
            {
                "title": "Web Page",
                "url": "https://example.com/page",
                "summary": "Short summary",
                "full_text": (
                    "This is the full extracted text from the web page, "
                    "much longer than the summary."
                ),
                "published": "",
                "source_id": "src_1",
            }
        ]
        result = normalize_execute({"items": json.dumps(items)})
        normalized = json.loads(result["outputs"]["items"])

        assert "full extracted text" in normalized[0]["clean_text"]
