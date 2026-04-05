"""Tests for Radar embed and dedup ops using mock provider and temp LanceDB."""

import json
import sys
from pathlib import Path

import lancedb
import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from ops.radar_embed import execute as embed_execute
from ops.radar_dedup import execute as dedup_execute


class TestEmbed:
    def test_embed_uses_canonical_success_shape(self):
        result = embed_execute({
            "items": json.dumps([]),
            "provider": "mock",
            "provider_config": json.dumps({}),
        })

        assert set(result.keys()) == {"outputs"}

    def test_items_get_embeddings(self):
        items = [
            {"id": "a1", "title": "Test", "clean_text": "Hello world", "url": "https://a.com"},
            {"id": "a2", "title": "Test 2", "clean_text": "Goodbye world", "url": "https://b.com"},
        ]
        result = embed_execute({
            "items": json.dumps(items),
            "provider": "mock",
            "provider_config": json.dumps({"dims": 32}),
        })

        embedded = json.loads(result["outputs"]["items"])
        assert len(embedded) == 2
        assert "embedding" in embedded[0]
        assert len(embedded[0]["embedding"]) == 32
        assert isinstance(embedded[0]["embedding"][0], float)

    def test_empty_items(self):
        result = embed_execute({
            "items": json.dumps([]),
            "provider": "mock",
            "provider_config": json.dumps({}),
        })
        embedded = json.loads(result["outputs"]["items"])
        assert embedded == []

    def test_deterministic_embeddings(self):
        items = [{"id": "a1", "title": "T", "clean_text": "Same text", "url": "https://a.com"}]
        r1 = embed_execute({"items": json.dumps(items), "provider": "mock", "provider_config": json.dumps({})})
        r2 = embed_execute({"items": json.dumps(items), "provider": "mock", "provider_config": json.dumps({})})

        e1 = json.loads(r1["outputs"]["items"])[0]["embedding"]
        e2 = json.loads(r2["outputs"]["items"])[0]["embedding"]
        assert e1 == e2


class TestDedup:
    def test_dedup_uses_canonical_success_shape(self, tmp_path):
        result = dedup_execute({
            "items": json.dumps([]),
            "lancedb_path": str(tmp_path / "lancedb"),
            "dims": "32",
        })

        assert set(result.keys()) == {"outputs"}

    def test_novel_items_against_empty_history(self, tmp_path):
        items = [
            {"id": "a1", "title": "Novel", "clean_text": "Brand new story", "url": "https://a.com",
             "embedding": [0.1] * 32, "source_id": "s1"},
        ]
        result = dedup_execute({
            "items": json.dumps(items),
            "lancedb_path": str(tmp_path / "lancedb"),
            "run_id": "run_001",
            "dims": "32",
        })

        output = json.loads(result["outputs"]["result"])
        assert len(output["new_items"]) == 1
        assert len(output["ambiguous_items"]) == 0
        assert len(output["duplicate_items"]) == 0

    def test_duplicate_detected(self, tmp_path):
        db_path = str(tmp_path / "lancedb")

        # First run — seed history
        items1 = [
            {"id": "a1", "title": "Story A", "clean_text": "Content A", "url": "https://a.com",
             "embedding": [0.5] * 32, "source_id": "s1"},
        ]
        dedup_execute({
            "items": json.dumps(items1),
            "lancedb_path": db_path,
            "run_id": "run_001",
            "dims": "32",
        })

        # Second run — identical embedding → duplicate
        items2 = [
            {"id": "a2", "title": "Story A copy", "clean_text": "Content A", "url": "https://b.com",
             "embedding": [0.5] * 32, "source_id": "s2"},
        ]
        result = dedup_execute({
            "items": json.dumps(items2),
            "lancedb_path": db_path,
            "run_id": "run_002",
            "dims": "32",
        })

        output = json.loads(result["outputs"]["result"])
        assert len(output["duplicate_items"]) == 1
        assert len(output["new_items"]) == 0

    def test_novel_item_added_to_history(self, tmp_path):
        db_path = str(tmp_path / "lancedb")

        # First item
        items1 = [
            {"id": "a1", "title": "Story A", "clean_text": "A", "url": "https://a.com",
             "embedding": [1.0] + [0.0] * 31, "source_id": "s1"},
        ]
        dedup_execute({"items": json.dumps(items1), "lancedb_path": db_path, "run_id": "r1", "dims": "32"})

        # Very different item → new
        items2 = [
            {"id": "a2", "title": "Story B", "clean_text": "B", "url": "https://b.com",
             "embedding": [0.0] * 31 + [1.0], "source_id": "s2"},
        ]
        result = dedup_execute({"items": json.dumps(items2), "lancedb_path": db_path, "run_id": "r2", "dims": "32"})

        output = json.loads(result["outputs"]["result"])
        assert len(output["new_items"]) == 1

    def test_empty_input(self, tmp_path):
        result = dedup_execute({
            "items": json.dumps([]),
            "lancedb_path": str(tmp_path / "lancedb"),
            "run_id": "r1",
            "dims": "32",
        })
        output = json.loads(result["outputs"]["result"])
        assert output["new_items"] == []
        assert output["ambiguous_items"] == []
        assert output["duplicate_items"] == []

    def test_dedup_stats_produced(self, tmp_path):
        items = [
            {"id": "a1", "title": "T", "clean_text": "C", "url": "https://a.com",
             "embedding": [0.1] * 32, "source_id": "s1"},
        ]
        result = dedup_execute({
            "items": json.dumps(items),
            "lancedb_path": str(tmp_path / "lancedb"),
            "run_id": "r1",
            "dims": "32",
        })

        stats = json.loads(result["outputs"]["dedup_stats"])
        assert "total_items" in stats
        assert "new_count" in stats
        assert "duplicate_count" in stats
        assert "ambiguous_count" in stats

    def test_runtime_context_controls_persisted_run_id_and_created_at(self, tmp_path):
        db_path = str(tmp_path / "lancedb")
        started_at = "2026-04-05T14:20:00+00:00"

        items = [
            {"id": "a1", "title": "Story A", "clean_text": "A", "url": "https://a.com",
             "embedding": [0.1] * 32, "source_id": "s1"},
        ]

        dedup_execute(
            {
                "items": json.dumps(items),
                "lancedb_path": db_path,
                "dims": "32",
            },
            {"run_id": "runtime-run-123", "started_at": started_at},
        )

        table = lancedb.connect(db_path).open_table("items")
        rows = table.search([0.1] * 32).limit(1).to_list()

        assert len(rows) == 1
        assert rows[0]["run_id"] == "runtime-run-123"
        assert rows[0]["created_at"] == started_at
