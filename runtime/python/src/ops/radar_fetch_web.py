"""Radar web fetch op — retrieves a web page and extracts content via trafilatura."""

import json

import httpx
import trafilatura


def execute(inputs):
    source = json.loads(inputs.get("source", "{}"))
    url = source.get("url", "")
    source_id = source.get("id", "unknown")
    timeout = inputs.get("timeout", 15)

    try:
        response = httpx.get(url, timeout=timeout, follow_redirects=True)
        response.raise_for_status()
    except Exception as e:
        return {
            "outputs": {
                "result": json.dumps({
                    "items": [],
                    "error": f"{type(e).__name__}: {e}",
                    "source_id": source_id,
                })
            }
        }

    extracted = trafilatura.extract(response.text, include_links=True, include_tables=False)

    items = []
    if extracted:
        items.append({
            "title": source.get("name", url),
            "url": url,
            "summary": extracted[:500] if len(extracted) > 500 else extracted,
            "published": "",
            "source_id": source_id,
            "full_text": extracted,
        })

    return {
        "outputs": {
            "result": json.dumps({
                "items": items,
                "error": None,
                "source_id": source_id,
            })
        }
    }
