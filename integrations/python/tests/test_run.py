"""Tests for run.py — Run context manager.

Spec reference: M-CS-03-decorators.md § run.py — Run context manager

Run lifecycle:
  with run(pack_id, pack_version, config=None) as r:
      ...
  Emits run_started on enter, run_completed or run_failed on exit.
  Writes seal.json on normal exit. Re-raises exceptions.
"""

import json
import re
from pathlib import Path

import pytest

from liminara.config import LiminaraConfig
from liminara.hash import canonical_json
from liminara.run import run


@pytest.fixture
def config(tmp_path: Path) -> LiminaraConfig:
    """Config pointing at temp directories."""
    return LiminaraConfig(
        store_root=tmp_path / "store" / "artifacts",
        runs_root=tmp_path / "runs",
    )


class TestRunId:
    """run_id format: {pack_id}-{YYYYMMDDTHHMMSS}-{8 hex random}."""

    def test_run_id_format(self, config: LiminaraConfig):
        """run_id matches the expected pattern."""
        with run("mypack", "1.0.0", config=config) as r:
            pattern = r"^mypack-\d{8}T\d{6}-[0-9a-f]{8}$"
            assert re.match(pattern, r.run_id), f"run_id {r.run_id!r} doesn't match pattern"


class TestRunStarted:
    """run_started event on context entry."""

    def test_run_started_is_first_event(self, config: LiminaraConfig):
        """run_started is the first event in the log."""
        with run("mypack", "1.0.0", config=config) as r:
            events = r.event_log.read_all()
            assert len(events) >= 1
            assert events[0]["event_type"] == "run_started"

    def test_run_started_payload(self, config: LiminaraConfig):
        """run_started payload contains run_id, pack_id, pack_version, plan_hash."""
        with run("mypack", "1.0.0", config=config) as r:
            events = r.event_log.read_all()
            payload = events[0]["payload"]
            assert payload["run_id"] == r.run_id
            assert payload["pack_id"] == "mypack"
            assert payload["pack_version"] == "1.0.0"
            assert payload["plan_hash"] is None


class TestRunCompleted:
    """run_completed event on normal exit."""

    def test_run_completed_is_last_event(self, config: LiminaraConfig):
        """run_completed is the last event on normal exit."""
        with run("mypack", "1.0.0", config=config) as r:
            pass
        events = r.event_log.read_all()
        assert events[-1]["event_type"] == "run_completed"

    def test_run_completed_payload(self, config: LiminaraConfig):
        """run_completed payload contains outcome and artifact_hashes."""
        with run("mypack", "1.0.0", config=config) as r:
            pass
        events = r.event_log.read_all()
        payload = events[-1]["payload"]
        assert payload["run_id"] == r.run_id
        assert payload["outcome"] == "success"
        assert "artifact_hashes" in payload
        assert isinstance(payload["artifact_hashes"], list)


class TestRunFailed:
    """run_failed event on exception."""

    def test_run_failed_is_last_event(self, config: LiminaraConfig):
        """run_failed is the last event when an exception occurs."""
        with (
            pytest.raises(ValueError, match="test error"),
            run("mypack", "1.0.0", config=config) as r,
        ):
            raise ValueError("test error")
        events = r.event_log.read_all()
        assert events[-1]["event_type"] == "run_failed"

    def test_run_failed_payload(self, config: LiminaraConfig):
        """run_failed payload contains error_type and error_message."""
        with (
            pytest.raises(ValueError, match="test error"),
            run("mypack", "1.0.0", config=config) as r,
        ):
            raise ValueError("test error")
        events = r.event_log.read_all()
        payload = events[-1]["payload"]
        assert payload["run_id"] == r.run_id
        assert payload["error_type"] == "ValueError"
        assert payload["error_message"] == "test error"

    def test_no_run_completed_on_exception(self, config: LiminaraConfig):
        """run_completed is NOT emitted when an exception occurs."""
        with pytest.raises(ValueError, match="boom"), run("mypack", "1.0.0", config=config) as r:
            raise ValueError("boom")
        events = r.event_log.read_all()
        event_types = [e["event_type"] for e in events]
        assert "run_completed" not in event_types

    def test_exception_is_reraised(self, config: LiminaraConfig):
        """Exceptions are re-raised, not swallowed."""
        with pytest.raises(RuntimeError, match="original"), run("mypack", "1.0.0", config=config):
            raise RuntimeError("original")


