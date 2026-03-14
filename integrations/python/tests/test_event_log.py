"""Tests for event_log.py — append-only JSONL event log with hash chain.

Spec reference: docs/analysis/11_Data_Model_Spec.md

Event log: {runs_root}/{run_id}/events.jsonl
Each line is canonical JSON with fields:
  event_hash, event_type, payload, prev_hash, timestamp
"""

import json
from pathlib import Path

import pytest

from liminara.event_log import EventLog


@pytest.fixture
def event_log(tmp_path: Path) -> EventLog:
    """Create an EventLog rooted in a temp directory."""
    return EventLog(runs_root=tmp_path / "runs", run_id="test-run-001")


class TestAppendAndRead:
    """Append event → read back."""

    def test_append_single_event(self, event_log: EventLog):
        """Appending one event and reading it back succeeds."""
        event_log.append(
            event_type="run_started",
            payload={"run_id": "test-run-001", "pack_id": "test", "pack_version": "0.1.0",
                      "plan_hash": "sha256:" + "00" * 32},
        )
        events = event_log.read_all()
        assert len(events) == 1

    def test_event_has_required_fields(self, event_log: EventLog):
        """Each event contains event_hash, event_type, payload, prev_hash, timestamp."""
        event_log.append(event_type="run_started", payload={"run_id": "test-run-001"})
        events = event_log.read_all()
        event = events[0]
        assert "event_hash" in event
        assert "event_type" in event
        assert "payload" in event
        assert "prev_hash" in event
        assert "timestamp" in event

    def test_event_type_preserved(self, event_log: EventLog):
        """Event type is preserved exactly."""
        event_log.append(event_type="op_started", payload={"node_id": "n1"})
        events = event_log.read_all()
        assert events[0]["event_type"] == "op_started"

    def test_payload_preserved(self, event_log: EventLog):
        """Payload is preserved exactly."""
        payload = {"node_id": "n1", "op_id": "summarize", "op_version": "1.0",
                   "input_hashes": ["sha256:" + "aa" * 32]}
        event_log.append(event_type="op_started", payload=payload)
        events = event_log.read_all()
        assert events[0]["payload"] == payload

    def test_read_multiple_events(self, event_log: EventLog):
        """Multiple appended events are all returned in order."""
        event_log.append(event_type="run_started", payload={"run_id": "r1"})
        event_log.append(event_type="op_started", payload={"node_id": "n1"})
        event_log.append(event_type="op_completed", payload={"node_id": "n1"})
        events = event_log.read_all()
        assert len(events) == 3
        assert events[0]["event_type"] == "run_started"
        assert events[1]["event_type"] == "op_started"
        assert events[2]["event_type"] == "op_completed"


class TestHashChain:
    """Hash chain: prev_hash links events cryptographically."""

    def test_first_event_prev_hash_null(self, event_log: EventLog):
        """First event has prev_hash: null."""
        event_log.append(event_type="run_started", payload={"run_id": "r1"})
        events = event_log.read_all()
        assert events[0]["prev_hash"] is None

    def test_second_event_prev_hash_links(self, event_log: EventLog):
        """Second event's prev_hash equals first event's event_hash."""
        event_log.append(event_type="run_started", payload={"run_id": "r1"})
        event_log.append(event_type="op_started", payload={"node_id": "n1"})
        events = event_log.read_all()
        assert events[1]["prev_hash"] == events[0]["event_hash"]

    def test_chain_of_three(self, event_log: EventLog):
        """Three events form a correct chain."""
        event_log.append(event_type="run_started", payload={"run_id": "r1"})
        event_log.append(event_type="op_started", payload={"node_id": "n1"})
        event_log.append(event_type="op_completed", payload={"node_id": "n1"})
        events = event_log.read_all()
        assert events[0]["prev_hash"] is None
        assert events[1]["prev_hash"] == events[0]["event_hash"]
        assert events[2]["prev_hash"] == events[1]["event_hash"]

    def test_event_hash_format(self, event_log: EventLog):
        """Event hashes use sha256:{64 hex} format."""
        event_log.append(event_type="run_started", payload={"run_id": "r1"})
        events = event_log.read_all()
        h = events[0]["event_hash"]
        assert h.startswith("sha256:")
        assert len(h) == 7 + 64


