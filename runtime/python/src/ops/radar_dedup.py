"""Radar dedup op — vector similarity against LanceDB history."""

import json
from datetime import datetime, timezone

import lancedb
import numpy as np
import pyarrow as pa


# Thresholds depend on embedding model. model2vec (potion-base-8M) uses lower
# values than transformer models. These are configurable via inputs.
DEFAULT_DUP_THRESHOLD = 0.55
DEFAULT_AMBIGUOUS_THRESHOLD = 0.35


def _cosine_similarity(a, b):
    a, b = np.array(a), np.array(b)
    dot = np.dot(a, b)
    norm = np.linalg.norm(a) * np.linalg.norm(b)
    return float(dot / norm) if norm > 0 else 0.0


def _get_or_create_table(db, dims):
    try:
        return db.open_table("items")
    except Exception:
        schema = pa.schema([
            pa.field("item_id", pa.string()),
            pa.field("embedding", pa.list_(pa.float32(), dims)),
            pa.field("title", pa.string()),
            pa.field("url", pa.string()),
            pa.field("source_id", pa.string()),
            pa.field("run_id", pa.string()),
            pa.field("created_at", pa.string()),
        ])
        return db.create_table("items", schema=schema)


def execute(inputs):
    items = json.loads(inputs.get("items", "[]"))
    db_path = inputs.get("lancedb_path", "/tmp/radar_lancedb")
    run_id = inputs.get("run_id", "unknown")
    dims = int(inputs.get("dims", "256"))
    dup_threshold = float(inputs.get("dup_threshold", str(DEFAULT_DUP_THRESHOLD)))
    ambiguous_threshold = float(inputs.get("ambiguous_threshold", str(DEFAULT_AMBIGUOUS_THRESHOLD)))

    if not items:
        empty_result = {
            "new_items": [], "ambiguous_items": [], "duplicate_items": [],
        }
        stats = {
            "total_items": 0, "new_count": 0, "ambiguous_count": 0, "duplicate_count": 0,
        }
        return {"outputs": {"result": json.dumps(empty_result), "dedup_stats": json.dumps(stats)}}

    db = lancedb.connect(db_path)
    table = _get_or_create_table(db, dims)

    new_items = []
    ambiguous_items = []
    duplicate_items = []

    history_count = table.count_rows()

    for item in items:
        embedding = item.get("embedding", [])

        if history_count == 0:
            new_items.append(item)
            continue

        results = table.search(embedding).limit(1).to_list()

        if not results:
            new_items.append(item)
            continue

        best = results[0]
        sim = 1.0 - best.get("_distance", 1.0)

        if sim > dup_threshold:
            item["_match_title"] = best.get("title", "")
            item["_match_url"] = best.get("url", "")
            item["_similarity"] = sim
            duplicate_items.append(item)
        elif sim > ambiguous_threshold:
            item["_match_title"] = best.get("title", "")
            item["_match_url"] = best.get("url", "")
            item["_similarity"] = sim
            ambiguous_items.append(item)
        else:
            new_items.append(item)

    # Add new items to history
    if new_items:
        now = datetime.now(timezone.utc).isoformat()
        rows = [
            {
                "item_id": item["id"],
                "embedding": item["embedding"],
                "title": item.get("title", ""),
                "url": item.get("url", ""),
                "source_id": item.get("source_id", ""),
                "run_id": run_id,
                "created_at": now,
            }
            for item in new_items
        ]
        table.add(rows)

    result = {
        "new_items": _strip_embeddings(new_items),
        "ambiguous_items": _strip_embeddings(ambiguous_items),
        "duplicate_items": _strip_embeddings(duplicate_items),
    }
    stats = {
        "total_items": len(items),
        "new_count": len(new_items),
        "ambiguous_count": len(ambiguous_items),
        "duplicate_count": len(duplicate_items),
    }

    return {"outputs": {"result": json.dumps(result), "dedup_stats": json.dumps(stats)}}


def _strip_embeddings(items):
    """Remove embedding vectors from output (too large for artifacts)."""
    return [{k: v for k, v in item.items() if k != "embedding"} for item in items]
