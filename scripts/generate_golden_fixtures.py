#!/usr/bin/env python3
"""Generate golden test fixtures for cross-language verification.

Uses the Python SDK's hash functions to produce a valid Liminara run
with correct hashes. The generated fixtures are the contract test
between the Python SDK and the Elixir runtime.

Run from repo root:
    uv run --project integrations/python scripts/generate_golden_fixtures.py
"""

import hashlib
import json
import sys
from pathlib import Path

# Add the Python SDK to the path
sys.path.insert(0, str(Path(__file__).parent.parent / "integrations" / "python"))

from liminara.hash import canonical_json, hash_bytes, hash_event

# ── Constants ────────────────────────────────────────────────────────

FIXTURES_DIR = Path(__file__).parent.parent / "test_fixtures" / "golden_run"
RUN_ID = "test_pack-20260315T120000-aabbccdd"
PACK_ID = "test_pack"
PACK_VERSION = "0.1.0"

# Cross-language canary: a known JSON object with expected canonical form and hash.
# Both Elixir and Python tests assert the same hash for this object.
CANARY_OBJECT = {"z": 1, "a": [True, None, "hello"], "m": {"nested": 42}}
CANARY_CANONICAL = canonical_json(CANARY_OBJECT)
CANARY_HASH = hash_bytes(CANARY_CANONICAL)


def make_artifact(content: bytes) -> tuple[str, bytes]:
    """Return (content_hash, content_bytes) for an artifact."""
    content_hash = hash_bytes(content)
    return content_hash, content


def artifact_path(content_hash: str) -> Path:
    """Git-style sharded path for an artifact blob."""
    hex_str = content_hash.removeprefix("sha256:")
    return FIXTURES_DIR / "artifacts" / hex_str[:2] / hex_str[2:4] / hex_str


def build_events(
    artifact1_hash: str,
    artifact2_hash: str,
    decision_hash: str,
) -> list[dict]:
    """Build the 7-event sequence with valid hash chain."""
    events = []
    prev_hash = None

    def append_event(event_type: str, payload: dict) -> None:
        nonlocal prev_hash
        # Fixed timestamps for reproducibility
        ts = f"2026-03-15T12:00:0{len(events)}.000Z"
        event_hash = hash_event(event_type, payload, prev_hash, ts)
        events.append(
            {
                "event_hash": event_hash,
                "event_type": event_type,
                "payload": payload,
                "prev_hash": prev_hash,
                "timestamp": ts,
            }
        )
        prev_hash = event_hash

    # 1. run_started
    plan_hash = hash_bytes(canonical_json({"nodes": ["fetch", "summarize"]}))
    append_event(
        "run_started",
        {
            "pack_id": PACK_ID,
            "pack_version": PACK_VERSION,
            "plan_hash": plan_hash,
            "run_id": RUN_ID,
        },
    )

    # 2. op_started — fetch
    append_event(
        "op_started",
        {
            "determinism": "pinned_env",
            "input_hashes": [],
            "node_id": "fetch",
            "op_id": "fetch_documents",
            "op_version": "1.0",
        },
    )

    # 3. op_completed — fetch
    append_event(
        "op_completed",
        {
            "cache_hit": False,
            "duration_ms": 1500,
            "node_id": "fetch",
            "output_hashes": [artifact1_hash],
        },
    )

    # 4. op_started — summarize
    append_event(
        "op_started",
        {
            "determinism": "recordable",
            "input_hashes": [artifact1_hash],
            "node_id": "summarize",
            "op_id": "summarize_text",
            "op_version": "1.0",
        },
    )

    # 5. decision_recorded — summarize
    append_event(
        "decision_recorded",
        {
            "decision_hash": decision_hash,
            "decision_type": "llm_response",
            "node_id": "summarize",
        },
    )

    # 6. op_completed — summarize
    append_event(
        "op_completed",
        {
            "cache_hit": False,
            "duration_ms": 2300,
            "node_id": "summarize",
            "output_hashes": [artifact2_hash],
        },
    )

    # 7. run_completed
    append_event(
        "run_completed",
        {
            "artifact_hashes": [artifact1_hash, artifact2_hash],
            "outcome": "success",
            "run_id": RUN_ID,
        },
    )

    return events


