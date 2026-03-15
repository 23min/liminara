"""Tests for hash.py — SHA-256 hashing and canonical JSON serialization.

Spec reference: docs/analysis/11_Data_Model_Spec.md
"""

import hashlib
import json

from liminara.hash import canonical_json, hash_bytes, hash_event


class TestHashBytes:
    """SHA-256 hashing of raw bytes."""

    def test_known_input(self):
        """Known input produces expected SHA-256 hash."""
        data = b"hello"
        expected_hex = hashlib.sha256(b"hello").hexdigest()
        result = hash_bytes(data)
        assert result == f"sha256:{expected_hex}"

    def test_encoding_format(self):
        """Hash is encoded as 'sha256:{64 lowercase hex chars}'."""
        result = hash_bytes(b"test")
        assert result.startswith("sha256:")
        hex_part = result[7:]
        assert len(hex_part) == 64
        assert hex_part == hex_part.lower()
        # All chars are valid hex
        int(hex_part, 16)

    def test_empty_bytes(self):
        """Empty bytes produce the SHA-256 of empty input."""
        expected_hex = hashlib.sha256(b"").hexdigest()
        result = hash_bytes(b"")
        assert result == f"sha256:{expected_hex}"

    def test_deterministic(self):
        """Same input always produces same hash."""
        assert hash_bytes(b"deterministic") == hash_bytes(b"deterministic")

    def test_different_inputs_different_hashes(self):
        """Different inputs produce different hashes."""
        assert hash_bytes(b"a") != hash_bytes(b"b")


class TestCanonicalJson:
    """RFC 8785 canonical JSON serialization."""

    def test_sorted_keys(self):
        """Keys are sorted lexicographically."""
        data = {"z": 1, "a": 2, "m": 3}
        result = canonical_json(data)
        parsed = json.loads(result)
        assert list(parsed.keys()) == ["a", "m", "z"]

    def test_no_whitespace(self):
        """No whitespace between tokens."""
        data = {"key": "value", "num": 42}
        result = canonical_json(data)
        assert b" " not in result
        assert b"\n" not in result
        assert b"\t" not in result

    def test_nested_sorted_keys(self):
        """Nested objects also have sorted keys."""
        data = {"outer": {"z": 1, "a": 2}}
        result = canonical_json(data)
        # Parse and verify nested key order in the raw bytes
        assert result.index(b'"a"') < result.index(b'"z"')

    def test_returns_bytes(self):
        """canonical_json returns UTF-8 bytes, not a string."""
        result = canonical_json({"key": "value"})
        assert isinstance(result, bytes)

    def test_utf8_encoding(self):
        """Unicode characters are properly encoded as UTF-8."""
        data = {"name": "café"}
        result = canonical_json(data)
        assert "café".encode() in result

    def test_null_value(self):
        """null values serialize correctly."""
        data = {"key": None}
        result = canonical_json(data)
        assert b"null" in result

    def test_deterministic(self):
        """Same input always produces same bytes."""
        data = {"b": 2, "a": 1}
        assert canonical_json(data) == canonical_json(data)

    def test_integer_no_trailing_zeros(self):
        """Integers are serialized without trailing zeros or scientific notation."""
        data = {"n": 42}
        result = canonical_json(data)
        assert b"42" in result


class TestHashEvent:
    """Event hash computation per spec.

    event_hash = sha256(utf8(canonical_json({
        "event_type": event_type,
        "payload":    payload,
        "prev_hash":  prev_hash,
        "timestamp":  timestamp
    })))

    Note: event_hash itself is NOT included in the hash input.
    """

    def test_hash_event_format(self):
        """hash_event returns sha256:{64 hex} format."""
        result = hash_event(
            event_type="op_started",
            payload={"node_id": "n1"},
            prev_hash=None,
            timestamp="2026-03-14T12:00:00.000Z",
        )
        assert result.startswith("sha256:")
        assert len(result) == 7 + 64

    def test_hash_event_deterministic(self):
        """Same inputs produce same hash."""
        h1 = hash_event(
            event_type="op_started",
            payload={"node_id": "n1"},
            prev_hash=None,
            timestamp="2026-03-14T12:00:00.000Z",
        )
        h2 = hash_event(
            event_type="op_started",
            payload={"node_id": "n1"},
            prev_hash=None,
            timestamp="2026-03-14T12:00:00.000Z",
        )
        assert h1 == h2

    def test_hash_event_matches_manual_computation(self):
        """hash_event matches manual canonical JSON + SHA-256."""
        event_type = "run_started"
        payload = {"run_id": "test-run-1"}
        prev_hash = None
        timestamp = "2026-03-14T12:00:00.000Z"

        # Manual computation
        hash_input = canonical_json(
            {
                "event_type": event_type,
                "payload": payload,
                "prev_hash": prev_hash,
                "timestamp": timestamp,
            }
        )
        expected = "sha256:" + hashlib.sha256(hash_input).hexdigest()

        result = hash_event(event_type, payload, prev_hash, timestamp)
        assert result == expected

    def test_hash_event_with_prev_hash(self):
        """hash_event works correctly when prev_hash is not null."""
        result = hash_event(
            event_type="op_completed",
            payload={"node_id": "n1"},
            prev_hash="sha256:abc123" + "0" * 58,
            timestamp="2026-03-14T12:00:01.000Z",
        )
        assert result.startswith("sha256:")
        assert len(result) == 7 + 64

    def test_different_payloads_different_hashes(self):
        """Different payloads produce different hashes."""
        h1 = hash_event(
            event_type="op_started",
            payload={"node_id": "n1"},
            prev_hash=None,
            timestamp="2026-03-14T12:00:00.000Z",
        )
        h2 = hash_event(
            event_type="op_started",
            payload={"node_id": "n2"},
            prev_hash=None,
            timestamp="2026-03-14T12:00:00.000Z",
        )
        assert h1 != h2
