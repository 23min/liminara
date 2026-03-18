"""Golden fixture tests — verify test_fixtures/golden_run/ from Python.

These tests validate that the Python SDK produces identical hashes to the
golden fixtures, ensuring cross-language compatibility with the Elixir runtime.
"""

import hashlib
import json
from pathlib import Path

from liminara.hash import canonical_json, hash_bytes, hash_event

FIXTURES_DIR = Path(__file__).parent.parent.parent.parent / "test_fixtures" / "golden_run"


def read_events(filename: str) -> list[dict]:
    path = FIXTURES_DIR / filename
    return [json.loads(line) for line in path.read_text().strip().splitlines()]


def read_json(filename: str) -> dict:
    return json.loads((FIXTURES_DIR / filename).read_bytes())


class TestEventHashChain:
    def test_events_jsonl_has_valid_hash_chain(self) -> None:
        events = read_events("events.jsonl")
        assert len(events) == 7

        prev_hash = None
        for i, event in enumerate(events):
            assert event["prev_hash"] == prev_hash, f"Event {i}: prev_hash mismatch"

            expected = hash_event(
                event["event_type"],
                event["payload"],
                event["prev_hash"],
                event["timestamp"],
            )
            assert event["event_hash"] == expected, f"Event {i}: event_hash mismatch"
            prev_hash = event["event_hash"]

    def test_tampered_events_fail_verification(self) -> None:
        events = read_events("events_tampered.jsonl")

        prev_hash = None
        tamper_detected = False
        for _i, event in enumerate(events):
            expected = hash_event(
                event["event_type"],
                event["payload"],
                event["prev_hash"],
                event["timestamp"],
            )
            if event["prev_hash"] != prev_hash or event["event_hash"] != expected:
                tamper_detected = True
                break
            prev_hash = event["event_hash"]

        assert tamper_detected, "Tampered log should fail verification"


class TestRunSeal:
    def test_seal_matches_final_event_hash(self) -> None:
        events = read_events("events.jsonl")
        final_event = events[-1]
        seal = read_json("seal.json")

        assert seal["run_seal"] == final_event["event_hash"]
        assert seal["event_count"] == len(events)
        assert seal["run_id"] == "test_pack-20260315T120000-aabbccdd"
        assert seal["completed_at"] == final_event["timestamp"]


class TestDecisionRecord:
    def test_decision_hash_is_valid(self) -> None:
        decision = read_json("decisions/summarize.json")

        hashable = {k: v for k, v in decision.items() if k != "decision_hash"}
        expected = "sha256:" + hashlib.sha256(canonical_json(hashable)).hexdigest()
        assert decision["decision_hash"] == expected

    def test_decision_hash_matches_event_reference(self) -> None:
        decision = read_json("decisions/summarize.json")
        events = read_events("events.jsonl")

        decision_event = next(e for e in events if e["event_type"] == "decision_recorded")
        assert decision_event["payload"]["decision_hash"] == decision["decision_hash"]


class TestArtifactBlobs:
    def test_artifact_content_hashes_match_paths(self) -> None:
        events = read_events("events.jsonl")
        artifact_hashes = [
            h
            for e in events
            if e["event_type"] == "op_completed"
            for h in e["payload"]["output_hashes"]
        ]
        assert len(artifact_hashes) == 2

        for content_hash in artifact_hashes:
            hex_str = content_hash.removeprefix("sha256:")
            path = FIXTURES_DIR / "artifacts" / hex_str[:2] / hex_str[2:4] / hex_str
            assert path.exists(), f"Artifact file missing: {path}"

            content = path.read_bytes()
            assert hash_bytes(content) == content_hash


class TestCanary:
    def test_canonical_json_and_hash_match_expected(self) -> None:
        canary = {"z": 1, "a": [True, None, "hello"], "m": {"nested": 42}}

        canonical = canonical_json(canary)
        assert canonical == b'{"a":[true,null,"hello"],"m":{"nested":42},"z":1}'

        h = hash_bytes(canonical)
        assert h == "sha256:0fa7f2a293c29e7a21ddaa8cf24c99d6740a85353793a6bc92abdc9ab538637e"
