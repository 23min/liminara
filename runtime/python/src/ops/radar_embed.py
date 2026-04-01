"""Radar embed op — generates embeddings for normalized items."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from providers.embedding import get_provider


def execute(inputs):
    items = json.loads(inputs.get("items", "[]"))
    provider_name = inputs.get("provider", "mock")
    provider_config = json.loads(inputs.get("provider_config", "{}"))

    if not items:
        return {"outputs": {"items": json.dumps([])}}

    provider = get_provider(provider_name, **provider_config)

    texts = [f"{item.get('title', '')} {item.get('clean_text', '')}" for item in items]
    embeddings = provider.embed(texts)

    for item, embedding in zip(items, embeddings):
        item["embedding"] = embedding

    return {"outputs": {"items": json.dumps(items)}}
