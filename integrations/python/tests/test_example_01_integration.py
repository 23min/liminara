"""Integration tests for Example 01 — requires ANTHROPIC_API_KEY.

Run with: uv run pytest -m integration --run-integration
"""

import sys
from pathlib import Path

import pytest

from liminara import LiminaraConfig
from liminara.report import generate_report

_EXAMPLE_DIR = Path(__file__).resolve().parent.parent / "examples" / "01_raw_python"
sys.path.insert(0, str(_EXAMPLE_DIR))


def _skip_unless_integration(config: pytest.Config) -> None:
    """Skip integration tests unless --run-integration is passed and API key is set."""


@pytest.fixture
def config(tmp_path: Path) -> LiminaraConfig:
    return LiminaraConfig(
        store_root=tmp_path / "store" / "artifacts",
        runs_root=tmp_path / "runs",
    )


pytestmark = pytest.mark.integration


class TestIntegrationRawPipeline:
    def test_returns_nonempty_string(self):
        import pipeline_raw

        result = pipeline_raw.run_pipeline()
        assert isinstance(result, str)
        assert len(result) > 0


class TestIntegrationInstrumentedPipeline:
    def test_returns_nonempty_summary_and_valid_run_id(self, config: LiminaraConfig):
        import pipeline_instrumented

        summary, run_id = pipeline_instrumented.run_pipeline(config=config)
        assert isinstance(summary, str)
        assert len(summary) > 0
        assert run_id.startswith("example-01-")

    def test_report_success_and_article_12(self, config: LiminaraConfig):
        import pipeline_instrumented

        _, run_id = pipeline_instrumented.run_pipeline(config=config)
        report = generate_report(config.runs_root, run_id, store_root=config.store_root)
        assert report["outcome"] == "success"
        for field in report["article_12"].values():
            assert field is True
