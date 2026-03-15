"""Demo script — runs the full compliance story.

Requires ANTHROPIC_API_KEY to be set.

Usage:
    uv run python examples/01_raw_python/demo.py
"""

import json
import os
import sys
from pathlib import Path

# Ensure the example directory is importable
sys.path.insert(0, str(Path(__file__).resolve().parent))


def _load_dotenv() -> None:
    """Load .env file from the project root (integrations/python/) if it exists."""
    env_path = Path(__file__).resolve().parent.parent.parent / ".env"
    if not env_path.exists():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip("\"'")
        if key and key not in os.environ:
            os.environ[key] = value


def main() -> None:
    _load_dotenv()

    if not os.environ.get("ANTHROPIC_API_KEY"):
        print("Error: ANTHROPIC_API_KEY environment variable is not set.", file=sys.stderr)
        print("Get an API key at https://console.anthropic.com/", file=sys.stderr)
        sys.exit(1)

    import pipeline_instrumented
    import pipeline_raw

    from liminara.event_log import EventLog
    from liminara.report import format_human, format_markdown, generate_report

    # --- Step 1: Raw pipeline ---
    print("=" * 60)
    print("STEP 1: Raw pipeline (no instrumentation)")
    print("=" * 60)
    print()
    raw_result = pipeline_raw.run_pipeline()
    print(raw_result)
    print()
    print("-> No compliance artifacts. No event log. No audit trail.")
    print()

    # --- Step 2: Instrumented pipeline (first run) ---
    print("=" * 60)
    print("STEP 2: Instrumented pipeline (first run)")
    print("=" * 60)
    print()
    summary_1, run_id_1 = pipeline_instrumented.run_pipeline()
    print(summary_1)
    print()

    events_1 = EventLog(runs_root=Path(".liminara/runs"), run_id=run_id_1).read_all()
    seal_path_1 = Path(".liminara/runs") / run_id_1 / "seal.json"
    seal_1 = json.loads(seal_path_1.read_bytes()) if seal_path_1.exists() else None
    decisions_dir_1 = Path(".liminara/runs") / run_id_1 / "decisions"
    decision_count_1 = len(list(decisions_dir_1.glob("*.json"))) if decisions_dir_1.exists() else 0

    print(f"-> Run ID: {run_id_1}")
    print(f"-> Events recorded: {len(events_1)}")
    print(f"-> Decisions captured: {decision_count_1}")
    if seal_1:
        print(f"-> Run seal: {seal_1['run_seal']}")
    print()

    # --- Step 3: Instrumented pipeline (second run) ---
    print("=" * 60)
    print("STEP 3: Instrumented pipeline (second run)")
    print("=" * 60)
    print()
    summary_2, run_id_2 = pipeline_instrumented.run_pipeline()
    print(summary_2)
    print()

    events_2 = EventLog(runs_root=Path(".liminara/runs"), run_id=run_id_2).read_all()

    print(f"-> Run ID: {run_id_2}")
    print(f"-> Events recorded: {len(events_2)}")
    if summary_1 != summary_2:
        print("-> Different LLM response (nondeterministic) — but fully recorded.")
    else:
        print("-> Same LLM response this time — still fully recorded.")
    print()

    # --- Step 4: List all runs ---
    print("=" * 60)
    print("STEP 4: All recorded runs")
    print("=" * 60)
    print()
    runs_root = Path(".liminara/runs")
    for run_dir in sorted(runs_root.iterdir(), reverse=True):
        if (run_dir / "events.jsonl").exists():
            el = EventLog(runs_root=runs_root, run_id=run_dir.name)
            evts = el.read_all()
            seal_p = run_dir / "seal.json"
            status = "sealed" if seal_p.exists() else "unsealed"
            print(f"  {run_dir.name}  {len(evts)} events  {status}")
    print()

    # --- Step 5: Article 12 compliance report ---
    print("=" * 60)
    print("STEP 5: Article 12 Compliance Report")
    print("=" * 60)
    print()
    report = generate_report(
        runs_root=runs_root,
        run_id=run_id_2,
        store_root=Path(".liminara/store/artifacts"),
    )
    print(format_human(report))
    print()

    # --- Step 6: Save markdown report ---
    report_path = Path(f"compliance-report-{run_id_2}.md")
    report_path.write_text(format_markdown(report))
    print(f"-> Markdown report saved to: {report_path}")
    print()

    # --- Punchline ---
    print("=" * 60)
    print("RESULT")
    print("=" * 60)
    print()
    print("Both instrumented runs are independently auditable.")
    print("Every nondeterministic choice (LLM response) is recorded as a decision.")
    print("The hash chain proves nothing was tampered with.")
    print("Stored decisions enable exact replay (Elixir runtime, future).")


if __name__ == "__main__":
    main()
