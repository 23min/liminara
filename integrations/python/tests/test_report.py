"""Tests for the Article 12 compliance report generator."""

import json
from pathlib import Path

import pytest

from liminara import LiminaraConfig, decision, op, run
from liminara.report import format_human, format_json, format_markdown, generate_report


@pytest.fixture
def config(tmp_path: Path) -> LiminaraConfig:
    """Config pointing to temp directories."""
    return LiminaraConfig(
        store_root=tmp_path / "store" / "artifacts",
        runs_root=tmp_path / "runs",
    )


def _create_successful_run(config: LiminaraConfig) -> str:
    """Create a complete run with one pure op and one recordable op+decision.

    Returns the run_id.
    """

    @op(name="load", version="1.0.0", determinism="pure")
    def load(data: str) -> str:
        return data.upper()

    @op(name="summarize", version="2.0.0", determinism="recordable")
    @decision(decision_type="llm_response")
    def summarize(text: str) -> str:
        return f"Summary of: {text}"

    with run("testpack", "0.1.0", config=config) as r:
        result = load("hello")
        summarize(result)

    return r.run_id


def _create_failed_run(config: LiminaraConfig) -> str:
    """Create a run that fails mid-execution. Returns run_id."""

    @op(name="boom", version="1.0.0", determinism="pure")
    def boom() -> str:
        raise RuntimeError("intentional failure")

    try:
        with run("failpack", "0.1.0", config=config) as r:
            boom()
    except RuntimeError:
        pass

    return r.run_id


class TestGenerateReport:
    """Tests for generate_report()."""

    def test_returns_dict_with_all_top_level_keys(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id, store_root=config.store_root)

        expected_keys = {
            "report_version",
            "generated_at",
            "run_id",
            "pack_id",
            "pack_version",
            "started_at",
            "completed_at",
            "outcome",
            "event_count",
            "operations",
            "artifacts",
            "decisions",
            "hash_chain",
            "article_12",
        }
        assert set(report.keys()) == expected_keys

    def test_report_version_is_1_0(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)
        assert report["report_version"] == "1.0"

    def test_run_metadata_matches(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)

        assert report["run_id"] == run_id
        assert report["pack_id"] == "testpack"
        assert report["pack_version"] == "0.1.0"

    def test_timestamps_are_iso8601(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)

        # started_at and completed_at should be ISO 8601 with millisecond precision
        assert "T" in report["started_at"]
        assert report["started_at"].endswith("Z")
        assert "T" in report["completed_at"]
        assert report["completed_at"].endswith("Z")
        # generated_at should also be ISO 8601
        assert "T" in report["generated_at"]
        assert report["generated_at"].endswith("Z")

    def test_outcome_success(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)
        assert report["outcome"] == "success"

    def test_outcome_failed(self, config: LiminaraConfig):
        run_id = _create_failed_run(config)
        report = generate_report(config.runs_root, run_id)
        assert report["outcome"] == "failed"

    def test_event_count(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)
        # 7 events: run_started, 2x(op_started+op_completed), decision_recorded, run_completed
        assert report["event_count"] == 7

    def test_operations_list(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id, store_root=config.store_root)

        ops = report["operations"]
        assert len(ops) == 2

        # First op: load (pure, no decision)
        assert ops[0]["op_id"] == "load"
        assert ops[0]["op_version"] == "1.0.0"
        assert ops[0]["determinism"] == "pure"
        assert ops[0]["cache_hit"] is False
        assert isinstance(ops[0]["duration_ms"], float)
        assert ops[0]["has_decision"] is False
        assert len(ops[0]["input_hashes"]) == 1
        assert len(ops[0]["output_hashes"]) == 1

        # Second op: summarize (recordable, has decision)
        assert ops[1]["op_id"] == "summarize"
        assert ops[1]["determinism"] == "recordable"
        assert ops[1]["has_decision"] is True

    def test_operations_include_node_id(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)

        ops = report["operations"]
        assert ops[0]["node_id"] == "load-001"
        assert ops[1]["node_id"] == "summarize-002"

    def test_decisions_list(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)

        decisions = report["decisions"]
        assert len(decisions) == 1
        assert decisions[0]["node_id"] == "summarize-002"
        assert decisions[0]["decision_type"] == "llm_response"
        assert decisions[0]["decision_hash"].startswith("sha256:")

    def test_hash_chain_verified(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)

        assert report["hash_chain"]["verified"] is True
        assert report["hash_chain"]["error"] is None

    def test_hash_chain_run_seal(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)

        assert report["hash_chain"]["run_seal"] is not None
        assert report["hash_chain"]["run_seal"].startswith("sha256:")

    def test_hash_chain_no_seal_on_failed_run(self, config: LiminaraConfig):
        run_id = _create_failed_run(config)
        report = generate_report(config.runs_root, run_id)

        assert report["hash_chain"]["run_seal"] is None

    def test_article_12_all_true_for_complete_run(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)

        a12 = report["article_12"]
        assert a12["logging_automatic"] is True
        assert a12["tamper_evident"] is True
        assert a12["inputs_traceable"] is True
        assert a12["outputs_traceable"] is True
        assert a12["decisions_recorded"] is True
        assert a12["logs_retained"] is True

    def test_article_12_tamper_evident_false_on_tampered_run(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)

        # Tamper with the event log
        events_path = config.runs_root / run_id / "events.jsonl"
        lines = events_path.read_text().splitlines()
        # Modify the second event's payload
        event = json.loads(lines[1])
        event["payload"]["op_id"] = "TAMPERED"
        lines[1] = json.dumps(event)
        events_path.write_text("\n".join(lines) + "\n")

        report = generate_report(config.runs_root, run_id)
        assert report["article_12"]["tamper_evident"] is False

    def test_artifacts_list(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id, store_root=config.store_root)

        artifacts = report["artifacts"]
        assert len(artifacts) > 0
        for a in artifacts:
            assert a["artifact_hash"].startswith("sha256:")
            assert isinstance(a["size_bytes"], int)

    def test_artifacts_size_null_without_store_root(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id, store_root=None)

        for a in report["artifacts"]:
            assert a["size_bytes"] is None

    def test_raises_file_not_found_for_missing_run(self, config: LiminaraConfig):
        with pytest.raises(FileNotFoundError):
            generate_report(config.runs_root, "nonexistent-run-id")


class TestFormatJson:
    """Tests for format_json()."""

    def test_returns_valid_json(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)
        result = format_json(report)

        parsed = json.loads(result)
        assert parsed["report_version"] == "1.0"
        assert "article_12" in parsed


class TestFormatHuman:
    """Tests for format_human()."""

    def test_contains_section_headers_and_checkmarks(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)
        result = format_human(report)

        assert "Run:" in result
        assert "Pack:" in result
        assert "Operations:" in result
        assert "Article 12 Compliance:" in result
        assert "\u2713" in result  # checkmark


class TestFormatMarkdown:
    """Tests for format_markdown()."""

    def test_contains_markdown_headers_and_table(self, config: LiminaraConfig):
        run_id = _create_successful_run(config)
        report = generate_report(config.runs_root, run_id)
        result = format_markdown(report)

        assert "# Compliance Report:" in result
        assert "## Operations" in result
        assert "| Op " in result
        assert "- [x]" in result
