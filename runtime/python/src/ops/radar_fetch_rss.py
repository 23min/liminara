"""Radar RSS/Atom fetch op — retrieves and parses feeds via feedparser + httpx."""

import json

import feedparser
import httpx


def execute(inputs):
    source = json.loads(inputs.get("source", "{}"))
    feed_url = source.get("feed_url") or source.get("url", "")
    source_id = source.get("id", "unknown")
    timeout = inputs.get("timeout", 15)

    try:
        response = httpx.get(feed_url, timeout=timeout, follow_redirects=True)
        response.raise_for_status()
    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        return {
            "outputs": {
                "result": json.dumps({
                    "items": [],
                    "error": error,
                    "source_id": source_id,
                })
            },
            "warnings": [
                {
                    "code": "radar_fetch_rss_failed",
                    "severity": "degraded",
                    "summary": f"Failed to fetch RSS source {source_id}",
                    "cause": error,
                    "remediation": "Check source availability, URL, or feed health; Radar will continue with partial coverage",
                    "affected_outputs": ["result"],
                }
            ],
        }

    feed = feedparser.parse(response.text)

    items = []
    for entry in feed.entries:
        item = {
            "title": entry.get("title", ""),
            "url": entry.get("link", ""),
            "summary": entry.get("summary", ""),
            "published": entry.get("published", ""),
            "source_id": source_id,
        }
        if item["url"]:
            items.append(item)

    etag = response.headers.get("etag", "")
    last_modified = response.headers.get("last-modified", "")

    return {
        "outputs": {
            "result": json.dumps({
                "items": items,
                "error": None,
                "source_id": source_id,
                "etag": etag,
                "last_modified": last_modified,
            })
        }
    }
