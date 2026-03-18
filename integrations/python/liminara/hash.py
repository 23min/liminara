"""SHA-256 hashing and canonical JSON serialization (RFC 8785)."""

import hashlib

import canonicaljson


def hash_bytes(raw_bytes: bytes) -> str:
    """Return SHA-256 hash of raw bytes as 'sha256:{64 lowercase hex}'."""
    hex_digest = hashlib.sha256(raw_bytes).hexdigest()
    return f"sha256:{hex_digest}"


def canonical_json(obj: dict | list | str | int | float | bool | None) -> bytes:
    """Serialize JSON-serializable value to RFC 8785 canonical JSON (UTF-8 bytes)."""
    return canonicaljson.encode_canonical_json(obj)


def hash_event(
    event_type: str,
    payload: dict,
    prev_hash: str | None,
    timestamp: str,
) -> str:
    """Compute event hash: SHA-256 of canonical JSON of the four event fields.

    The event_hash field itself is NOT included in the hash input.
    """
    hash_input = canonical_json(
        {
            "event_type": event_type,
            "payload": payload,
            "prev_hash": prev_hash,
            "timestamp": timestamp,
        }
    )
    return hash_bytes(hash_input)
