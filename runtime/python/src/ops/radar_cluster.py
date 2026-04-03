"""Radar cluster op — HDBSCAN clustering on embeddings."""

import json

import numpy as np
from sklearn.cluster import HDBSCAN


def execute(inputs):
    items = json.loads(inputs.get("items", "[]"))
    embedded_items = json.loads(inputs.get("embedded_items", "[]"))

    if not items:
        return {"outputs": {"clusters": json.dumps([])}}

    # Build embedding lookup from embedded_items
    emb_lookup = {item["id"]: item["embedding"] for item in embedded_items if "embedding" in item}

    # Match items to their embeddings
    matched = []
    for item in items:
        emb = emb_lookup.get(item["id"])
        if emb is not None:
            matched.append((item, emb))

    if not matched:
        return {"outputs": {"clusters": json.dumps([])}}

    # Single item — no clustering needed
    if len(matched) == 1:
        item, emb = matched[0]
        cluster = {
            "cluster_id": "c0",
            "label": _auto_label([item]),
            "items": [_strip_embedding(item)],
            "centroid": emb,
        }
        return {"outputs": {"clusters": json.dumps([cluster])}}

    embeddings = np.array([emb for _, emb in matched])

    # HDBSCAN: data-driven cluster count, noise points become outliers
    min_cluster = max(2, len(matched) // 5)
    clusterer = HDBSCAN(min_cluster_size=min_cluster, metric="euclidean")
    labels = clusterer.fit_predict(embeddings)

    # Group items by cluster label (-1 = noise/outlier)
    cluster_map = {}
    outliers = []
    for i, (item, emb) in enumerate(matched):
        label = int(labels[i])
        if label == -1:
            outliers.append((item, emb))
        else:
            cluster_map.setdefault(label, []).append((item, emb))

    # If HDBSCAN put everything in noise, fall back to single cluster
    if not cluster_map:
        centroid = np.mean(embeddings, axis=0).tolist()
        cluster = {
            "cluster_id": "c0",
            "label": _auto_label([item for item, _ in matched]),
            "items": [_strip_embedding(item) for item, _ in matched],
            "centroid": centroid,
        }
        return {"outputs": {"clusters": json.dumps([cluster])}}

    clusters = []
    for idx, (label, members) in enumerate(sorted(cluster_map.items())):
        member_items = [item for item, _ in members]
        member_embs = np.array([emb for _, emb in members])
        centroid = np.mean(member_embs, axis=0).tolist()
        clusters.append(
            {
                "cluster_id": f"c{idx}",
                "label": _auto_label(member_items),
                "items": [_strip_embedding(item) for item in member_items],
                "centroid": centroid,
            }
        )

    # Outliers go to miscellaneous cluster
    if outliers:
        outlier_embs = np.array([emb for _, emb in outliers])
        centroid = np.mean(outlier_embs, axis=0).tolist()
        clusters.append(
            {
                "cluster_id": f"c{len(clusters)}",
                "label": "Miscellaneous",
                "items": [_strip_embedding(item) for item, _ in outliers],
                "centroid": centroid,
            }
        )

    # Merge clusters with very similar centroids (HDBSCAN over-splitting)
    clusters = _merge_similar_clusters(clusters, emb_lookup)

    return {"outputs": {"clusters": json.dumps(clusters)}}


def _cosine_similarity(a, b):
    """Cosine similarity between two vectors."""
    a = np.asarray(a)
    b = np.asarray(b)
    norm = np.linalg.norm(a) * np.linalg.norm(b)
    if norm == 0:
        return 0.0
    return float(np.dot(a, b) / norm)


def _merge_similar_clusters(clusters, emb_lookup, threshold=0.9):
    """Merge clusters whose centroids have cosine similarity above threshold."""
    merged = True
    while merged:
        merged = False
        for i in range(len(clusters)):
            for j in range(i + 1, len(clusters)):
                sim = _cosine_similarity(clusters[i]["centroid"], clusters[j]["centroid"])
                if sim > threshold:
                    clusters[i]["items"].extend(clusters[j]["items"])
                    # Recompute centroid from original embeddings
                    all_embs = [
                        emb_lookup[item["id"]]
                        for item in clusters[i]["items"]
                        if item["id"] in emb_lookup
                    ]
                    if all_embs:
                        clusters[i]["centroid"] = np.mean(all_embs, axis=0).tolist()
                    clusters[i]["label"] = _auto_label(clusters[i]["items"])
                    clusters.pop(j)
                    merged = True
                    break
            if merged:
                break
    # Re-number cluster_ids
    for idx, cluster in enumerate(clusters):
        cluster["cluster_id"] = f"c{idx}"
    return clusters


def _auto_label(items):
    """Generate a label from the most common words in titles."""
    from collections import Counter

    stop = {
        "the",
        "a",
        "an",
        "is",
        "are",
        "was",
        "were",
        "to",
        "of",
        "in",
        "for",
        "and",
        "on",
        "with",
        "at",
        "by",
        "from",
        "or",
        "as",
        "it",
        "its",
        "this",
        "that",
        "be",
        "has",
        "have",
        "had",
        "not",
        "but",
        "what",
        "how",
        "why",
        "when",
        "who",
        "which",
        "new",
    }
    words = []
    for item in items:
        for w in item.get("title", "").lower().split():
            cleaned = w.strip(".,;:!?\"'()[]{}—–-")
            if cleaned and len(cleaned) > 2 and cleaned not in stop:
                words.append(cleaned)

    if not words:
        return "Untitled cluster"

    top = Counter(words).most_common(3)
    return " / ".join(w for w, _ in top).title()


def _strip_embedding(item):
    return {k: v for k, v in item.items() if k != "embedding"}
