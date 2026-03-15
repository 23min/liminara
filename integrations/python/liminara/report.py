"""Article 12 compliance report generator."""

import json
from datetime import UTC, datetime
from pathlib import Path

from liminara.artifact_store import ArtifactStore
from liminara.event_log import EventLog


def generate_report(runs_root: Path, run_id: str, store_root: Path | None = None) -> dict:
    """Generate an Article 12 compliance report for a run.

    Args:
        runs_root: Root directory containing run directories.
        run_id: The run identifier.
        store_root: Optional artifact store root for size lookup.

    Returns:
        Report dict with all compliance fields.

    Raises:
        FileNotFoundError: If run directory does not exist.
    """
    runs_root = Path(runs_root)
    run_dir = runs_root / run_id

    if not run_dir.exists():
        raise FileNotFoundError(f"Run directory not found: {run_dir}")

    # Read events
    event_log = EventLog(runs_root=runs_root, run_id=run_id)
    events = event_log.read_all()

    # Verify hash chain
    chain_valid, chain_error = event_log.verify()

    # Read seal if exists
    seal_path = run_dir / "seal.json"
    run_seal = None
    if seal_path.exists():
        seal_data = json.loads(seal_path.read_bytes())
        run_seal = seal_data.get("run_seal")

    # Extract run metadata from run_started event
    run_started = next(e for e in events if e["event_type"] == "run_started")
    pack_id = run_started["payload"]["pack_id"]
    pack_version = run_started["payload"]["pack_version"]
    started_at = run_started["timestamp"]

    # completed_at is timestamp of last event
    completed_at = events[-1]["timestamp"]

    # outcome from last event type
    last_event_type = events[-1]["event_type"]
    outcome = "success" if last_event_type == "run_completed" else "failed"

    # Build operations list by pairing op_started/op_completed events
    op_started_events = {
        e["payload"]["node_id"]: e for e in events if e["event_type"] == "op_started"
    }
    op_completed_events = {
        e["payload"]["node_id"]: e for e in events if e["event_type"] == "op_completed"
    }
    decision_events = {
        e["payload"]["node_id"]: e for e in events if e["event_type"] == "decision_recorded"
    }

    operations = []
    for node_id, started in op_started_events.items():
        completed = op_completed_events.get(node_id)
        entry = {
            "node_id": node_id,
            "op_id": started["payload"]["op_id"],
            "op_version": started["payload"]["op_version"],
            "determinism": started["payload"].get("determinism"),
            "duration_ms": completed["payload"]["duration_ms"] if completed else None,
            "cache_hit": completed["payload"]["cache_hit"] if completed else None,
            "input_hashes": started["payload"]["input_hashes"],
            "output_hashes": completed["payload"]["output_hashes"] if completed else [],
            "has_decision": node_id in decision_events,
        }
        operations.append(entry)

    # Build artifacts list (unique hashes from all ops)
    artifact_hashes = set()
    for o in operations:
        artifact_hashes.update(o["input_hashes"])
        artifact_hashes.update(o["output_hashes"])

    artifact_store = ArtifactStore(root=Path(store_root)) if store_root else None
    artifacts = []
    for h in sorted(artifact_hashes):
        size = None
        if artifact_store:
            try:
                blob = artifact_store.read(h)
                size = len(blob)
            except FileNotFoundError:
                size = None
        artifacts.append({"artifact_hash": h, "size_bytes": size})

    # Build decisions list
    decisions = []
    for node_id, evt in decision_events.items():
        decisions.append(
            {
                "node_id": node_id,
                "decision_type": evt["payload"]["decision_type"],
                "decision_hash": evt["payload"]["decision_hash"],
            }
        )

    # Article 12 compliance fields
    inputs_traceable = all(
        "input_hashes" in e["payload"] for e in events if e["event_type"] == "op_started"
    )
    outputs_traceable = all(
        "output_hashes" in e["payload"] for e in events if e["event_type"] == "op_completed"
    )
    decisions_recorded = all(
        evt["payload"].get("decision_hash") is not None for evt in decision_events.values()
    )

    article_12 = {
        "logging_automatic": len(events) > 0,
        "tamper_evident": chain_valid,
        "inputs_traceable": inputs_traceable,
        "outputs_traceable": outputs_traceable,
        "decisions_recorded": decisions_recorded,
        "logs_retained": True,
    }

    generated_at = (
        datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%S.")
        + f"{datetime.now(UTC).microsecond // 1000:03d}Z"
    )

    return {
        "report_version": "1.0",
        "generated_at": generated_at,
        "run_id": run_id,
        "pack_id": pack_id,
        "pack_version": pack_version,
        "started_at": started_at,
        "completed_at": completed_at,
        "outcome": outcome,
        "event_count": len(events),
        "operations": operations,
        "artifacts": artifacts,
        "decisions": decisions,
        "hash_chain": {
            "verified": chain_valid,
            "error": chain_error,
            "run_seal": run_seal,
        },
        "article_12": article_12,
    }


