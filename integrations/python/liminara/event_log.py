"""JSONL append-only event log with hash chain."""

import json
from datetime import UTC, datetime
from pathlib import Path

from liminara.hash import canonical_json, hash_event


class EventLog:
    """Append-only JSONL event log with hash-chained events.

    File layout: {runs_root}/{run_id}/events.jsonl
    Each line is canonical JSON with fields:
        event_hash, event_type, payload, prev_hash, timestamp
    """

    def __init__(self, runs_root: Path, run_id: str) -> None:
        self.runs_root = runs_root
        self.run_id = run_id
        self.events_path = runs_root / run_id / "events.jsonl"
        self._prev_hash: str | None = None

    def append(self, event_type: str, payload: dict) -> None:
        """Append an event with auto-computed hash and timestamp."""
        timestamp = (
            datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%S.")
            + f"{datetime.now(UTC).microsecond // 1000:03d}Z"
        )

        event_hash = hash_event(
            event_type=event_type,
            payload=payload,
            prev_hash=self._prev_hash,
            timestamp=timestamp,
        )

        event = {
            "event_hash": event_hash,
            "event_type": event_type,
            "payload": payload,
            "prev_hash": self._prev_hash,
            "timestamp": timestamp,
        }

        self.events_path.parent.mkdir(parents=True, exist_ok=True)

        line = canonical_json(event).decode("utf-8") + "\n"
        with open(self.events_path, "a") as f:
            f.write(line)

        self._prev_hash = event_hash

    def read_all(self) -> list[dict]:
        """Read all events from the log."""
        if not self.events_path.exists():
            return []
        lines = self.events_path.read_text().strip().splitlines()
        return [json.loads(line) for line in lines]

    def verify(self) -> tuple[bool, str | None]:
        """Verify hash chain integrity.

        Returns (True, None) if valid, (False, error_message) if tampered.
        """
        events = self.read_all()
        if not events:
            return True, None

        prev_hash = None
        for i, event in enumerate(events):
            # Check prev_hash linkage
            if event["prev_hash"] != prev_hash:
                return False, f"Event {i}: prev_hash mismatch"

            # Recompute event_hash and compare
            expected_hash = hash_event(
                event_type=event["event_type"],
                payload=event["payload"],
                prev_hash=event["prev_hash"],
                timestamp=event["timestamp"],
            )
            if event["event_hash"] != expected_hash:
                return False, f"Event {i}: event_hash mismatch"

            prev_hash = event["event_hash"]

        return True, None