class TestVerifyChain:
    """verify() checks hash chain integrity."""

    def test_valid_chain(self, event_log: EventLog):
        """A properly formed chain verifies successfully."""
        event_log.append(event_type="run_started", payload={"run_id": "r1"})
        event_log.append(event_type="op_started", payload={"node_id": "n1"})
        event_log.append(event_type="op_completed", payload={"node_id": "n1"})
        valid, error = event_log.verify()
        assert valid is True
        assert error is None

    def test_tamper_middle_event(self, event_log: EventLog):
        """Modifying a middle event's payload is detected."""
        event_log.append(event_type="run_started", payload={"run_id": "r1"})
        event_log.append(event_type="op_started", payload={"node_id": "n1"})
        event_log.append(event_type="op_completed", payload={"node_id": "n1"})

        # Tamper with the second event's payload on disk
        events_file = event_log.events_path
        lines = events_file.read_text().splitlines()
        event = json.loads(lines[1])
        event["payload"]["node_id"] = "TAMPERED"
        lines[1] = json.dumps(event, separators=(",", ":"), sort_keys=True)
        events_file.write_text("\n".join(lines) + "\n")

        valid, error = event_log.verify()
        assert valid is False
        assert error is not None

    def test_tamper_first_event(self, event_log: EventLog):
        """Modifying the first event invalidates all subsequent hashes."""
        event_log.append(event_type="run_started", payload={"run_id": "r1"})
        event_log.append(event_type="op_started", payload={"node_id": "n1"})
        event_log.append(event_type="op_completed", payload={"node_id": "n1"})

        # Tamper with the first event
        events_file = event_log.events_path
        lines = events_file.read_text().splitlines()
        event = json.loads(lines[0])
        event["payload"]["run_id"] = "TAMPERED"
        lines[0] = json.dumps(event, separators=(",", ":"), sort_keys=True)
        events_file.write_text("\n".join(lines) + "\n")

        valid, error = event_log.verify()
        assert valid is False

    def test_empty_log_is_valid(self, event_log: EventLog):
        """An empty event log verifies successfully."""
        valid, error = event_log.verify()
        assert valid is True
        assert error is None


class TestFileFormat:
    """On-disk format: JSONL in {runs_root}/{run_id}/events.jsonl."""

    def test_file_location(self, event_log: EventLog):
        """Events file is at {runs_root}/{run_id}/events.jsonl."""
        event_log.append(event_type="run_started", payload={"run_id": "r1"})
        expected_path = event_log.runs_root / "test-run-001" / "events.jsonl"
        assert expected_path.exists()

    def test_each_line_is_valid_json(self, event_log: EventLog):
        """Each line in the JSONL file is independently parseable JSON."""
        event_log.append(event_type="run_started", payload={"run_id": "r1"})
        event_log.append(event_type="op_started", payload={"node_id": "n1"})
        lines = event_log.events_path.read_text().strip().splitlines()
        assert len(lines) == 2
        for line in lines:
            parsed = json.loads(line)
            assert isinstance(parsed, dict)

    def test_newline_terminated(self, event_log: EventLog):
        """File ends with a newline character."""
        event_log.append(event_type="run_started", payload={"run_id": "r1"})
        content = event_log.events_path.read_text()
        assert content.endswith("\n")

    def test_timestamp_is_iso8601_utc(self, event_log: EventLog):
        """Timestamps are ISO 8601, UTC, with millisecond precision."""
        event_log.append(event_type="run_started", payload={"run_id": "r1"})
        events = event_log.read_all()
        ts = events[0]["timestamp"]
        # Should end with Z (UTC) and have milliseconds
        assert ts.endswith("Z")
        assert "." in ts
