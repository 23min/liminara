"""Liminara Python op runner.

Generic dispatcher: reads {packet,4} length-framed JSON from stdin,
routes to op modules, writes length-framed JSON responses to stdout.

Protocol:
  Request:  {"id": "...", "op": "module_name", "inputs": {...}}
  Success:  {"id": "...", "status": "ok", "outputs": {...}}
  With decisions: {"id": "...", "status": "ok", "outputs": {...}, "decisions": [...]}
  Error:    {"id": "...", "status": "error", "error": "message"}
"""

import importlib
import json
import struct
import sys
import traceback


def read_message():
    """Read a {packet,4} length-framed message from stdin."""
    raw_len = sys.stdin.buffer.read(4)
    if len(raw_len) < 4:
        return None
    msg_len = struct.unpack(">I", raw_len)[0]
    data = sys.stdin.buffer.read(msg_len)
    if len(data) < msg_len:
        return None
    return json.loads(data)


def write_message(obj):
    """Write a {packet,4} length-framed message to stdout."""
    data = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    sys.stdout.buffer.write(struct.pack(">I", len(data)))
    sys.stdout.buffer.write(data)
    sys.stdout.buffer.flush()


def dispatch(op_name, inputs):
    """Import and execute an op module by name."""
    module = importlib.import_module(f"ops.{op_name}")
    return module.execute(inputs)


def handle_request(msg):
    """Process a single request and return a response dict."""
    req_id = msg.get("id", "unknown")
    op_name = msg.get("op")
    inputs = msg.get("inputs", {})

    if not op_name:
        return {"id": req_id, "status": "error", "error": "missing 'op' field"}

    try:
        result = dispatch(op_name, inputs)
    except SystemExit as e:
        return {"id": req_id, "status": "error", "error": f"SystemExit: {e.code}"}
    except Exception:
        return {"id": req_id, "status": "error", "error": traceback.format_exc()}

    response = {"id": req_id, "status": "ok"}
    if isinstance(result, dict):
        response["outputs"] = result.get("outputs", result)
        if "decisions" in result:
            response["decisions"] = result["decisions"]
    else:
        response["outputs"] = result

    return response


def main():
    """Main loop: read requests, dispatch, write responses."""
    while True:
        msg = read_message()
        if msg is None:
            break
        response = handle_request(msg)
        write_message(response)


if __name__ == "__main__":
    main()
