"""Run context manager — start run, collect events, compute seal."""

import contextvars
import os
from contextlib import contextmanager
from datetime import datetime, timezone

from liminara.artifact_store import ArtifactStore
from liminara.config import LiminaraConfig
from liminara.decision_store import DecisionStore
from liminara.event_log import EventLog
from liminara.hash import canonical_json

_current_run: contextvars.ContextVar["RunContext | None"] = contextvars.ContextVar(
    "_current_run", default=None
)


def get_current_run() -> "RunContext | None":
    """Get the active run context, or None if outside a run."""
    return _current_run.get()


class RunContext:
    """Holds state for an active run."""

    def __init__(
        self,
        run_id: str,
        event_log: EventLog,
        artifact_store: ArtifactStore,
        decision_store: DecisionStore,
    ):
        self.run_id = run_id
        self.event_log = event_log
        self.artifact_store = artifact_store
        self.decision_store = decision_store
        self._node_counter = 0
        self._artifact_hashes: list[str] = []

    def next_node_id(self, name: str) -> str:
        """Generate the next node_id: {name}-{zero_padded_counter}."""
        self._node_counter += 1
        return f"{name}-{self._node_counter:03d}"

    def track_artifact(self, artifact_hash: str) -> None:
        """Track an artifact hash produced during this run."""
        self._artifact_hashes.append(artifact_hash)


@contextmanager
def run(pack_id: str, pack_version: str, config: LiminaraConfig | None = None):
    """Run context manager.

    Usage:
        with run("my_pack", "1.0.0") as r:
            ...
    """
    if config is None:
        config = LiminaraConfig()

    # Generate run_id: {pack_id}-{YYYYMMDDTHHMMSS}-{8 hex random}
    now = datetime.now(timezone.utc)
    timestamp = now.strftime("%Y%m%dT%H%M%S")
    random_hex = os.urandom(4).hex()
    run_id = f"{pack_id}-{timestamp}-{random_hex}"

    event_log = EventLog(runs_root=config.runs_root, run_id=run_id)
    artifact_store = ArtifactStore(root=config.store_root)
    decision_store = DecisionStore(runs_root=config.runs_root, run_id=run_id)

    ctx = RunContext(
        run_id=run_id,
        event_log=event_log,
        artifact_store=artifact_store,
        decision_store=decision_store,
    )

    token = _current_run.set(ctx)
    try:
        # Emit run_started
        event_log.append(
            event_type="run_started",
            payload={
                "run_id": run_id,
                "pack_id": pack_id,
                "pack_version": pack_version,
                "plan_hash": None,
            },
        )

        yield ctx

        # Normal exit: emit run_completed
        event_log.append(
            event_type="run_completed",
            payload={
                "run_id": run_id,
                "outcome": "success",
                "artifact_hashes": ctx._artifact_hashes,
            },
        )

        # Write seal.json
        events = event_log.read_all()
        run_completed_event = events[-1]
        seal = {
            "run_id": run_id,
            "run_seal": run_completed_event["event_hash"],
            "completed_at": run_completed_event["timestamp"],
            "event_count": len(events),
        }
        seal_path = config.runs_root / run_id / "seal.json"
        seal_path.write_bytes(canonical_json(seal))

    except Exception as exc:
        # Emit run_failed
        event_log.append(
            event_type="run_failed",
            payload={
                "run_id": run_id,
                "error_type": type(exc).__name__,
                "error_message": str(exc),
            },
        )
        raise
    finally:
        _current_run.reset(token)
