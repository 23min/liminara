"""Integration tests — end-to-end run with multiple ops and decisions.

Spec reference: M-CS-03-decorators.md § test_integration.py

Tests a full run with one plain @op and one stacked @op+@decision,
verifying the complete event sequence, hash chain, and on-disk artifacts.
"""

import json
from pathlib import Path

import pytest

from liminara.config import LiminaraConfig
from liminara.decorators import decision, op
from liminara.run import run


@pytest.fixture
def config(tmp_path: Path) -> LiminaraConfig:
    return LiminaraConfig(
        store_root=tmp_path / "store" / "artifacts",
        runs_root=tmp_path / "runs",
    )


@op(name="load", version="1.0", determinism="pure")
def load_data(text):
    """A plain @op — no decision."""
    return text.upper()


@op(name="summarize", version="1.0", determinism="recordable")
@decision(decision_type="llm_response")
def summarize(text):
    """A stacked @op + @decision."""
    return f"Summary: {text[:20]}"


class TestEndToEndEventSequence:
    """Full run produces correct event sequence."""

    def test_event_sequence(self, config: LiminaraConfig):
        """Full event sequence for one plain @op and one stacked @op+@decision."""
        with run("integration-test", "0.1.0", config=config) as r:
            result1 = load_data("hello world")
            result2 = summarize(result1)

        events = r.event_log.read_all()
        event_types = [e["event_type"] for e in events]
        assert event_types == [
            "run_started",
            "op_started",
            "op_completed",
            "op_started",
            "decision_recorded",
            "op_completed",
            "run_completed",
        ]

        # Verify return values flowed through
        assert result1 == "HELLO WORLD"
        assert result2 == "Summary: HELLO WORLD"


class TestEndToEndHashChain:
    """Hash chain integrity after full run."""

    def test_hash_chain_valid(self, config: LiminaraConfig):
        """Hash chain verifies successfully after a full run."""
        with run("integration-test", "0.1.0", config=config) as r:
            load_data("test input")
            summarize("SOME TEXT FOR SUMMARY")

        valid, error = r.event_log.verify()
        assert valid is True, f"Hash chain failed: {error}"


class TestEndToEndOnDisk:
    """All artifacts, decisions, and seal exist on disk."""

    def test_all_artifacts_exist(self, config: LiminaraConfig):
        """All artifacts, decision records, and seal.json exist with correct content."""
        with run("integration-test", "0.1.0", config=config) as r:
            load_data("hello")
            summarize("HELLO")

        events = r.event_log.read_all()

        # All op input/output artifacts exist in store
        for e in events:
            if e["event_type"] == "op_started":
                for h in e["payload"]["input_hashes"]:
                    assert r.artifact_store.read(h) is not None
            if e["event_type"] == "op_completed":
                for h in e["payload"]["output_hashes"]:
                    assert r.artifact_store.read(h) is not None

        # Decision record exists
        decision_events = [e for e in events if e["event_type"] == "decision_recorded"]
        assert len(decision_events) == 1
        node_id = decision_events[0]["payload"]["node_id"]
        decision_path = config.runs_root / r.run_id / "decisions" / f"{node_id}.json"
        assert decision_path.exists()

        # Seal exists and matches
        seal_path = config.runs_root / r.run_id / "seal.json"
        assert seal_path.exists()
        seal = json.loads(seal_path.read_bytes())
        assert seal["run_seal"] == events[-1]["event_hash"]
        assert seal["event_count"] == len(events)
