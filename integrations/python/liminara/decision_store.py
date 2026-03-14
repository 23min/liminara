"""Decision record storage for nondeterministic choices."""

import hashlib
import json
from pathlib import Path

from liminara.hash import canonical_json


class DecisionStore:
    """Decision record store.

    File layout: {runs_root}/{run_id}/decisions/{node_id}.json
    Each file is canonical JSON. decision_hash is computed over all fields
    except decision_hash itself.
    """

    def __init__(self, runs_root: Path, run_id: str) -> None:
        self.runs_root = runs_root
        self.run_id = run_id

    def write(self, record: dict) -> str:
        """Write decision record, return decision_hash.

        Computes decision_hash over all fields in the record (excluding
        decision_hash itself, if present).
        """
        # Compute hash over all fields except decision_hash
        hashable = {k: v for k, v in record.items() if k != "decision_hash"}
        decision_hash = "sha256:" + hashlib.sha256(canonical_json(hashable)).hexdigest()

        # Store with decision_hash included
        full_record = {**record, "decision_hash": decision_hash}
        node_id = record["node_id"]

        path = self._node_path(node_id)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(canonical_json(full_record))

        return decision_hash

    def read(self, node_id: str) -> dict:
        """Read decision record by node_id. Raises FileNotFoundError if not found."""
        path = self._node_path(node_id)
        return json.loads(path.read_bytes())

    def _node_path(self, node_id: str) -> Path:
        """Path for a decision record file."""
        return self.runs_root / self.run_id / "decisions" / f"{node_id}.json"
