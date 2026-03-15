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
        "events": [
            {
                "event_type": e["event_type"],
                "event_hash": e["event_hash"],
                "prev_hash": e["prev_hash"],
                "timestamp": e["timestamp"],
            }
            for e in events
        ],
        "paths": {
            "runs_root": str(runs_root),
            "run_dir": str(run_dir),
            "event_log": str(run_dir / "events.jsonl"),
            "seal": str(run_dir / "seal.json"),
            "decisions": str(run_dir / "decisions"),
            "store_root": str(store_root) if store_root else None,
        },
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
    ops = report["operations"]
    decisions = report["decisions"]
    hc = report["hash_chain"]
    ec = report["event_count"]
    ops_with_inputs = [o for o in ops if o["input_hashes"]]
    ops_with_outputs = [o for o in ops if o["output_hashes"]]

    lines.append("## Article 12 Compliance")
    lines.append("")

    # 1. Automatic event recording
    lines.append(f"- [{_md_check(a12['logging_automatic'])}] **Automatic event recording**")
    lines.append(f"  - {ec} events recorded automatically via SDK decorators")
    lines.append("")

    # 2. Tamper-evident log
    lines.append(f"- [{_md_check(a12['tamper_evident'])}] **Tamper-evident log**")
    if hc["verified"]:
        lines.append(f"  - Hash chain of {ec} events verified intact")
    else:
        lines.append(f"  - Hash chain verification failed: {hc['error']}")
    if hc["run_seal"]:
        lines.append(f"  - Run seal: `{hc['run_seal']}`")
    lines.append("")
    events_list = report.get("events", [])
    if events_list:
        lines.append("  **Hash chain:**")
        lines.append("")
        lines.append("  | # | Event | Hash | Prev |")
        lines.append("  |---|---|---|---|")
        for i, evt in enumerate(events_list):
            h = evt["event_hash"][:16] + "..."
            p = evt["prev_hash"][:16] + "..." if evt["prev_hash"] else "null"
            prev_matches = i == 0 or evt["prev_hash"] == events_list[i - 1]["event_hash"]
            link = "\u2713" if prev_matches else "\u2717"
            lines.append(f"  | {i + 1} {link} | {evt['event_type']} | `{h}` | `{p}` |")
        lines.append("")

    # 3. Input traceability
    lines.append(f"- [{_md_check(a12['inputs_traceable'])}] **Input traceability**")
    for o in ops_with_inputs:
        hashes = ", ".join(f"`{h[:20]}...`" for h in o["input_hashes"])
        lines.append(f"  - `{o['op_id']}`: {hashes}")
    lines.append("")

    # 4. Output traceability
    lines.append(f"- [{_md_check(a12['outputs_traceable'])}] **Output traceability**")
    for o in ops_with_outputs:
        hashes = ", ".join(f"`{h[:20]}...`" for h in o["output_hashes"])
        lines.append(f"  - `{o['op_id']}`: {hashes}")
    lines.append("")

    # 5. Decisions recorded
    lines.append(f"- [{_md_check(a12['decisions_recorded'])}] **Decisions recorded**")
    if decisions:
        for d in decisions:
            lines.append(
                f"  - `{d['node_id']}`: {d['decision_type']}, hash `{d['decision_hash'][:20]}...`"
            )
    else:
        lines.append("  - No nondeterministic decisions in this run")
    lines.append("")

    # 6. Logs retained
    paths = report.get("paths", {})
    lines.append(f"- [{_md_check(a12['logs_retained'])}] **Logs retained on disk**")
    if paths:
        lines.append(f"  - Event log: `{paths['event_log']}`")
        lines.append(f"  - Seal: `{paths['seal']}`")
        lines.append(f"  - Decisions: `{paths['decisions']}/`")
        if paths.get("store_root"):
            lines.append(f"  - Artifacts: `{paths['store_root']}/`")
    else:
        lines.append("  - Event log, artifacts, and decision records stored on filesystem")

    lines.append("")
    lines.append("---")
    lines.append("")
    lines.append(
        f"*Report generated at {report['generated_at']} "
        f"by Liminara SDK v{report['report_version']}*"
    )

    return "\n".join(lines)


def _check(val: bool) -> str:
    return "\u2713" if val else "\u2717"


def _md_check(val: bool) -> str:
    return "x" if val else " "
