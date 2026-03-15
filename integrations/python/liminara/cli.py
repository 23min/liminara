"""CLI entry point for Liminara."""

import json
import sys
from pathlib import Path

import click

from liminara.event_log import EventLog
from liminara.report import format_human, format_json, format_markdown, generate_report


@click.group()
@click.version_option(package_name="liminara")
def main() -> None:
    """Liminara — reproducible nondeterministic computation with compliance reporting."""


@main.command("list")
@click.option("--runs-root", default=".liminara/runs", type=click.Path())
def list_runs(runs_root: str) -> None:
    """List all recorded runs."""
    root = Path(runs_root)

    if not root.exists():
        click.echo("No runs found.", err=True)
        return

    # Find all run directories that contain events.jsonl
    run_dirs = sorted(
        [d for d in root.iterdir() if d.is_dir() and (d / "events.jsonl").exists()],
        key=lambda d: d.name,
        reverse=True,  # newest first
    )

    if not run_dirs:
        click.echo("No runs found.", err=True)
        return

    for d in run_dirs:
        run_id = d.name
        event_log = EventLog(runs_root=root, run_id=run_id)
        events = event_log.read_all()
        event_count = len(events)

        # Determine started_at from first event
        started_at = events[0]["timestamp"] if events else "unknown"

        # Determine status
        seal_path = d / "seal.json"
        if seal_path.exists():
            status = "sealed"
        elif events and events[-1]["event_type"] == "run_failed":
            status = "failed"
        else:
            status = "unsealed"

        click.echo(f"{run_id}  {started_at}  {event_count:>4} events  {status}")


@main.command()
@click.argument("run_id")
@click.option("--runs-root", default=".liminara/runs", type=click.Path())
def verify(run_id: str, runs_root: str) -> None:
    """Verify hash chain integrity of a run's event log."""
    root = Path(runs_root)
    run_dir = root / run_id

    if not run_dir.exists() or not (run_dir / "events.jsonl").exists():
        click.echo(f"Run not found: {run_id}", err=True)
        sys.exit(1)

    event_log = EventLog(runs_root=root, run_id=run_id)
    events = event_log.read_all()
    valid, error = event_log.verify()

    if not valid:
        click.echo(f"Hash chain verification failed: {error}", err=True)
        sys.exit(1)

    click.echo(f"Hash chain verified. {len(events)} events, chain intact.")

    # Check seal
    seal_path = run_dir / "seal.json"
    if seal_path.exists():
        seal_data = json.loads(seal_path.read_bytes())
        run_seal = seal_data.get("run_seal")
        click.echo(f"Run seal: {run_seal}")


@main.command()
@click.argument("run_id")
@click.option("--format", "fmt", type=click.Choice(["json", "human", "markdown"]), default="json")
@click.option("--runs-root", default=".liminara/runs", type=click.Path())
@click.option("--store-root", default=".liminara/store/artifacts", type=click.Path())
def report(run_id: str, fmt: str, runs_root: str, store_root: str) -> None:
    """Generate Article 12 compliance report for a run."""
    root = Path(runs_root)

    try:
        report_data = generate_report(root, run_id, store_root=Path(store_root))
    except FileNotFoundError:
        click.echo(f"Run not found: {run_id}", err=True)
        sys.exit(1)

    if fmt == "json":
        click.echo(format_json(report_data))
    elif fmt == "human":
        click.echo(format_human(report_data))
    elif fmt == "markdown":
        click.echo(format_markdown(report_data))
