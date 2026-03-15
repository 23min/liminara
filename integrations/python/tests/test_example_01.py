"""Tests for Example 01: Raw Python + Anthropic SDK.

All tests use a stubbed call_llm — no API key required.
"""

import sys
from pathlib import Path
from unittest.mock import patch

import pytest

from liminara import LiminaraConfig
from liminara.event_log import EventLog
from liminara.report import generate_report

# Add the example directory to sys.path so we can import the modules
_EXAMPLE_DIR = Path(__file__).resolve().parent.parent / "examples" / "01_raw_python"
sys.path.insert(0, str(_EXAMPLE_DIR))


STUB_RESPONSE = "This is a stubbed LLM summary of the documents."


@pytest.fixture
def config(tmp_path: Path) -> LiminaraConfig:
    """Config pointing to temp directories."""
    return LiminaraConfig(
        store_root=tmp_path / "store" / "artifacts",
        runs_root=tmp_path / "runs",
    )


@pytest.fixture(autouse=True)
def _stub_llm():
    """Patch call_llm in both pipeline modules to avoid real API calls."""
    with patch("llm.call_llm", return_value=STUB_RESPONSE):
        yield


class TestRawPipeline:
    """Tests for pipeline_raw.py."""

    def test_run_pipeline_returns_string(self):
        import pipeline_raw

        result = pipeline_raw.run_pipeline()
        assert isinstance(result, str)
        assert result == STUB_RESPONSE

    def test_load_documents_returns_list(self):
        import pipeline_raw

        docs = pipeline_raw.load_documents()
        assert isinstance(docs, list)
        assert len(docs) == 3

    def test_no_liminara_files_created(self, tmp_path: Path):
        import pipeline_raw

        liminara_dir = tmp_path / ".liminara"
        assert not liminara_dir.exists()
        pipeline_raw.run_pipeline()
        assert not liminara_dir.exists()


class TestInstrumentedPipeline:
    """Tests for pipeline_instrumented.py."""

    def test_returns_summary_and_run_id(self, config: LiminaraConfig):
        import pipeline_instrumented

        result = pipeline_instrumented.run_pipeline(config=config)
        assert isinstance(result, tuple)
        summary, run_id = result
        assert isinstance(summary, str)
        assert summary == STUB_RESPONSE
        assert isinstance(run_id, str)
        assert run_id.startswith("example-01-")

    def test_events_directory_exists(self, config: LiminaraConfig):
        import pipeline_instrumented

        _, run_id = pipeline_instrumented.run_pipeline(config=config)
        events_path = config.runs_root / run_id / "events.jsonl"
        assert events_path.exists()

    def test_event_count_is_7(self, config: LiminaraConfig):
        import pipeline_instrumented

        _, run_id = pipeline_instrumented.run_pipeline(config=config)
        event_log = EventLog(runs_root=config.runs_root, run_id=run_id)
        events = event_log.read_all()
        # run_started, op_started(load), op_completed(load),
        # op_started(summarize), decision_recorded, op_completed(summarize),
        # run_completed
        assert len(events) == 7

    def test_summarize_op_has_recordable_determinism(self, config: LiminaraConfig):
        import pipeline_instrumented

        _, run_id = pipeline_instrumented.run_pipeline(config=config)
        event_log = EventLog(runs_root=config.runs_root, run_id=run_id)
        events = event_log.read_all()
        summarize_started = next(
            e
            for e in events
            if e["event_type"] == "op_started" and e["payload"]["op_id"] == "summarize"
        )
        assert summarize_started["payload"]["determinism"] == "recordable"

    def test_decision_record_exists(self, config: LiminaraConfig):
        import pipeline_instrumented

        _, run_id = pipeline_instrumented.run_pipeline(config=config)
        decisions_dir = config.runs_root / run_id / "decisions"
        assert decisions_dir.exists()
        decision_files = list(decisions_dir.glob("*.json"))
        assert len(decision_files) == 1

    def test_seal_exists(self, config: LiminaraConfig):
        import pipeline_instrumented

        _, run_id = pipeline_instrumented.run_pipeline(config=config)
        seal_path = config.runs_root / run_id / "seal.json"
        assert seal_path.exists()

    def test_hash_chain_verifies(self, config: LiminaraConfig):
        import pipeline_instrumented

        _, run_id = pipeline_instrumented.run_pipeline(config=config)
        event_log = EventLog(runs_root=config.runs_root, run_id=run_id)
        valid, error = event_log.verify()
        assert valid is True
        assert error is None

    def test_article_12_all_true(self, config: LiminaraConfig):
        import pipeline_instrumented

        _, run_id = pipeline_instrumented.run_pipeline(config=config)
        report = generate_report(config.runs_root, run_id, store_root=config.store_root)
        a12 = report["article_12"]
        assert a12["logging_automatic"] is True
        assert a12["tamper_evident"] is True
        assert a12["inputs_traceable"] is True
        assert a12["outputs_traceable"] is True
        assert a12["decisions_recorded"] is True
        assert a12["logs_retained"] is True


class TestEquivalence:
    """Raw and instrumented pipelines return the same result with the same stubbed LLM."""

    def test_same_output(self, config: LiminaraConfig):
        import pipeline_instrumented
        import pipeline_raw

        raw_result = pipeline_raw.run_pipeline()
        instrumented_result, _ = pipeline_instrumented.run_pipeline(config=config)
        assert raw_result == instrumented_result
