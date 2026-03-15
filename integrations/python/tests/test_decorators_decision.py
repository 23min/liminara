"""Tests for decorators.py — @decision decorator.

Spec reference: M-CS-03-decorators.md § decorators.py — @decision

@decision(decision_type) records the function's result as a decision via DecisionStore,
emits decision_recorded event. Reads node_id/op_id/op_version from enclosing @op context.
"""

import hashlib
from pathlib import Path

import pytest

from liminara.config import LiminaraConfig
from liminara.decorators import decision, op
from liminara.hash import canonical_json
from liminara.run import run


@pytest.fixture
def config(tmp_path: Path) -> LiminaraConfig:
    return LiminaraConfig(
        store_root=tmp_path / "store" / "artifacts",
        runs_root=tmp_path / "runs",
    )


class TestDecorationTime:
    """Validation at decoration time."""

    def test_valid_decision_types(self):
        """@decision with valid types does not raise."""
        for dt in ("llm_response", "human_gate", "stochastic", "model_selection"):

            @decision(decision_type=dt)
            def fn():
                pass

    def test_invalid_decision_type_raises(self):
        """@decision with invalid type raises ValueError at decoration time."""
        with pytest.raises(ValueError):

            @decision(decision_type="invalid")
            def fn():
                pass


class TestDecisionRecord:
    """Decision record written to disk."""

    def test_decision_record_written(self, config: LiminaraConfig):
        """Decision record is written to decisions/{node_id}.json."""

        @op(name="choose", version="1.0", determinism="recordable")
        @decision(decision_type="llm_response")
        def choose(x):
            return f"chose {x}"

        with run("mypack", "1.0.0", config=config) as r:
            choose("option_a")

        decision_path = config.runs_root / r.run_id / "decisions" / "choose-001.json"
        assert decision_path.exists()

    def test_decision_record_fields(self, config: LiminaraConfig):
        """Decision record contains all required fields."""

        @op(name="choose", version="2.0", determinism="recordable")
        @decision(decision_type="stochastic")
        def choose(x):
            return x * 2

        with run("mypack", "1.0.0", config=config) as r:
            choose(5)

        record = r.decision_store.read("choose-001")
        assert record["node_id"] == "choose-001"
        assert record["op_id"] == "choose"
        assert record["op_version"] == "2.0"
        assert record["decision_type"] == "stochastic"
        assert "inputs" in record
        assert "args_hash" in record["inputs"]
        assert "output" in record
        assert "result_hash" in record["output"]
        assert "recorded_at" in record
        assert "decision_hash" in record

    def test_decision_hash_is_correct(self, config: LiminaraConfig):
        """decision_hash is correctly computed (verified by recomputing)."""

        @op(name="choose", version="1.0", determinism="recordable")
        @decision(decision_type="llm_response")
        def choose(x):
            return x

        with run("mypack", "1.0.0", config=config) as r:
            choose("test")

        record = r.decision_store.read("choose-001")
        without_hash = {k: v for k, v in record.items() if k != "decision_hash"}
        expected = "sha256:" + hashlib.sha256(canonical_json(without_hash)).hexdigest()
        assert record["decision_hash"] == expected


class TestDecisionEvent:
    """decision_recorded event emitted."""

    def test_decision_recorded_event(self, config: LiminaraConfig):
        """decision_recorded event is emitted with correct payload."""

        @op(name="choose", version="1.0", determinism="recordable")
        @decision(decision_type="model_selection")
        def choose(x):
            return x

        with run("mypack", "1.0.0", config=config) as r:
            choose("test")

        events = r.event_log.read_all()
        decision_events = [e for e in events if e["event_type"] == "decision_recorded"]
        assert len(decision_events) == 1

        payload = decision_events[0]["payload"]
        assert payload["node_id"] == "choose-001"
        assert payload["decision_hash"].startswith("sha256:")
        assert payload["decision_type"] == "model_selection"


class TestReturnValue:
    """Return value passes through unchanged."""

    def test_return_value_passthrough(self, config: LiminaraConfig):
        """Return value of decorated function is passed through unchanged."""

        @op(name="choose", version="1.0", determinism="recordable")
        @decision(decision_type="stochastic")
        def choose(x):
            return {"result": x, "score": 42}

        with run("mypack", "1.0.0", config=config):
            result = choose("test")

        assert result == {"result": "test", "score": 42}
