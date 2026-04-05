"""Radar rank op — novelty scoring and cluster/item ranking."""

import json
from collections import Counter
from datetime import datetime

import numpy as np


def execute(inputs):
    clusters = json.loads(inputs.get("clusters", "[]"))
    history_basis = _parse_history_basis(inputs.get("history_basis", ""))
    reference_time = inputs.get("reference_time", "")

    if not clusters:
        return {"outputs": {"ranked_clusters": json.dumps([])}}

    # Parse reference time — makes recency scoring deterministic
    ref_dt = _parse_reference_time(reference_time)

    for cluster in clusters:
        _score_items(cluster, ref_dt)
        # Sort items by novelty_score descending, stable by id
        cluster["items"].sort(key=lambda x: (-x["novelty_score"], x["id"]))
        cluster["cluster_score"] = _cluster_score(cluster)
        cluster["scoring_context"] = {
            "history_basis": history_basis,
            "reference_time": reference_time,
        }

    # Sort clusters by cluster_score descending, stable by cluster_id
    clusters.sort(key=lambda c: (-c["cluster_score"], c["cluster_id"]))

    return {"outputs": {"ranked_clusters": json.dumps(clusters)}}


def _score_items(cluster, ref_dt):
    items = cluster["items"]

    # Source diversity: how many unique sources in this cluster
    source_counts = Counter(item.get("source_id", "") for item in items)
    total_sources = len(source_counts)

    for item in items:
        score = 0.0
        history_component = 0.0

        # Source diversity: item's source appears alongside other sources
        diversity_component = 0.0
        if total_sources > 1:
            diversity_component = min(total_sources / 5.0, 1.0) * 0.3  # Up to 0.3 points
            score += diversity_component

        # Recency
        recency, publication_status = _recency_score(item, ref_dt)
        recency_component = recency * 0.3  # Up to 0.3 points
        score += recency_component

        item["novelty_score"] = round(score, 4)
        item["publication_status"] = publication_status
        item["score_breakdown"] = {
            "history": round(history_component, 4),
            "source_diversity": round(diversity_component, 4),
            "recency": round(recency_component, 4),
        }


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
        raise ValueError(
            "reference_time is required — rank op is :pure and must not use wall clock"
        )
    try:
        return datetime.fromisoformat(ref_str.replace("Z", "+00:00"))
    except (ValueError, TypeError) as e:
        raise ValueError(f"invalid reference_time: {ref_str!r}") from e


def _parse_history_basis(value):
    if not value:
        raise ValueError(
            "history_basis is required — rank must declare whether historical context exists"
        )
    if value != "none":
        raise ValueError(f"unsupported history_basis: {value!r}")
    return value


def _recency_score(item, ref_dt):
    published = item.get("published")
    if not published:
        return 0.5, "missing"  # Default for items without date

    try:
        dt = datetime.fromisoformat(published.replace("Z", "+00:00"))
        hours_old = (ref_dt - dt).total_seconds() / 3600
        # Exponential decay: 1.0 for now, ~0.5 at 24h, ~0.25 at 48h
        return max(0.0, min(1.0, np.exp(-hours_old / 24.0))), "present"
    except (ValueError, TypeError):
        return 0.5, "invalid"


def _cosine_similarity(a, b):
    a, b = np.array(a), np.array(b)
    dot = np.dot(a, b)
    norm = np.linalg.norm(a) * np.linalg.norm(b)
    return float(dot / norm) if norm > 0 else 0.0
