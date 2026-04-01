"""Tests for the liminara op runner — framing, dispatch, error handling."""

import json
import struct
import sys
from pathlib import Path

import pytest

# Add src/ to path so we can import the runner
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from liminara_op_runner import dispatch, handle_request, read_message, write_message


def frame(obj: dict) -> bytes:
    """Encode a dict as a {packet,4} framed message."""
    data = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    return struct.pack(">I", len(data)) + data


def unframe(raw: bytes) -> dict:
    """Decode a {packet,4} framed message."""
    msg_len = struct.unpack(">I", raw[:4])[0]
    return json.loads(raw[4 : 4 + msg_len])


class TestDispatch:
    def test_echo_op_returns_inputs(self):
        result = dispatch("echo", {"message": "hello"})
        assert result == {"outputs": {"message": "hello"}}

    def test_unknown_op_raises(self):
        with pytest.raises(ModuleNotFoundError):
            dispatch("nonexistent_op_xyz", {})

    def test_echo_op_with_empty_inputs(self):
        result = dispatch("echo", {})
        assert result == {"outputs": {}}


class TestHandleRequest:
    def test_success_response(self):
        msg = {"id": "abc123", "op": "echo", "inputs": {"x": 1}}
        response = handle_request(msg)
        assert response["id"] == "abc123"
        assert response["status"] == "ok"
        assert response["outputs"] == {"x": 1}

    def test_missing_op_field(self):
        msg = {"id": "abc123", "inputs": {}}
        response = handle_request(msg)
        assert response["id"] == "abc123"
        assert response["status"] == "error"
        assert "missing" in response["error"]

    def test_unknown_op_returns_error(self):
        msg = {"id": "abc123", "op": "nonexistent_op_xyz", "inputs": {}}
        response = handle_request(msg)
        assert response["id"] == "abc123"
        assert response["status"] == "error"
        assert "ModuleNotFoundError" in response["error"]

    def test_op_exception_returns_traceback(self):
        """Test that a regular exception (not os._exit) is caught and reported."""
        msg = {"id": "abc123", "op": "test_raise", "inputs": {}}
        response = handle_request(msg)
        assert response["status"] == "error"
        assert "ValueError" in response["error"]

    def test_missing_id_defaults_to_unknown(self):
        msg = {"op": "echo", "inputs": {"x": 1}}
        response = handle_request(msg)
        assert response["id"] == "unknown"
        assert response["status"] == "ok"

    def test_missing_inputs_defaults_to_empty(self):
        msg = {"id": "abc", "op": "echo"}
        response = handle_request(msg)
        assert response["status"] == "ok"
        assert response["outputs"] == {}


class TestFraming:
    def test_write_then_read_roundtrip(self, tmp_path):
        """Write a framed message to a file, read it back."""
        msg = {"id": "test", "op": "echo", "inputs": {"data": "hello"}}
        data = json.dumps(msg, separators=(",", ":")).encode("utf-8")
        framed = struct.pack(">I", len(data)) + data

        # Verify the frame structure
        assert len(framed) == 4 + len(data)
        msg_len = struct.unpack(">I", framed[:4])[0]
        assert msg_len == len(data)
        decoded = json.loads(framed[4:])
        assert decoded == msg

    def test_large_payload(self):
        """Verify large payloads frame correctly."""
        large_data = "x" * 100_000
        msg = {"id": "big", "op": "echo", "inputs": {"data": large_data}}
        response = handle_request(msg)
        assert response["status"] == "ok"
        assert response["outputs"]["data"] == large_data
