"""Tests for decision_store.py — decision record storage.

Spec reference: docs/analysis/11_Data_Model_Spec.md

Decision records: {runs_root}/{run_id}/decisions/{node_id}.json
Canonical JSON. decision_hash computed over all fields except decision_hash itself.
"""

import hashlib
import json
from pathlib import Path

import pytest

from liminara.decision_store import DecisionStore
from liminara.hash import canonical_json


@pytest.fixture
def decision_store(tmp_path: Path) -> DecisionStore:
    """Create a DecisionStore rooted in a temp directory."""
    return DecisionStore(runs_root=tmp_path / "runs", run_id="test-run-001")


def _sample_decision(node_id: str = "summarize-001") -> dict:
    """Return a sample decision record (without decision_hash — store computes it)."""
    return {
        "node_id": node_id,
        "op_id": "summarize",
        "op_version": "1.0",
        "decision_type": "llm_response",
        "inputs": {
            "prompt_hash": "sha256:" + "aa" * 32,
            "model_id": "claude-sonnet-4-6",
            "model_version": "20251001",
            "temperature": 0.7,
        },
        "output": {
            "response_hash": "sha256:" + "bb" * 32,
            "token_usage": {"input": 1024, "output": 512},
        },
        "recorded_at": "2026-03-14T12:00:00.000Z",
    }


class TestWriteAndRead:
    """Write decision → read decision round-trip."""

    def test_write_returns_hash(self, decision_store: DecisionStore):
        """write() returns the decision_hash."""
        record = _sample_decision()
        result = decision_store.write(record)
        assert result.startswith("sha256:")
        assert len(result) == 7 + 64

    def test_read_returns_record(self, decision_store: DecisionStore):
        """read() returns the full record including decision_hash."""
        record = _sample_decision()
        decision_store.write(record)
        stored = decision_store.read("summarize-001")
        assert stored["node_id"] == "summarize-001"
        assert stored["op_id"] == "summarize"
        assert stored["decision_type"] == "llm_response"
        assert "decision_hash" in stored

    def test_round_trip_preserves_all_fields(self, decision_store: DecisionStore):
        """All input fields are preserved after write + read."""
        record = _sample_decision()
        decision_store.write(record)
        stored = decision_store.read("summarize-001")
        for key, value in record.items():
            assert stored[key] == value

    def test_read_nonexistent_raises(self, decision_store: DecisionStore):
        """Reading a non-existent node_id raises an error."""
        with pytest.raises(FileNotFoundError):
            decision_store.read("nonexistent")


class TestDecisionHash:
    """decision_hash = sha256(canonical_json(all fields except decision_hash))."""

    def test_hash_is_correct(self, decision_store: DecisionStore):
        """decision_hash matches manual computation."""
        record = _sample_decision()
        decision_hash = decision_store.write(record)

        # Manual computation: hash all fields except decision_hash
        manual_hash = "sha256:" + hashlib.sha256(canonical_json(record)).hexdigest()
        assert decision_hash == manual_hash

    def test_hash_excludes_itself(self, decision_store: DecisionStore):
        """decision_hash is NOT included in the hash input."""
        record = _sample_decision()
        decision_store.write(record)
        stored = decision_store.read("summarize-001")

        # Recompute: exclude decision_hash from input
        without_hash = {k: v for k, v in stored.items() if k != "decision_hash"}
        expected = "sha256:" + hashlib.sha256(canonical_json(without_hash)).hexdigest()
        assert stored["decision_hash"] == expected

    def test_different_inputs_different_hashes(self, decision_store: DecisionStore):
        """Different decision records produce different hashes."""
        r1 = _sample_decision("node-a")
        r2 = _sample_decision("node-b")
        h1 = decision_store.write(r1)
        h2 = decision_store.write(r2)
        assert h1 != h2


class TestFileFormat:
    """On-disk format: canonical JSON at {runs_root}/{run_id}/decisions/{node_id}.json."""

    def test_file_location(self, decision_store: DecisionStore):
        """Decision file is at the correct path."""
        record = _sample_decision()
        decision_store.write(record)
        expected_path = (
            decision_store.runs_root / "test-run-001" / "decisions" / "summarize-001.json"
        )
        assert expected_path.exists()

    def test_canonical_json_format(self, decision_store: DecisionStore):
        """File content is canonical JSON (sorted keys, no whitespace)."""
        record = _sample_decision()
        decision_store.write(record)
        path = decision_store.runs_root / "test-run-001" / "decisions" / "summarize-001.json"
        content = path.read_bytes()

        # Verify it's valid JSON
        parsed = json.loads(content)
        assert isinstance(parsed, dict)

        # Verify keys are sorted at top level
        keys = list(parsed.keys())
        assert keys == sorted(keys)

        # Verify no unnecessary whitespace (canonical JSON has no spaces after : or ,)
        text = content.decode("utf-8")
        assert ": " not in text  # no space after colon
