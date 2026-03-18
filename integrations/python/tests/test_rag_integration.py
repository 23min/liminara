"""Integration tests for Example 02: LangChain RAG pipeline.

Spec reference: M-LC-02-rag-example.md § Tests

Tests the full stack: setup_index → RAG chain → LiminaraCallbackHandler
→ event log → CLI verify/report. Uses FakeListChatModel to avoid API calls
and real fastembed + LanceDB for the vector index.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest
from click.testing import CliRunner
from langchain_core.language_models import FakeListChatModel

from liminara.cli import main as cli
from liminara.config import LiminaraConfig
from liminara.event_log import EventLog

_EXAMPLE_DIR = Path(__file__).resolve().parent.parent / "examples" / "02_langchain"
sys.path.insert(0, str(_EXAMPLE_DIR))

FAKE_ANSWER = "Article 12 of the EU AI Act requires providers to implement automatic logging."


@pytest.fixture
def config(tmp_path: Path) -> LiminaraConfig:
    return LiminaraConfig(
        store_root=tmp_path / "store" / "artifacts",
        runs_root=tmp_path / "runs",
    )


@pytest.fixture
def fake_llm() -> FakeListChatModel:
    """Fake LLM that returns a canned answer for any query."""
    return FakeListChatModel(responses=[FAKE_ANSWER] * 10)


@pytest.fixture
def index_path(tmp_path: Path) -> Path:
    """Build a LanceDB index from small test docs."""
    import setup_index

    db_path = tmp_path / "lancedb"
    # Use the real project docs (spec requirement)
    docs_dir = Path(__file__).resolve().parent.parent.parent.parent
    stats = setup_index.build_index(db_path=db_path, docs_dir=docs_dir)
    assert stats["doc_count"] == 3
    assert stats["chunk_count"] > 0
    return db_path


class TestIndexSetup:
    """setup_index.py creates a valid LanceDB index."""

    def test_builds_index(self, index_path: Path):
        """Index directory is created with data."""
        assert index_path.exists()

    def test_idempotent_rebuild(self, index_path: Path):
        """Re-running build_index on existing path succeeds."""
        import setup_index

        docs_dir = Path(__file__).resolve().parent.parent.parent.parent
        stats = setup_index.build_index(db_path=index_path, docs_dir=docs_dir)
        assert stats["chunk_count"] > 0

    def test_chunks_are_retrievable(self, index_path: Path):
        """Stored chunks can be retrieved by similarity search."""
        import lancedb

        db = lancedb.connect(index_path)
        table = db.open_table("docs")
        assert table.count_rows() > 0


class TestRAGPipeline:
    """Full pipeline run produces valid Liminara events."""

    def test_produces_valid_events(self, config: LiminaraConfig, index_path: Path, fake_llm):
        """RAG pipeline produces run_started, op/decision events, run_completed."""
        import run as run_module

        answer, run_id, event_count, seal = run_module.ask_question(
            question="What does Article 12 require?",
            db_path=index_path,
            llm=fake_llm,
            config=config,
        )
        assert answer == FAKE_ANSWER
        assert run_id.startswith("langchain-rag-")
        assert event_count > 0
        assert seal.startswith("sha256:")

    def test_hash_chain_valid(self, config: LiminaraConfig, index_path: Path, fake_llm):
        """Hash chain is valid after a RAG pipeline run."""
        import run as run_module

        _, run_id, _, _ = run_module.ask_question(
            question="What is Liminara?",
            db_path=index_path,
            llm=fake_llm,
            config=config,
        )
        event_log = EventLog(runs_root=config.runs_root, run_id=run_id)
        valid, error = event_log.verify()
        assert valid, f"Hash chain broken: {error}"

    def test_events_include_llm_op(self, config: LiminaraConfig, index_path: Path, fake_llm):
        """Events include an LLM op_started with model info."""
        import run as run_module

        _, run_id, _, _ = run_module.ask_question(
            question="What is an artifact?",
            db_path=index_path,
            llm=fake_llm,
            config=config,
        )
        event_log = EventLog(runs_root=config.runs_root, run_id=run_id)
        events = event_log.read_all()
        op_started = [e for e in events if e["event_type"] == "op_started"]
        llm_ops = [e for e in op_started if e["payload"]["op_id"] == "llm"]
        assert len(llm_ops) >= 1

    def test_decision_recorded(self, config: LiminaraConfig, index_path: Path, fake_llm):
        """A decision_recorded event is emitted for the LLM call."""
        import run as run_module

        _, run_id, _, _ = run_module.ask_question(
            question="What is a decision?",
            db_path=index_path,
            llm=fake_llm,
            config=config,
        )
        event_log = EventLog(runs_root=config.runs_root, run_id=run_id)
        events = event_log.read_all()
        decisions = [e for e in events if e["event_type"] == "decision_recorded"]
        assert len(decisions) >= 1
        assert decisions[0]["payload"]["decision_type"] == "llm_response"


class TestCLIIntegration:
    """CLI commands work on LangChain-produced runs."""

    def _run_pipeline(self, config, index_path, fake_llm) -> str:
        """Helper: run one question, return run_id."""
        import run as run_module

        _, run_id, _, _ = run_module.ask_question(
            question="What does Article 12 require?",
            db_path=index_path,
            llm=fake_llm,
            config=config,
        )
        return run_id

    def test_verify_passes(self, config: LiminaraConfig, index_path: Path, fake_llm):
        """liminara verify exits 0 for a valid LangChain run."""
        run_id = self._run_pipeline(config, index_path, fake_llm)
        runner = CliRunner()
        result = runner.invoke(cli, ["verify", run_id, "--runs-root", str(config.runs_root)])
        assert result.exit_code == 0

    def test_report_json(self, config: LiminaraConfig, index_path: Path, fake_llm):
        """liminara report --format json produces valid JSON."""
        run_id = self._run_pipeline(config, index_path, fake_llm)
        runner = CliRunner()
        result = runner.invoke(
            cli,
            ["report", run_id, "--format", "json", "--runs-root", str(config.runs_root)],
        )
        assert result.exit_code == 0
        report = json.loads(result.output)
        assert report["run_id"] == run_id
        assert report["hash_chain"]["verified"] is True

    def test_report_human(self, config: LiminaraConfig, index_path: Path, fake_llm):
        """liminara report --format human produces readable output."""
        run_id = self._run_pipeline(config, index_path, fake_llm)
        runner = CliRunner()
        result = runner.invoke(
            cli,
            [
                "report",
                run_id,
                "--format",
                "human",
                "--runs-root",
                str(config.runs_root),
                "--store-root",
                str(config.store_root),
            ],
        )
        assert result.exit_code == 0
        assert "Hash chain" in result.output

    def test_list_shows_run(self, config: LiminaraConfig, index_path: Path, fake_llm):
        """liminara list includes the LangChain run."""
        run_id = self._run_pipeline(config, index_path, fake_llm)
        runner = CliRunner()
        result = runner.invoke(cli, ["list", "--runs-root", str(config.runs_root)])
        assert result.exit_code == 0
        assert run_id in result.output


class TestTamperDetection:
    """Tampering with events is detected."""

    def test_verify_fails_on_tampered_event(
        self, config: LiminaraConfig, index_path: Path, fake_llm
    ):
        """Modifying an event causes verify to fail."""
        import run as run_module

        _, run_id, _, _ = run_module.ask_question(
            question="What is tampering?",
            db_path=index_path,
            llm=fake_llm,
            config=config,
        )

        # Tamper with an event
        events_path = config.runs_root / run_id / "events.jsonl"
        lines = events_path.read_text().splitlines()
        event = json.loads(lines[1])  # tamper with second event
        event["payload"]["op_id"] = "tampered"
        lines[1] = json.dumps(event)
        events_path.write_text("\n".join(lines) + "\n")

        # Verify should fail
        runner = CliRunner()
        result = runner.invoke(cli, ["verify", run_id, "--runs-root", str(config.runs_root)])
        assert result.exit_code == 1


class TestMultipleRuns:
    """Multiple questions produce independent valid runs."""

    def test_three_independent_runs(self, config: LiminaraConfig, index_path: Path, fake_llm):
        """Three questions produce three runs, each with valid hash chain."""
        import run as run_module

        run_ids = []
        for q in ["What is Article 12?", "What is an artifact?", "What is a run?"]:
            _, run_id, _, _ = run_module.ask_question(
                question=q,
                db_path=index_path,
                llm=fake_llm,
                config=config,
            )
            run_ids.append(run_id)

        assert len(set(run_ids)) == 3  # all unique

        for run_id in run_ids:
            event_log = EventLog(runs_root=config.runs_root, run_id=run_id)
            valid, error = event_log.verify()
            assert valid, f"Run {run_id} hash chain broken: {error}"