def build_decision(artifact1_hash: str, artifact2_hash: str) -> tuple[dict, str]:
    """Build the decision record and compute its hash."""
    record = {
        "decision_type": "llm_response",
        "inputs": {
            "model_id": "claude-sonnet-4-6",
            "model_version": "20251001",
            "prompt_hash": artifact1_hash,
            "temperature": 0.7,
        },
        "node_id": "summarize",
        "op_id": "summarize_text",
        "op_version": "1.0",
        "output": {
            "response_hash": artifact2_hash,
            "token_usage": {"input": 1024, "output": 512},
        },
        "recorded_at": "2026-03-15T12:00:04.500Z",
    }
    # Hash over all fields except decision_hash
    decision_hash = "sha256:" + hashlib.sha256(canonical_json(record)).hexdigest()
    record["decision_hash"] = decision_hash
    return record, decision_hash


def build_seal(events: list[dict]) -> dict:
    """Build the run seal from the final event."""
    final_event = events[-1]
    return {
        "completed_at": final_event["timestamp"],
        "event_count": len(events),
        "run_id": RUN_ID,
        "run_seal": final_event["event_hash"],
    }


def build_tampered_events(events: list[dict]) -> list[dict]:
    """Copy events with one payload modified to break the hash chain."""
    tampered = json.loads(json.dumps(events))  # deep copy
    # Modify event 2 (op_completed for fetch): change duration_ms
    tampered[2]["payload"]["duration_ms"] = 9999
    return tampered


def write_fixtures() -> None:
    """Generate all golden fixture files."""
    # Clean and create directory
    if FIXTURES_DIR.exists():
        import shutil

        shutil.rmtree(FIXTURES_DIR)
    FIXTURES_DIR.mkdir(parents=True)

    # Artifacts
    artifact1_content = canonical_json(
        {
            "documents": [
                {"id": "doc-001", "source": "rss-feed-a", "title": "Sample Article"},
                {"id": "doc-002", "source": "rss-feed-b", "title": "Another Article"},
            ]
        }
    )
    artifact2_content = b"This is a summary of the fetched documents. The articles discuss various topics."

    artifact1_hash, artifact1_bytes = make_artifact(artifact1_content)
    artifact2_hash, artifact2_bytes = make_artifact(artifact2_content)

    # Write artifact blobs
    for h, content in [(artifact1_hash, artifact1_bytes), (artifact2_hash, artifact2_bytes)]:
        path = artifact_path(h)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        print(f"  artifact: {path.relative_to(FIXTURES_DIR)}")

    # Decision
    decision_record, decision_hash = build_decision(artifact1_hash, artifact2_hash)

    # Write decision file
    decision_path = FIXTURES_DIR / "decisions" / "summarize.json"
    decision_path.parent.mkdir(parents=True, exist_ok=True)
    decision_path.write_bytes(canonical_json(decision_record))
    print(f"  decision: decisions/summarize.json")

    # Events
    events = build_events(artifact1_hash, artifact2_hash, decision_hash)

    # Write events.jsonl
    events_path = FIXTURES_DIR / "events.jsonl"
    with open(events_path, "w") as f:
        for event in events:
            f.write(canonical_json(event).decode("utf-8") + "\n")
    print(f"  events:   events.jsonl ({len(events)} events)")

    # Seal
    seal = build_seal(events)
    seal_path = FIXTURES_DIR / "seal.json"
    seal_path.write_bytes(canonical_json(seal))
    print(f"  seal:     seal.json")

    # Tampered events
    tampered = build_tampered_events(events)
    tampered_path = FIXTURES_DIR / "events_tampered.jsonl"
    with open(tampered_path, "w") as f:
        for event in tampered:
            f.write(canonical_json(event).decode("utf-8") + "\n")
    print(f"  tampered: events_tampered.jsonl")

    # Canary file (for reference — both test suites hardcode the expected values)
    canary_path = FIXTURES_DIR / "canary.json"
    canary_path.write_bytes(canonical_json({
        "canonical_bytes": CANARY_CANONICAL.decode("utf-8"),
        "hash": CANARY_HASH,
        "object": CANARY_OBJECT,
    }))
    print(f"  canary:   canary.json")

    # Summary
    print(f"\nCanary object hash: {CANARY_HASH}")
    print(f"Artifact 1 hash:   {artifact1_hash}")
    print(f"Artifact 2 hash:   {artifact2_hash}")
    print(f"Decision hash:     {decision_hash}")
    print(f"Run seal:          {seal['run_seal']}")


if __name__ == "__main__":
    print(f"Generating golden fixtures in {FIXTURES_DIR}/\n")
    write_fixtures()
    print("\nDone.")