def format_json(report: dict) -> str:
    """Format report as pretty-printed JSON with sorted keys."""
    return json.dumps(report, indent=2, sort_keys=True)


def format_human(report: dict) -> str:
    """Format report as human-readable plain text."""
    lines = []

    chain_check = "\u2713" if report["hash_chain"]["verified"] else "\u2717"
    seal = report["hash_chain"]["run_seal"] or "none (run failed)"

    lines.append(f"Run: {report['run_id']}")
    lines.append(f"Pack: {report['pack_id']} (v{report['pack_version']})")
    lines.append(f"Started: {report['started_at']}")
    lines.append(f"Completed: {report['completed_at']}")
    lines.append(f"Outcome: {report['outcome']}")
    lines.append(f"Events: {report['event_count']}")
    lines.append(f"Hash chain: {chain_check} intact")
    lines.append(f"Run seal: {seal}")
    lines.append("")

    lines.append("Operations:")
    for o in report["operations"]:
        cache_status = "hit" if o["cache_hit"] else "miss"
        duration = f"{o['duration_ms']:.0f}" if o["duration_ms"] is not None else "?"
        decision_note = "decision" if o["has_decision"] else ""
        op_id = o["op_id"]
        det = o["determinism"]
        lines.append(f"  {op_id:<20} {det:<16} {cache_status:<10} {duration}ms  {decision_note}")
    lines.append("")

    lines.append(f"Artifacts: {len(report['artifacts'])} unique")
    for a in report["artifacts"]:
        size = f"{a['size_bytes']} bytes" if a["size_bytes"] is not None else "unknown"
        lines.append(f"  {a['artifact_hash']} ({size})")
    lines.append("")

    a12 = report["article_12"]
    ec = report["event_count"]
    ops_count = len(report["operations"])
    completed_ops = sum(1 for o in report["operations"] if o["output_hashes"])
    decisions_count = len(report["decisions"])

    lines.append("Article 12 Compliance:")
    lines.append(f"  {_check(a12['logging_automatic'])} Automatic event recording ({ec} events)")
    lines.append(f"  {_check(a12['tamper_evident'])} Tamper-evident log (hash chain intact)")
    inp_check = _check(a12["inputs_traceable"])
    lines.append(f"  {inp_check} Input traceability ({ops_count} ops with recorded inputs)")
    out_check = _check(a12["outputs_traceable"])
    lines.append(f"  {out_check} Output traceability ({completed_ops} ops with recorded outputs)")
    lines.append(
        f"  {_check(a12['decisions_recorded'])} Decisions recorded ({decisions_count} decisions)"
    )
    lines.append(f"  {_check(a12['logs_retained'])} Logs retained on disk")

    return "\n".join(lines)


def format_markdown(report: dict) -> str:
    """Format report as markdown."""
    lines = []

    lines.append(f"# Compliance Report: {report['run_id']}")
    lines.append("")

    lines.append("## Run Metadata")
    lines.append("")
    lines.append(f"- **Pack:** {report['pack_id']} (v{report['pack_version']})")
    lines.append(f"- **Started:** {report['started_at']}")
    lines.append(f"- **Completed:** {report['completed_at']}")
    lines.append(f"- **Outcome:** {report['outcome']}")
    lines.append(f"- **Events:** {report['event_count']}")
    seal = report["hash_chain"]["run_seal"] or "none"
    lines.append(f"- **Run seal:** `{seal}`")
    lines.append("")

    lines.append("## Operations")
    lines.append("")
    lines.append("| Op | Determinism | Cache | Duration | Decision |")
    lines.append("|---|---|---|---|---|")
    for o in report["operations"]:
        cache = "hit" if o["cache_hit"] else "miss"
        duration = f"{o['duration_ms']:.0f}ms" if o["duration_ms"] is not None else "?"
        dec = "yes" if o["has_decision"] else "no"
        lines.append(f"| {o['op_id']} | {o['determinism']} | {cache} | {duration} | {dec} |")
    lines.append("")

    lines.append("## Artifacts")
    lines.append("")
    lines.append(f"{len(report['artifacts'])} unique artifacts.")
    lines.append("")

    a12 = report["article_12"]
    lines.append("## Article 12 Compliance")
    lines.append("")
    lines.append(f"- [{_md_check(a12['logging_automatic'])}] Automatic event recording")
    lines.append(f"- [{_md_check(a12['tamper_evident'])}] Tamper-evident log")
    lines.append(f"- [{_md_check(a12['inputs_traceable'])}] Input traceability")
    lines.append(f"- [{_md_check(a12['outputs_traceable'])}] Output traceability")
    lines.append(f"- [{_md_check(a12['decisions_recorded'])}] Decisions recorded")
    lines.append(f"- [{_md_check(a12['logs_retained'])}] Logs retained on disk")

    return "\n".join(lines)


def _check(val: bool) -> str:
    return "\u2713" if val else "\u2717"


def _md_check(val: bool) -> str:
    return "x" if val else " "
