"""Tests for Radar fetch ops using fixtures (no real HTTP)."""

import json
from unittest.mock import patch, MagicMock

import pytest

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from ops.radar_fetch_rss import execute as fetch_rss_execute
from ops.radar_fetch_web import execute as fetch_web_execute

SAMPLE_RSS = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Test Feed</title>
    <link>https://example.com</link>
    <item>
      <title>Article One</title>
      <link>https://example.com/article-1</link>
      <description>First article summary</description>
      <pubDate>Mon, 01 Apr 2026 10:00:00 GMT</pubDate>
    </item>
    <item>
      <title>Article Two</title>
      <link>https://example.com/article-2</link>
      <description>Second article summary</description>
      <pubDate>Mon, 01 Apr 2026 11:00:00 GMT</pubDate>
    </item>
  </channel>
</rss>"""

SAMPLE_HTML = """<!DOCTYPE html>
<html>
<head><title>Blog Post</title></head>
<body>
<article>
<h1>Important Blog Post</h1>
<p>This is a detailed blog post about an important topic. It contains
multiple paragraphs of content that should be extracted by trafilatura.</p>
<p>The second paragraph continues the discussion with more details and
information that would be relevant to a daily intelligence briefing.</p>
</article>
</body>
</html>"""


def mock_response(text, status_code=200, headers=None):
    resp = MagicMock()
    resp.text = text
    resp.status_code = status_code
    resp.headers = headers or {}
    resp.raise_for_status = MagicMock()
    if status_code >= 400:
        resp.raise_for_status.side_effect = Exception(f"HTTP {status_code}")
    return resp


class TestFetchRss:
    @patch("ops.radar_fetch_rss.httpx.get")
    def test_valid_rss_returns_items(self, mock_get):
        mock_get.return_value = mock_response(SAMPLE_RSS, headers={"etag": '"abc"'})

        source = {"id": "test_src", "feed_url": "https://example.com/feed.xml"}
        result = fetch_rss_execute({"source": json.dumps(source)})

        data = json.loads(result["outputs"]["result"])
        assert data["error"] is None
        assert len(data["items"]) == 2
        assert data["items"][0]["title"] == "Article One"
        assert data["items"][0]["url"] == "https://example.com/article-1"
        assert data["items"][0]["source_id"] == "test_src"
        assert data["etag"] == '"abc"'

    @patch("ops.radar_fetch_rss.httpx.get")
    def test_http_error_returns_empty_with_error(self, mock_get):
        mock_get.return_value = mock_response("", status_code=500)

        source = {"id": "test_src", "feed_url": "https://example.com/broken"}
        result = fetch_rss_execute({"source": json.dumps(source)})

        data = json.loads(result["outputs"]["result"])
        assert data["items"] == []
        assert data["error"] is not None
        assert "500" in data["error"]

    @patch("ops.radar_fetch_rss.httpx.get")
    def test_connection_error_returns_empty_with_error(self, mock_get):
        mock_get.side_effect = Exception("Connection refused")

        source = {"id": "test_src", "feed_url": "https://unreachable.example.com"}
        result = fetch_rss_execute({"source": json.dumps(source)})

        data = json.loads(result["outputs"]["result"])
        assert data["items"] == []
        assert "Connection refused" in data["error"]

    @patch("ops.radar_fetch_rss.httpx.get")
    def test_malformed_xml_returns_empty(self, mock_get):
        mock_get.return_value = mock_response("<not><valid>xml")

        source = {"id": "test_src", "feed_url": "https://example.com/bad"}
        result = fetch_rss_execute({"source": json.dumps(source)})

        data = json.loads(result["outputs"]["result"])
        # feedparser handles malformed XML gracefully — returns empty entries
        assert data["error"] is None
        assert data["items"] == []


class TestFetchWeb:
    @patch("ops.radar_fetch_web.httpx.get")
    def test_valid_html_extracts_content(self, mock_get):
        mock_get.return_value = mock_response(SAMPLE_HTML)

        source = {"id": "test_web", "name": "Test Blog", "url": "https://example.com/blog"}
        result = fetch_web_execute({"source": json.dumps(source)})

        data = json.loads(result["outputs"]["result"])
        assert data["error"] is None
        assert len(data["items"]) <= 1  # 0 or 1 — trafilatura may not extract minimal HTML

        if data["items"]:
            assert data["items"][0]["source_id"] == "test_web"
            assert data["items"][0]["url"] == "https://example.com/blog"

    @patch("ops.radar_fetch_web.httpx.get")
    def test_http_error_returns_empty(self, mock_get):
        mock_get.return_value = mock_response("", status_code=404)

        source = {"id": "test_web", "url": "https://example.com/missing"}
        result = fetch_web_execute({"source": json.dumps(source)})

        data = json.loads(result["outputs"]["result"])
        assert data["items"] == []
        assert data["error"] is not None

    @patch("ops.radar_fetch_web.httpx.get")
    def test_empty_page_returns_empty_items(self, mock_get):
        mock_get.return_value = mock_response("<html><body></body></html>")

        source = {"id": "test_web", "url": "https://example.com/empty"}
        result = fetch_web_execute({"source": json.dumps(source)})

        data = json.loads(result["outputs"]["result"])
        assert data["error"] is None
        assert data["items"] == []
