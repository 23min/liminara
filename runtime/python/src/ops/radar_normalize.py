"""Radar normalize op — cleans and normalizes fetched items."""

import hashlib
import html
import json
import re


def strip_html(text):
    """Remove HTML tags and decode entities."""
    text = re.sub(r"<[^>]+>", " ", text)
    text = html.unescape(text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def make_item_id(url, source_id):
    """Deterministic ID from URL + source."""
    key = f"{url}:{source_id}"
    return hashlib.sha256(key.encode("utf-8")).hexdigest()[:16]


def execute(inputs):
    items = json.loads(inputs.get("items", "[]"))

    normalized = []
    for item in items:
        # Prefer full_text (from web extraction), fall back to summary
        raw_text = item.get("full_text") or item.get("summary", "")
        clean_text = strip_html(raw_text)

        normalized.append(
            {
                "id": make_item_id(item.get("url", ""), item.get("source_id", "")),
                "title": item.get("title", ""),
                "clean_text": clean_text,
                "url": item.get("url", ""),
                "published": item.get("published", ""),
                "source_id": item.get("source_id", ""),
            }
        )

    return {"outputs": {"items": json.dumps(normalized)}}
