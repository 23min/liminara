"""Tests for Radar LLM dedup check — mocked, no real API calls."""

import json
import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from ops.radar_llm_dedup import execute as llm_dedup_execute


def make_ambiguous_item(item_id="a1", title="News Story", match_title="Similar Story", sim=0.85):
    return {
        "id": item_id,
        "title": title,
        "clean_text": "Some article content here",
        "url": f"https://example.com/{item_id}",
        "source_id": "src_1",
        "_match_title": match_title,
        "_match_url": "https://other.com/existing",
        "_similarity": sim,
    }


class TestLlmDedupCheck:
    def test_empty_items_returns_immediately(self):
        result = llm_dedup_execute({"items": json.dumps([])})

        items = json.loads(result["outputs"]["items"])
        decisions = json.loads(result["outputs"]["decisions"])
        assert items == []
        assert decisions == []

    def test_no_api_key_defaults_to_keep(self):
        """Without ANTHROPIC_API_KEY, all items are kept (safe default)."""
        # Ensure no key is set
        env = os.environ.copy()
        os.environ.pop("ANTHROPIC_API_KEY", None)

        try:
            items = [make_ambiguous_item("a1"), make_ambiguous_item("a2")]
            result = llm_dedup_execute({"items": json.dumps(items)})

            kept = json.loads(result["outputs"]["items"])
            decisions = json.loads(result["outputs"]["decisions"])

            assert len(kept) == 2  # all kept
            assert decisions == []
            assert result["decisions"] == []
            assert result["warnings"] == [
                {
                    "code": "radar_llm_dedup_safe_default",
                    "severity": "degraded",
                    "summary": "Keeping ambiguous items because LLM dedup is unavailable",
                    "cause": "ANTHROPIC_API_KEY is not configured",
                    "remediation": "Configure ANTHROPIC_API_KEY to enable LLM dedup resolution",
                    "affected_outputs": ["items"],
                }
            ]
        finally:
            os.environ.update(env)

    @patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test-key"})
    @patch("ops.radar_llm_dedup.anthropic", None)
    def test_missing_sdk_defaults_to_keep_with_warning(self):
        items = [make_ambiguous_item("a1")]
        result = llm_dedup_execute({"items": json.dumps(items)})

        kept = json.loads(result["outputs"]["items"])
        assert len(kept) == 1
        assert result["decisions"] == []
        assert result["warnings"] == [
            {
                "code": "radar_llm_dedup_safe_default",
                "severity": "degraded",
                "summary": "Keeping ambiguous items because LLM dedup is unavailable",
                "cause": "anthropic SDK is not installed in the Radar Python environment",
                "remediation": "Install the anthropic package in the runtime Python environment",
                "affected_outputs": ["items"],
            }
        ]

    @patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test-key"})
    @patch("ops.radar_llm_dedup.anthropic")
    def test_same_verdict_filters_item(self, mock_anthropic):
        mock_response = MagicMock()
        mock_response.content = [MagicMock(text='{"verdict": "same", "rationale": "Same event"}')]
        mock_anthropic.Anthropic.return_value.messages.create.return_value = mock_response

        items = [make_ambiguous_item("a1")]
        result = llm_dedup_execute({"items": json.dumps(items)})

        kept = json.loads(result["outputs"]["items"])
        decisions = json.loads(result["outputs"]["decisions"])

        assert len(kept) == 0  # filtered out
        assert len(decisions) == 1
        assert decisions[0]["verdict"] == "same"

    @patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test-key"})
    @patch("ops.radar_llm_dedup.anthropic")
    def test_different_verdict_keeps_item(self, mock_anthropic):
        mock_response = MagicMock()
        mock_response.content = [MagicMock(text='{"verdict": "different", "rationale": "Different angle"}')]
        mock_anthropic.Anthropic.return_value.messages.create.return_value = mock_response

        items = [make_ambiguous_item("a1")]
        result = llm_dedup_execute({"items": json.dumps(items)})

        kept = json.loads(result["outputs"]["items"])
        assert len(kept) == 1

    @patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test-key"})
    @patch("ops.radar_llm_dedup.anthropic")
    def test_decisions_recorded_for_replay(self, mock_anthropic):
        mock_response = MagicMock()
        mock_response.content = [MagicMock(text='{"verdict": "same", "rationale": "Duplicate"}')]
        mock_anthropic.Anthropic.return_value.messages.create.return_value = mock_response

        items = [make_ambiguous_item("a1", title="Breaking News", match_title="Breaking News Update")]
        result = llm_dedup_execute({"items": json.dumps(items)})

        assert "decisions" in result
        assert len(result["decisions"]) == 1
        d = result["decisions"][0]
        assert d["decision_type"] == "llm_dedup_check"
        assert d["item_id"] == "a1"
        assert d["verdict"] == "same"

    @patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test-key"})
    @patch("ops.radar_llm_dedup.anthropic")
    def test_api_error_defaults_to_keep(self, mock_anthropic):
        mock_anthropic.Anthropic.return_value.messages.create.side_effect = Exception("API timeout")

        items = [make_ambiguous_item("a1")]
        result = llm_dedup_execute({"items": json.dumps(items)})

        kept = json.loads(result["outputs"]["items"])
        decisions = json.loads(result["outputs"]["decisions"])

        assert len(kept) == 1  # kept on error (safe default)
        assert decisions == []
        assert result["decisions"] == []
        assert result["warnings"] == [
            {
                "code": "radar_llm_dedup_llm_error",
                "severity": "degraded",
                "summary": "Keeping ambiguous items after an LLM dedup error",
                "cause": "API timeout",
                "remediation": "Check Anthropic availability and credentials; replay will preserve this degraded keep decision",
                "affected_outputs": ["items"],
            }
        ]

    def test_dict_shaped_input_extracts_ambiguous_items(self):
        """Input from dedup is a dict with new/ambiguous/duplicate lists."""
        dedup_result = {
            "new_items": [{"id": "n1", "title": "New"}],
            "ambiguous_items": [make_ambiguous_item("a1")],
            "duplicate_items": [{"id": "d1", "title": "Dup"}],
        }
        env = os.environ.copy()
        os.environ.pop("ANTHROPIC_API_KEY", None)

        try:
            result = llm_dedup_execute({"items": json.dumps(dedup_result)})

            kept = json.loads(result["outputs"]["items"])
            decisions = json.loads(result["outputs"]["decisions"])

            # Should only process the 1 ambiguous item, not all 3
            assert len(kept) == 1
            assert kept[0]["id"] == "a1"
            assert decisions == []
            assert result["warnings"][0]["code"] == "radar_llm_dedup_safe_default"
        finally:
            os.environ.update(env)
