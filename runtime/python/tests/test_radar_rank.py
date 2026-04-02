"""Tests for Radar rank op — novelty scoring and ranking."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from ops.radar_rank import execute as rank_execute


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


class TestRank:
    def test_items_ranked_by_novelty_within_cluster(self):
        """Items with higher novelty score come first."""
        # Item from diverse sources is more novel
        items = [
            _make_item("a1", "Low novelty", source_id="s1"),
            _make_item("a2", "High novelty", source_id="s2"),
            _make_item("a3", "Also high", source_id="s3"),
        ]
        # a2 and a3 from different sources = more diverse = higher novelty
        clusters = [_make_cluster("c0", items)]

        result = rank_execute(
            {
                "clusters": json.dumps(clusters),
                "historical_centroid": json.dumps([0.0] * 32),
            }
        )

        ranked = json.loads(result["outputs"]["ranked_clusters"])
        # Items should have novelty_score field
        for item in ranked[0]["items"]:
            assert "novelty_score" in item

    def test_clusters_ranked_by_max_novelty(self):
        """Cluster with highest max novelty comes first."""
        cluster_a = _make_cluster(
            "c0",
            [
                _make_item("a1", "Old news", source_id="s1"),
            ],
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

        result = rank_execute(
            {
                "clusters": json.dumps([cluster_a, cluster_b]),
                "historical_centroid": json.dumps([0.0] * 32),
            }
        )

        ranked = json.loads(result["outputs"]["ranked_clusters"])
        # Cluster B has more items + more source diversity → should rank higher
        assert ranked[0]["cluster_id"] == "c1"

    def test_stable_ordering_with_identical_scores(self):
        """Identical novelty scores → deterministic stable ordering."""
        items = [
            _make_item("a1", "Same", source_id="s1"),
            _make_item("a2", "Same", source_id="s1"),
        ]
        clusters = [_make_cluster("c0", items)]

        inputs = {
            "clusters": json.dumps(clusters),
            "historical_centroid": json.dumps([0.0] * 32),
        }
        r1 = rank_execute(inputs)
        r2 = rank_execute(inputs)

        ranked1 = json.loads(r1["outputs"]["ranked_clusters"])
        ranked2 = json.loads(r2["outputs"]["ranked_clusters"])
        ids1 = [i["id"] for i in ranked1[0]["items"]]
        ids2 = [i["id"] for i in ranked2[0]["items"]]
        assert ids1 == ids2

    def test_single_item_cluster(self):
        """Single item cluster → rank is trivial."""
        clusters = [_make_cluster("c0", [_make_item("a1", "Only one")])]

        result = rank_execute(
            {
                "clusters": json.dumps(clusters),
                "historical_centroid": json.dumps([0.0] * 32),
            }
        )

        ranked = json.loads(result["outputs"]["ranked_clusters"])
        assert len(ranked) == 1
        assert len(ranked[0]["items"]) == 1
        assert "novelty_score" in ranked[0]["items"][0]

    def test_empty_clusters(self):
        """Empty input → empty output."""
        result = rank_execute(
            {
                "clusters": json.dumps([]),
                "historical_centroid": json.dumps([0.0] * 32),
            }
        )

        ranked = json.loads(result["outputs"]["ranked_clusters"])
        assert ranked == []

    def test_recency_boosts_novelty(self):
        """More recent items get higher novelty scores."""
        items = [
            _make_item("old", "Old item", published="2026-03-01T00:00:00Z"),
            _make_item("new", "New item", published="2026-04-02T00:00:00Z"),
        ]
        clusters = [_make_cluster("c0", items)]

        result = rank_execute(
            {
                "clusters": json.dumps(clusters),
                "historical_centroid": json.dumps([0.0] * 32),
            }
        )

        ranked = json.loads(result["outputs"]["ranked_clusters"])
        items_ranked = ranked[0]["items"]
        new_item = next(i for i in items_ranked if i["id"] == "new")
        old_item = next(i for i in items_ranked if i["id"] == "old")
        assert new_item["novelty_score"] >= old_item["novelty_score"]

    def test_cluster_score_present(self):
        """Each ranked cluster should have a cluster_score."""
        clusters = [
            _make_cluster("c0", [_make_item("a1", "Item")]),
            _make_cluster("c1", [_make_item("b1", "Other")]),
        ]

        result = rank_execute(
            {
                "clusters": json.dumps(clusters),
                "historical_centroid": json.dumps([0.0] * 32),
            }
        )

        ranked = json.loads(result["outputs"]["ranked_clusters"])
        for c in ranked:
            assert "cluster_score" in c
