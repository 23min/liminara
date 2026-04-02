"""Tests for Radar cluster op — HDBSCAN clustering on embeddings."""

import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from ops.radar_cluster import execute as cluster_execute


def _make_item(item_id, title, embedding, source_id="s1"):
    return {
        "id": item_id,
        "title": title,
        "clean_text": f"Text for {title}",
        "url": f"https://example.com/{item_id}",
        "source_id": source_id,
    }


def _make_embedded(item_id, title, embedding, source_id="s1"):
    item = _make_item(item_id, title, embedding, source_id)
    item["embedding"] = embedding
    return item


def _cluster_vec(topic_idx, dims=32, noise=0.01):
    """Generate a vector clearly belonging to a topic cluster."""
    rng = np.random.RandomState(hash(f"topic_{topic_idx}") % 2**31)
    base = rng.randn(dims).astype(float)
    base = base / np.linalg.norm(base)
    perturbation = np.random.RandomState(np.random.randint(0, 2**31)).randn(dims) * noise
    return (base + perturbation).tolist()


class TestCluster:
    def test_distinct_topics_form_separate_clusters(self):
        """10 items about 3 distinct topics → at least 2 clusters."""
        items = []
        embedded = []
        for topic in range(3):
            for i in range(4 if topic < 2 else 2):
                item_id = f"t{topic}_i{i}"
                emb = _cluster_vec(topic, dims=32, noise=0.02)
                items.append(_make_item(item_id, f"Topic {topic} item {i}", emb))
                embedded.append(_make_embedded(item_id, f"Topic {topic} item {i}", emb))

        result = cluster_execute(
            {
                "items": json.dumps(items),
                "embedded_items": json.dumps(embedded),
            }
        )

        clusters = json.loads(result["outputs"]["clusters"])
        assert len(clusters) >= 2
        # Every item appears in exactly one cluster
        all_item_ids = set()
        for c in clusters:
            for item in c["items"]:
                assert item["id"] not in all_item_ids
                all_item_ids.add(item["id"])
        assert all_item_ids == {item["id"] for item in items}

    def test_same_topic_forms_one_cluster(self):
        """All items on same topic → 1 cluster."""
        items = []
        embedded = []
        for i in range(5):
            emb = _cluster_vec(0, dims=32, noise=0.01)
            items.append(_make_item(f"a{i}", f"Same topic {i}", emb))
            embedded.append(_make_embedded(f"a{i}", f"Same topic {i}", emb))

        result = cluster_execute(
            {
                "items": json.dumps(items),
                "embedded_items": json.dumps(embedded),
            }
        )

        clusters = json.loads(result["outputs"]["clusters"])
        assert len(clusters) == 1

    def test_single_item(self):
        """1 item → 1 cluster with 1 item."""
        emb = [0.5] * 32
        items = [_make_item("a1", "Only item", emb)]
        embedded = [_make_embedded("a1", "Only item", emb)]

        result = cluster_execute(
            {
                "items": json.dumps(items),
                "embedded_items": json.dumps(embedded),
            }
        )

        clusters = json.loads(result["outputs"]["clusters"])
        assert len(clusters) == 1
        assert len(clusters[0]["items"]) == 1

    def test_empty_input(self):
        """Empty input → empty clusters."""
        result = cluster_execute(
            {
                "items": json.dumps([]),
                "embedded_items": json.dumps([]),
            }
        )

        clusters = json.loads(result["outputs"]["clusters"])
        assert clusters == []

    def test_cluster_structure(self):
        """Each cluster has: cluster_id, label, items, centroid."""
        emb = [0.5] * 32
        items = [_make_item("a1", "Test item", emb)]
        embedded = [_make_embedded("a1", "Test item", emb)]

        result = cluster_execute(
            {
                "items": json.dumps(items),
                "embedded_items": json.dumps(embedded),
            }
        )

        clusters = json.loads(result["outputs"]["clusters"])
        c = clusters[0]
        assert "cluster_id" in c
        assert "label" in c
        assert "items" in c
        assert "centroid" in c
        assert isinstance(c["centroid"], list)
        assert len(c["centroid"]) == 32

    def test_outliers_in_miscellaneous(self):
        """Items far from any cluster go to a miscellaneous cluster."""
        items = []
        embedded = []
        # 6 items in tight cluster
        for i in range(6):
            emb = _cluster_vec(0, dims=32, noise=0.01)
            items.append(_make_item(f"c{i}", f"Cluster item {i}", emb))
            embedded.append(_make_embedded(f"c{i}", f"Cluster item {i}", emb))
        # 1 outlier with random embedding
        rng = np.random.RandomState(999)
        outlier_emb = rng.randn(32).tolist()
        items.append(_make_item("outlier", "Random outlier", outlier_emb))
        embedded.append(_make_embedded("outlier", "Random outlier", outlier_emb))

        result = cluster_execute(
            {
                "items": json.dumps(items),
                "embedded_items": json.dumps(embedded),
            }
        )

        clusters = json.loads(result["outputs"]["clusters"])
        # All items accounted for
        total = sum(len(c["items"]) for c in clusters)
        assert total == 7

    def test_embeddings_not_in_output(self):
        """Cluster output items should not contain embedding vectors."""
        emb = [0.5] * 32
        items = [_make_item("a1", "Test", emb)]
        embedded = [_make_embedded("a1", "Test", emb)]

        result = cluster_execute(
            {
                "items": json.dumps(items),
                "embedded_items": json.dumps(embedded),
            }
        )

        clusters = json.loads(result["outputs"]["clusters"])
        for c in clusters:
            for item in c["items"]:
                assert "embedding" not in item