class TestSeal:
    """seal.json on normal exit."""

    def test_seal_exists_after_normal_exit(self, config: LiminaraConfig):
        """seal.json exists after normal run completion."""
        with run("mypack", "1.0.0", config=config) as r:
            pass
        seal_path = config.runs_root / r.run_id / "seal.json"
        assert seal_path.exists()

    def test_seal_contains_correct_fields(self, config: LiminaraConfig):
        """seal.json contains run_id, run_seal, completed_at, event_count."""
        with run("mypack", "1.0.0", config=config) as r:
            pass
        seal_path = config.runs_root / r.run_id / "seal.json"
        seal = json.loads(seal_path.read_bytes())
        assert seal["run_id"] == r.run_id
        assert seal["run_seal"].startswith("sha256:")
        assert "completed_at" in seal
        assert isinstance(seal["event_count"], int)

    def test_seal_matches_run_completed_hash(self, config: LiminaraConfig):
        """run_seal equals event_hash of the run_completed event."""
        with run("mypack", "1.0.0", config=config) as r:
            pass
        events = r.event_log.read_all()
        run_completed = events[-1]
        assert run_completed["event_type"] == "run_completed"

        seal_path = config.runs_root / r.run_id / "seal.json"
        seal = json.loads(seal_path.read_bytes())
        assert seal["run_seal"] == run_completed["event_hash"]

    def test_seal_event_count(self, config: LiminaraConfig):
        """event_count in seal.json matches actual number of events."""
        with run("mypack", "1.0.0", config=config) as r:
            pass
        events = r.event_log.read_all()
        seal_path = config.runs_root / r.run_id / "seal.json"
        seal = json.loads(seal_path.read_bytes())
        assert seal["event_count"] == len(events)

    def test_seal_is_canonical_json(self, config: LiminaraConfig):
        """seal.json is canonical JSON (sorted keys, no whitespace)."""
        with run("mypack", "1.0.0", config=config) as r:
            pass
        seal_path = config.runs_root / r.run_id / "seal.json"
        raw = seal_path.read_bytes()
        parsed = json.loads(raw)

        # Re-encode as canonical JSON and compare
        expected = canonical_json(parsed)
        assert raw == expected

    def test_no_seal_on_failure(self, config: LiminaraConfig):
        """seal.json is NOT written when the run fails."""
        with pytest.raises(ValueError, match="fail"), run("mypack", "1.0.0", config=config) as r:
            raise ValueError("fail")
        seal_path = config.runs_root / r.run_id / "seal.json"
        assert not seal_path.exists()


class TestRunContext:
    """Accessible attributes inside the run context."""

    def test_run_id_accessible(self, config: LiminaraConfig):
        """r.run_id is accessible inside the context block."""
        with run("mypack", "1.0.0", config=config) as r:
            assert r.run_id is not None
            assert isinstance(r.run_id, str)

    def test_event_log_accessible(self, config: LiminaraConfig):
        """r.event_log is accessible inside the context block."""
        from liminara.event_log import EventLog

        with run("mypack", "1.0.0", config=config) as r:
            assert isinstance(r.event_log, EventLog)

    def test_artifact_store_accessible(self, config: LiminaraConfig):
        """r.artifact_store is accessible inside the context block."""
        from liminara.artifact_store import ArtifactStore

        with run("mypack", "1.0.0", config=config) as r:
            assert isinstance(r.artifact_store, ArtifactStore)

    def test_decision_store_accessible(self, config: LiminaraConfig):
        """r.decision_store is accessible inside the context block."""
        from liminara.decision_store import DecisionStore

        with run("mypack", "1.0.0", config=config) as r:
            assert isinstance(r.decision_store, DecisionStore)


class TestHashChainIntegrity:
    """Hash chain is valid after run completes."""

    def test_hash_chain_valid(self, config: LiminaraConfig):
        """Hash chain verifies after a normal run."""
        with run("mypack", "1.0.0", config=config) as r:
            pass
        valid, error = r.event_log.verify()
        assert valid is True
        assert error is None


class TestMultipleRuns:
    """Multiple sequential runs produce separate directories."""

    def test_separate_run_directories(self, config: LiminaraConfig):
        """Two runs create two separate run directories."""
        with run("mypack", "1.0.0", config=config) as r1:
            pass
        with run("mypack", "1.0.0", config=config) as r2:
            pass
        assert r1.run_id != r2.run_id
        assert (config.runs_root / r1.run_id / "events.jsonl").exists()
        assert (config.runs_root / r2.run_id / "events.jsonl").exists()
