"""CLI entry point for Liminara."""

import click


@click.group()
@click.version_option(package_name="liminara")
def main() -> None:
    """Liminara — reproducible nondeterministic computation with compliance reporting."""


@main.command()
def list() -> None:
    """List all recorded runs."""
    click.echo("Not yet implemented.")


@main.command()
@click.argument("run_id")
def verify(run_id: str) -> None:
    """Verify hash chain integrity of a run's event log."""
    click.echo(f"Not yet implemented for run {run_id}.")


@main.command()
@click.argument("run_id")
@click.option("--format", "fmt", type=click.Choice(["json", "human", "markdown"]), default="json")
def report(run_id: str, fmt: str) -> None:
    """Generate Article 12 compliance report for a run."""
    click.echo(f"Not yet implemented for run {run_id} (format={fmt}).")
