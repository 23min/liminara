"""Radar rank op — novelty scoring and cluster/item ranking."""

import json
from collections import Counter
from datetime import datetime, timezone

import numpy as np


def execute(inputs):
    clusters = json.loads(inputs.get("clusters", "[]"))
    historical_centroid = json.loads(inputs.get("historical_centroid", "[]"))
    reference_time = inputs.get("reference_time", "")

    if not clusters:
        return {"outputs": {"ranked_clusters": json.dumps([])}}

    hist_cent = np.array(historical_centroid) if historical_centroid else None

    # Parse reference time — makes recency scoring deterministic
    ref_dt = _parse_reference_time(reference_time)

    for cluster in clusters:
        _score_items(cluster, hist_cent, ref_dt)
        # Sort items by novelty_score descending, stable by id
        cluster["items"].sort(key=lambda x: (-x["novelty_score"], x["id"]))
        cluster["cluster_score"] = _cluster_score(cluster)

    # Sort clusters by cluster_score descending, stable by cluster_id
    clusters.sort(key=lambda c: (-c["cluster_score"], c["cluster_id"]))

    return {"outputs": {"ranked_clusters": json.dumps(clusters)}}


def _score_items(cluster, historical_centroid, ref_dt):
    items = cluster["items"]
    centroid = np.array(cluster["centroid"]) if cluster.get("centroid") else None

    # Source diversity: how many unique sources in this cluster
    source_counts = Counter(item.get("source_id", "") for item in items)
    total_sources = len(source_counts)

    for item in items:
        score = 0.0

        # Distance from historical centroid (novelty of angle)
        has_history = (
            historical_centroid is not None
            and centroid is not None
            and np.linalg.norm(historical_centroid) > 0
        )
        if has_history:
            sim = _cosine_similarity(centroid, historical_centroid)
            score += (1.0 - sim) * 0.4  # Up to 0.4 points

        # Source diversity: item's source appears alongside other sources
        if total_sources > 1:
            score += min(total_sources / 5.0, 1.0) * 0.3  # Up to 0.3 points

        # Recency
        recency = _recency_score(item, ref_dt)
        score += recency * 0.3  # Up to 0.3 points

        item["novelty_score"] = round(score, 4)


def _cluster_score(cluster):
    items = cluster["items"]
    if not items:
        return 0.0

    max_novelty = max(item.get("novelty_score", 0) for item in items)
    size_bonus = min(len(items) / 10.0, 0.5)  # Up to 0.5 for large clusters

    source_ids = set(item.get("source_id", "") for item in items)
    diversity_bonus = min(len(source_ids) / 5.0, 0.5)  # Up to 0.5

    return round(max_novelty + size_bonus + diversity_bonus, 4)


def _parse_reference_time(ref_str):
    if not ref_str:
        raise ValueError("reference_time is required — rank op is :pure and must not use wall clock")
    try:
        return datetime.fromisoformat(ref_str.replace("Z", "+00:00"))
    except (ValueError, TypeError) as e:
        raise ValueError(f"invalid reference_time: {ref_str!r}") from e


def _recency_score(item, ref_dt):
    published = item.get("published")
    if not published:
        return 0.5  # Default for items without date

    try:
        dt = datetime.fromisoformat(published.replace("Z", "+00:00"))
        hours_old = (ref_dt - dt).total_seconds() / 3600
        # Exponential decay: 1.0 for now, ~0.5 at 24h, ~0.25 at 48h
        return max(0.0, min(1.0, np.exp(-hours_old / 24.0)))
    except (ValueError, TypeError):
        return 0.5


def _cosine_similarity(a, b):
    a, b = np.array(a), np.array(b)
    dot = np.dot(a, b)
    norm = np.linalg.norm(a) * np.linalg.norm(b)
    return float(dot / norm) if norm > 0 else 0.0
