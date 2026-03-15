"""Tests for decorators.py — @op decorator.

Spec reference: M-CS-03-decorators.md § decorators.py — @op

@op(name, version, determinism) emits op_started/op_completed/op_failed,
stores input/output as artifacts, measures duration, assigns node_id.
"""

import json
from pathlib import Path

import pytest

from liminara.config import LiminaraConfig
from liminara.decorators import op
from liminara.run import run


@pytest.fixture
def config(tmp_path: Path) -> LiminaraConfig:
    return LiminaraConfig(
        store_root=tmp_path / "store" / "artifacts",
        runs_root=tmp_path / "runs",
    )


class TestDecorationTime:
    """Validation at decoration time."""

    def test_valid_determinism_values(self):
        """@op with valid determinism values does not raise."""
        for det in ("pure", "pinned_env", "recordable", "side_effecting"):

            @op(name="test_op", version="1.0", determinism=det)
            def fn():
                pass

    def test_invalid_determinism_raises(self):
        """@op with invalid determinism raises ValueError at decoration time."""
        with pytest.raises(ValueError):

            @op(name="test_op", version="1.0", determinism="invalid")
            def fn():
                pass


class TestNodeId:
    """node_id = {name}-{zero_padded_counter}."""

    def test_node_id_format(self, config: LiminaraConfig):
        """node_id is {name}-{3-digit zero-padded counter}."""

        @op(name="summarize", version="1.0", determinism="pure")
        def summarize(x):
            return x

        with run("mypack", "1.0.0", config=config) as r:
            summarize("hello")

        events = r.event_log.read_all()
        op_started = [e for e in events if e["event_type"] == "op_started"][0]
        assert op_started["payload"]["node_id"] == "summarize-001"

    def test_sequential_node_ids(self, config: LiminaraConfig):
        """Multiple ops in one run get sequential node_ids."""

        @op(name="step", version="1.0", determinism="pure")
        def step(x):
            return x

        with run("mypack", "1.0.0", config=config) as r:
            step("a")
            step("b")
            step("c")

        events = r.event_log.read_all()
        op_started_events = [e for e in events if e["event_type"] == "op_started"]
        node_ids = [e["payload"]["node_id"] for e in op_started_events]
        assert node_ids == ["step-001", "step-002", "step-003"]


class TestOpStarted:
    """op_started event."""

    def test_op_started_emitted(self, config: LiminaraConfig):
        """op_started event is emitted when @op function is called."""

        @op(name="my_op", version="2.0", determinism="pure")
        def my_op(x):
            return x

        with run("mypack", "1.0.0", config=config) as r:
            my_op("input")

        events = r.event_log.read_all()
        op_started = [e for e in events if e["event_type"] == "op_started"]
        assert len(op_started) == 1

    def test_op_started_payload(self, config: LiminaraConfig):
        """op_started payload has node_id, op_id, op_version, input_hashes."""

        @op(name="my_op", version="2.0", determinism="recordable")
        def my_op(x):
            return x

        with run("mypack", "1.0.0", config=config) as r:
            my_op("input")

        events = r.event_log.read_all()
        payload = [e for e in events if e["event_type"] == "op_started"][0]["payload"]
        assert payload["node_id"] == "my_op-001"
        assert payload["op_id"] == "my_op"
        assert payload["op_version"] == "2.0"
        assert isinstance(payload["input_hashes"], list)
        assert len(payload["input_hashes"]) == 1
        assert payload["input_hashes"][0].startswith("sha256:")

    def test_input_artifact_exists(self, config: LiminaraConfig):
        """Input artifact is stored and deserializes to {"args": [...], "kwargs": {...}}."""

        @op(name="my_op", version="1.0", determinism="pure")
        def my_op(x, y=10):
            return x * y

        with run("mypack", "1.0.0", config=config) as r:
            my_op("hello", y=3)

        events = r.event_log.read_all()
        payload = [e for e in events if e["event_type"] == "op_started"][0]["payload"]
        input_hash = payload["input_hashes"][0]

        # Read the artifact back
        raw = r.artifact_store.read(input_hash)
        deserialized = json.loads(raw)
        assert "args" in deserialized
        assert "kwargs" in deserialized
        assert deserialized["args"] == ["hello"]
        assert deserialized["kwargs"] == {"y": 3}


