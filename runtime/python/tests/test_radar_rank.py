"""Tests for Radar rank op — novelty scoring and ranking."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from ops.radar_rank import execute as rank_execute

# Fixed reference time for deterministic tests
REF_TIME = "2026-04-02T12:00:00+00:00"


def _make_cluster(cluster_id, items, centroid=None):
    if centroid is None:
        centroid = [0.0] * 32
    return {
        "cluster_id": cluster_id,
        "label": f"Cluster {cluster_id}",
        "items": items,
        "centroid": centroid,
    }


def _make_item(item_id, title="Item", source_id="s1", published=None, url=None):
    item = {
        "id": item_id,
        "title": title,
        "clean_text": f"Text for {title}",
        "url": url or f"https://example.com/{item_id}",
        "source_id": source_id,
    }
    if published:
        item["published"] = published
    return item


def _rank(clusters, historical_centroid=None):
    return rank_execute(
        {
            "clusters": json.dumps(clusters),
            "historical_centroid": json.dumps(historical_centroid or [0.0] * 32),
            "reference_time": REF_TIME,
        }
    )


class TestRank:
    def test_items_ranked_by_novelty_within_cluster(self):
        """Items with higher novelty score come first."""
        items = [
            _make_item("a1", "Low novelty", source_id="s1"),
            _make_item("a2", "High novelty", source_id="s2"),
            _make_item("a3", "Also high", source_id="s3"),
        ]
        clusters = [_make_cluster("c0", items)]

        result = _rank(clusters)

        ranked = json.loads(result["outputs"]["ranked_clusters"])
        for item in ranked[0]["items"]:
            assert "novelty_score" in item

    def test_clusters_ranked_by_max_novelty(self):
        """Cluster with highest max novelty comes first."""
        cluster_a = _make_cluster(
            "c0",
            [_make_item("a1", "Old news", source_id="s1")],
            centroid=[0.1] * 32,
        )
        cluster_b = _make_cluster(
            "c1",
            [
                _make_item("b1", "Breaking", source_id="s1"),
                _make_item("b2", "Breaking too", source_id="s2"),
                _make_item("b3", "Also breaking", source_id="s3"),
            ],
            centroid=[0.9] * 32,
        )

        result = _rank([cluster_a, cluster_b])

        ranked = json.loads(result["outputs"]["ranked_clusters"])
        assert ranked[0]["cluster_id"] == "c1"

    def test_stable_ordering_with_identical_scores(self):
        """Identical novelty scores → deterministic stable ordering."""
        items = [
            _make_item("a1", "Same", source_id="s1"),
            _make_item("a2", "Same", source_id="s1"),
        ]
        clusters = [_make_cluster("c0", items)]

        r1 = _rank(clusters)
        r2 = _rank(clusters)

        ranked1 = json.loads(r1["outputs"]["ranked_clusters"])
        ranked2 = json.loads(r2["outputs"]["ranked_clusters"])
        ids1 = [i["id"] for i in ranked1[0]["items"]]
        ids2 = [i["id"] for i in ranked2[0]["items"]]
        assert ids1 == ids2

    def test_single_item_cluster(self):
        """Single item cluster → rank is trivial."""
        clusters = [_make_cluster("c0", [_make_item("a1", "Only one")])]

        result = _rank(clusters)

        ranked = json.loads(result["outputs"]["ranked_clusters"])
        assert len(ranked) == 1
        assert len(ranked[0]["items"]) == 1
        assert "novelty_score" in ranked[0]["items"][0]

    def test_empty_clusters(self):
        """Empty input → empty output."""
        result = _rank([])

        ranked = json.loads(result["outputs"]["ranked_clusters"])
        assert ranked == []

    def test_recency_boosts_novelty(self):
        """More recent items get higher novelty scores."""
        items = [
            _make_item("old", "Old item", published="2026-03-01T00:00:00Z"),
            _make_item("new", "New item", published="2026-04-02T10:00:00Z"),
        ]
        clusters = [_make_cluster("c0", items)]

        result = _rank(clusters)

        ranked = json.loads(result["outputs"]["ranked_clusters"])
        items_ranked = ranked[0]["items"]
        new_item = next(i for i in items_ranked if i["id"] == "new")
        old_item = next(i for i in items_ranked if i["id"] == "old")
        assert new_item["novelty_score"] > old_item["novelty_score"]

    def test_cluster_score_present(self):
        """Each ranked cluster should have a cluster_score."""
        clusters = [
            _make_cluster("c0", [_make_item("a1", "Item")]),
            _make_cluster("c1", [_make_item("b1", "Other")]),
        ]

        result = _rank(clusters)

        ranked = json.loads(result["outputs"]["ranked_clusters"])
        for c in ranked:
            assert "cluster_score" in c

    def test_same_inputs_same_outputs_with_fixed_time(self):
        """With fixed reference_time, rank op is genuinely pure."""
        items = [
            _make_item("a1", "Item A", published="2026-04-01T00:00:00Z"),
            _make_item("a2", "Item B", published="2026-03-30T00:00:00Z"),
        ]
        clusters = [_make_cluster("c0", items)]

        r1 = _rank(clusters)
        r2 = _rank(clusters)

        assert r1["outputs"]["ranked_clusters"] == r2["outputs"]["ranked_clusters"]

    def test_missing_reference_time_raises(self):
        """Rank op must not silently fall back to wall clock."""
        clusters = [_make_cluster("c0", [_make_item("a1", "Item")])]

        import pytest

        with pytest.raises(ValueError, match="reference_time is required"):
            rank_execute(
                {
                    "clusters": json.dumps(clusters),
                    "historical_centroid": json.dumps([0.0] * 32),
                    "reference_time": "",
                }
            )

    def test_invalid_reference_time_raises(self):
        """Invalid reference_time raises instead of falling back."""
        clusters = [_make_cluster("c0", [_make_item("a1", "Item")])]

        import pytest

        with pytest.raises(ValueError, match="invalid reference_time"):
            rank_execute(
                {
                    "clusters": json.dumps(clusters),
                    "historical_centroid": json.dumps([0.0] * 32),
                    "reference_time": "not-a-date",
                }
            )
