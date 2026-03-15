"""@op and @decision decorators for wrapping functions with event recording."""

import contextvars
import functools
import time
from datetime import datetime, timezone

from liminara.hash import canonical_json, hash_bytes

_VALID_DETERMINISM = {"pure", "pinned_env", "recordable", "side_effecting"}
_VALID_DECISION_TYPES = {"llm_response", "human_gate", "stochastic", "model_selection"}

_current_node_id: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "_current_node_id", default=None
)
_current_op_id: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "_current_op_id", default=None
)
_current_op_version: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "_current_op_version", default=None
)


def op(name: str, version: str, determinism: str):
    """Decorator that instruments a function as a Liminara op.

    Emits op_started/op_completed/op_failed events, stores input/output
    as artifacts. Passthrough when called outside a run context.
    """
    if determinism not in _VALID_DETERMINISM:
        raise ValueError(
            f"Invalid determinism {determinism!r}. Must be one of: {sorted(_VALID_DETERMINISM)}"
        )

    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            from liminara.run import get_current_run

            run_ctx = get_current_run()
            if run_ctx is None:
                return fn(*args, **kwargs)

            node_id = run_ctx.next_node_id(name)

            # Set context vars for inner @decision
            prev_node = _current_node_id.set(node_id)
            prev_op_id = _current_op_id.set(name)
            prev_op_version = _current_op_version.set(version)

            try:
                # Serialize and store inputs
                input_data = {"args": list(args), "kwargs": kwargs}
                input_bytes = canonical_json(input_data)
                input_hash = run_ctx.artifact_store.write(input_bytes)
                run_ctx.track_artifact(input_hash)

                # Emit op_started
                run_ctx.event_log.append(
                    event_type="op_started",
                    payload={
                        "node_id": node_id,
                        "op_id": name,
                        "op_version": version,
                        "input_hashes": [input_hash],
                    },
                )

                # Call the wrapped function
                start = time.perf_counter()
                try:
                    result = fn(*args, **kwargs)
                except Exception as exc:
                    duration_ms = (time.perf_counter() - start) * 1000
                    run_ctx.event_log.append(
                        event_type="op_failed",
                        payload={
                            "node_id": node_id,
                            "error_type": type(exc).__name__,
                            "error_message": str(exc),
                        },
                    )
                    raise

                duration_ms = (time.perf_counter() - start) * 1000

                # Store output as artifact
                output_bytes = canonical_json(result)
                output_hash = run_ctx.artifact_store.write(output_bytes)
                run_ctx.track_artifact(output_hash)

                # Emit op_completed
                run_ctx.event_log.append(
                    event_type="op_completed",
                    payload={
                        "node_id": node_id,
                        "output_hashes": [output_hash],
                        "cache_hit": False,
                        "duration_ms": duration_ms,
                    },
                )

                return result
            finally:
                _current_node_id.reset(prev_node)
                _current_op_id.reset(prev_op_id)
                _current_op_version.reset(prev_op_version)

        return wrapper

    return decorator


def decision(decision_type: str):
    """Decorator that records a function's result as a decision.

    Must be used inside an @op decorator to have context (node_id, op_id, op_version).
    Passthrough when called outside a run context or outside an @op.
    """
    if decision_type not in _VALID_DECISION_TYPES:
        raise ValueError(
            f"Invalid decision_type {decision_type!r}. "
            f"Must be one of: {sorted(_VALID_DECISION_TYPES)}"
        )

    def decorator(fn):
        @functools.wraps(fn)
        def wrapper(*args, **kwargs):
            from liminara.run import get_current_run

            run_ctx = get_current_run()
            node_id = _current_node_id.get()

            # Passthrough if no run context or no enclosing @op
            if run_ctx is None or node_id is None:
                return fn(*args, **kwargs)

            result = fn(*args, **kwargs)

            # Hash inputs and output
            input_data = {"args": list(args), "kwargs": kwargs}
            input_bytes = canonical_json(input_data)
            args_hash = hash_bytes(input_bytes)

            result_bytes = canonical_json(result)
            result_hash = hash_bytes(result_bytes)

            timestamp = (
                datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.")
                + f"{datetime.now(timezone.utc).microsecond // 1000:03d}Z"
            )

            # Write decision record
            record = {
                "node_id": node_id,
                "op_id": _current_op_id.get(),
                "op_version": _current_op_version.get(),
                "decision_type": decision_type,
                "inputs": {"args_hash": args_hash},
                "output": {"result_hash": result_hash},
                "recorded_at": timestamp,
            }
            decision_hash = run_ctx.decision_store.write(record)

            # Emit decision_recorded event
            run_ctx.event_log.append(
                event_type="decision_recorded",
                payload={
                    "node_id": node_id,
                    "decision_hash": decision_hash,
                    "decision_type": decision_type,
                },
            )

            return result

        return wrapper

    return decorator