class TestOpCompleted:
    """op_completed event on success."""

    def test_op_completed_emitted(self, config: LiminaraConfig):
        """op_completed event is emitted on success."""

        @op(name="my_op", version="1.0", determinism="pure")
        def my_op(x):
            return x.upper()

        with run("mypack", "1.0.0", config=config) as r:
            my_op("hello")

        events = r.event_log.read_all()
        op_completed = [e for e in events if e["event_type"] == "op_completed"]
        assert len(op_completed) == 1

    def test_op_completed_payload(self, config: LiminaraConfig):
        """op_completed payload has node_id, output_hashes, cache_hit, duration_ms."""

        @op(name="my_op", version="1.0", determinism="pure")
        def my_op(x):
            return x.upper()

        with run("mypack", "1.0.0", config=config) as r:
            my_op("hello")

        events = r.event_log.read_all()
        payload = [e for e in events if e["event_type"] == "op_completed"][0]["payload"]
        assert payload["node_id"] == "my_op-001"
        assert isinstance(payload["output_hashes"], list)
        assert len(payload["output_hashes"]) == 1
        assert payload["output_hashes"][0].startswith("sha256:")
        assert payload["cache_hit"] is False
        assert isinstance(payload["duration_ms"], float)

    def test_output_artifact_exists(self, config: LiminaraConfig):
        """Output artifact is stored and matches return value."""

        @op(name="my_op", version="1.0", determinism="pure")
        def my_op(x):
            return x.upper()

        with run("mypack", "1.0.0", config=config) as r:
            my_op("hello")

        events = r.event_log.read_all()
        payload = [e for e in events if e["event_type"] == "op_completed"][0]["payload"]
        output_hash = payload["output_hashes"][0]

        raw = r.artifact_store.read(output_hash)
        deserialized = json.loads(raw)
        assert deserialized == "HELLO"

    def test_cache_hit_always_false(self, config: LiminaraConfig):
        """cache_hit is always false (caching deferred)."""

        @op(name="my_op", version="1.0", determinism="pure")
        def my_op(x):
            return x

        with run("mypack", "1.0.0", config=config) as r:
            my_op("a")
            my_op("a")

        events = r.event_log.read_all()
        for e in events:
            if e["event_type"] == "op_completed":
                assert e["payload"]["cache_hit"] is False

    def test_duration_ms_is_positive(self, config: LiminaraConfig):
        """duration_ms is a positive float."""

        @op(name="my_op", version="1.0", determinism="pure")
        def my_op(x):
            return x

        with run("mypack", "1.0.0", config=config) as r:
            my_op("hello")

        events = r.event_log.read_all()
        payload = [e for e in events if e["event_type"] == "op_completed"][0]["payload"]
        assert payload["duration_ms"] > 0


class TestOpFailed:
    """op_failed event on exception."""

    def test_op_failed_emitted(self, config: LiminaraConfig):
        """op_failed event is emitted when the function raises."""

        @op(name="failing_op", version="1.0", determinism="pure")
        def failing_op():
            raise RuntimeError("boom")

        with pytest.raises(RuntimeError):
            with run("mypack", "1.0.0", config=config) as r:
                failing_op()

        events = r.event_log.read_all()
        op_failed = [e for e in events if e["event_type"] == "op_failed"]
        assert len(op_failed) == 1
        payload = op_failed[0]["payload"]
        assert payload["node_id"] == "failing_op-001"
        assert payload["error_type"] == "RuntimeError"
        assert payload["error_message"] == "boom"

    def test_exception_reraised(self, config: LiminaraConfig):
        """Exception from the wrapped function is re-raised."""

        @op(name="failing_op", version="1.0", determinism="pure")
        def failing_op():
            raise ValueError("original error")

        with pytest.raises(ValueError, match="original error"):
            with run("mypack", "1.0.0", config=config):
                failing_op()
