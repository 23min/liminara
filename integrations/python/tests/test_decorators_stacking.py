"""Tests for decorator stacking — @op outside, @decision inside.

Spec reference: M-CS-03-decorators.md § Stacking @op and @decision

When @op is the outer decorator and @decision is inner:
  op_started → decision_recorded → op_completed
The decision's node_id matches the op's node_id.
"""

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


class TestEventOrder:
    """Events emitted in correct order."""

    def test_op_decision_event_sequence(self, config: LiminaraConfig):
        """Events: op_started → decision_recorded → op_completed."""

        @op(name="choose", version="1.0", determinism="recordable")
        @decision(decision_type="llm_response")
        def choose(x):
            return f"chose {x}"

        with run("mypack", "1.0.0", config=config) as r:
            choose("option_a")

        events = r.event_log.read_all()
        # Filter to just op/decision events (skip run_started/run_completed)
        relevant = [
            e["event_type"]
            for e in events
            if e["event_type"] in ("op_started", "op_completed", "decision_recorded")
        ]
        assert relevant == ["op_started", "decision_recorded", "op_completed"]


class TestNodeIdMatch:
    """Decision's node_id matches enclosing op's node_id."""

    def test_decision_node_id_matches_op(self, config: LiminaraConfig):
        """The decision record's node_id matches the op's node_id."""

        @op(name="choose", version="1.0", determinism="recordable")
        @decision(decision_type="llm_response")
        def choose(x):
            return x

        with run("mypack", "1.0.0", config=config) as r:
            choose("test")

        events = r.event_log.read_all()
        op_started = next(e for e in events if e["event_type"] == "op_started")
        decision_recorded = next(e for e in events if e["event_type"] == "decision_recorded")
        assert op_started["payload"]["node_id"] == decision_recorded["payload"]["node_id"]


class TestArtifactsAndDecision:
    """Both artifacts and decision record exist on disk."""

    def test_all_on_disk(self, config: LiminaraConfig):
        """Input artifact, output artifact, and decision record all exist."""

        @op(name="choose", version="1.0", determinism="recordable")
        @decision(decision_type="stochastic")
        def choose(x):
            return x * 2

        with run("mypack", "1.0.0", config=config) as r:
            choose(5)

        events = r.event_log.read_all()
        op_started = next(e for e in events if e["event_type"] == "op_started")
        op_completed = next(e for e in events if e["event_type"] == "op_completed")

        # Input artifact exists
        input_hash = op_started["payload"]["input_hashes"][0]
        assert r.artifact_store.read(input_hash) is not None

        # Output artifact exists
        output_hash = op_completed["payload"]["output_hashes"][0]
        assert r.artifact_store.read(output_hash) is not None

        # Decision record exists
        decision_path = config.runs_root / r.run_id / "decisions" / "choose-001.json"
        assert decision_path.exists()


class TestReturnValueFlowsThrough:
    """Return value flows through both decorators."""

    def test_return_value(self, config: LiminaraConfig):
        """Return value flows through both @op and @decision unchanged."""

        @op(name="choose", version="1.0", determinism="recordable")
        @decision(decision_type="stochastic")
        def choose(x):
            return {"selected": x, "confidence": 0.95}

        with run("mypack", "1.0.0", config=config):
            result = choose("option_b")

        assert result == {"selected": "option_b", "confidence": 0.95}
