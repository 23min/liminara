"""Tests for the CLI commands (list, verify, report)."""

import json
from pathlib import Path

import pytest
from click.testing import CliRunner

from liminara import LiminaraConfig, decision, op, run
from liminara.cli import main


@pytest.fixture
def config(tmp_path: Path) -> LiminaraConfig:
    """Config pointing to temp directories."""
    return LiminaraConfig(
        store_root=tmp_path / "store" / "artifacts",
        runs_root=tmp_path / "runs",
    )


@pytest.fixture
def runner() -> CliRunner:
    return CliRunner()


def _create_run(config: LiminaraConfig, pack_id: str = "testpack") -> str:
    """Create a successful run. Returns run_id."""

    @op(name="greet", version="1.0.0", determinism="pure")
    def greet(name: str) -> str:
        return f"Hello, {name}!"

    @op(name="choose", version="1.0.0", determinism="recordable")
    @decision(decision_type="llm_response")
    def choose(text: str) -> str:
        return f"Chose: {text}"

    with run(pack_id, "0.1.0", config=config) as r:
        result = greet("world")
        choose(result)

    return r.run_id


def _create_failed_run(config: LiminaraConfig) -> str:
    """Create a failed run. Returns run_id."""

    @op(name="fail_op", version="1.0.0", determinism="pure")
    def fail_op() -> str:
        raise ValueError("test failure")

    try:
        with run("failpack", "0.1.0", config=config) as r:
            fail_op()
    except ValueError:
        pass

    return r.run_id


class TestListCommand:
    """Tests for `liminara list`."""

    def test_no_runs_shows_message(self, runner: CliRunner, tmp_path: Path):
        runs_root = tmp_path / "runs"
        runs_root.mkdir()
        result = runner.invoke(main, ["list", "--runs-root", str(runs_root)])
        assert result.exit_code == 0
        assert "No runs found" in result.output

    def test_lists_two_runs(self, runner: CliRunner, config: LiminaraConfig):
        run_id_1 = _create_run(config, pack_id="pack_a")
        run_id_2 = _create_run(config, pack_id="pack_b")

        result = runner.invoke(main, ["list", "--runs-root", str(config.runs_root)])
        assert result.exit_code == 0
        assert run_id_1 in result.output
        assert run_id_2 in result.output

    def test_runs_sorted_newest_first(self, runner: CliRunner, config: LiminaraConfig):
        run_id_1 = _create_run(config, pack_id="first")
        run_id_2 = _create_run(config, pack_id="second")

        result = runner.invoke(main, ["list", "--runs-root", str(config.runs_root)])
        # Newest (run_id_2) should appear before oldest (run_id_1)
        pos_1 = result.output.index(run_id_1)
        pos_2 = result.output.index(run_id_2)
        assert pos_2 < pos_1


class TestVerifyCommand:
    """Tests for `liminara verify`."""

    def test_valid_run_exit_code_0(self, runner: CliRunner, config: LiminaraConfig):
        run_id = _create_run(config)
        result = runner.invoke(main, ["verify", run_id, "--runs-root", str(config.runs_root)])
        assert result.exit_code == 0
        assert "verified" in result.output.lower()

    def test_tampered_run_exit_code_1(self, runner: CliRunner, config: LiminaraConfig):
        run_id = _create_run(config)

        # Tamper with the event log
        events_path = config.runs_root / run_id / "events.jsonl"
        lines = events_path.read_text().splitlines()
        event = json.loads(lines[1])
        event["payload"]["op_id"] = "TAMPERED"
        lines[1] = json.dumps(event)
        events_path.write_text("\n".join(lines) + "\n")

        result = runner.invoke(main, ["verify", run_id, "--runs-root", str(config.runs_root)])
        assert result.exit_code == 1

    def test_nonexistent_run_exit_code_1(self, runner: CliRunner, tmp_path: Path):
        runs_root = tmp_path / "runs"
        runs_root.mkdir()
        result = runner.invoke(main, ["verify", "no-such-run", "--runs-root", str(runs_root)])
        assert result.exit_code == 1
        assert "not found" in result.output.lower()

    def test_shows_seal_when_exists(self, runner: CliRunner, config: LiminaraConfig):
        run_id = _create_run(config)
        result = runner.invoke(main, ["verify", run_id, "--runs-root", str(config.runs_root)])
        assert "seal" in result.output.lower()


class TestReportCommand:
    """Tests for `liminara report`."""

    def test_default_format_is_json(self, runner: CliRunner, config: LiminaraConfig):
        run_id = _create_run(config)
        result = runner.invoke(
            main,
            ["report", run_id, "--runs-root", str(config.runs_root)],
        )
        assert result.exit_code == 0
        parsed = json.loads(result.output)
        assert parsed["report_version"] == "1.0"

    def test_human_format(self, runner: CliRunner, config: LiminaraConfig):
        run_id = _create_run(config)
        result = runner.invoke(
            main,
            [
                "report",
                run_id,
                "--format",
                "human",
                "--runs-root",
                str(config.runs_root),
            ],
        )
        assert result.exit_code == 0
        assert "Article 12 Compliance" in result.output

    def test_markdown_format(self, runner: CliRunner, config: LiminaraConfig):
        run_id = _create_run(config)
        result = runner.invoke(
            main,
            [
                "report",
                run_id,
                "--format",
                "markdown",
                "--runs-root",
                str(config.runs_root),
            ],
        )
        assert result.exit_code == 0
        assert "# Compliance Report" in result.output

    def test_nonexistent_run_exit_code_1(self, runner: CliRunner, tmp_path: Path):
        runs_root = tmp_path / "runs"
        runs_root.mkdir()
        result = runner.invoke(
            main,
            ["report", "no-such-run", "--runs-root", str(runs_root)],
        )
        assert result.exit_code == 1
        assert "not found" in result.output.lower()

    def test_help_shows_commands(self, runner: CliRunner):
        result = runner.invoke(main, ["--help"])
        assert result.exit_code == 0
        assert "list" in result.output
        assert "verify" in result.output
        assert "report" in result.output
