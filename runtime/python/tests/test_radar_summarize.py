"""Tests for Radar summarize op — per-cluster Haiku summaries."""

import json
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from ops.radar_summarize import execute as summarize_execute


def _make_cluster(cluster_id, items, label="Test Cluster"):
    return {
        "cluster_id": cluster_id,
        "label": label,
        "items": items,
        "centroid": [0.0] * 32,
    }


def _make_item(item_id, title="Item", source_id="s1"):
    return {
        "id": item_id,
        "title": title,
        "clean_text": f"Full text content for {title}. This is a longer description.",
        "url": f"https://example.com/{item_id}",
        "source_id": source_id,
    }


class TestSummarize:
    def test_empty_clusters(self):
        """Empty cluster list → no summaries, no decisions."""
        result = summarize_execute({"clusters": json.dumps([])})

        summaries = json.loads(result["outputs"]["summaries"])
        decisions = json.loads(result["outputs"]["decisions"])
        assert summaries == []
        assert decisions == []
        assert result["decisions"] == []

    def test_no_api_key_returns_placeholder(self):
        """Without ANTHROPIC_API_KEY, returns placeholder summaries."""
        clusters = [
            _make_cluster("c0", [_make_item("a1", "Test Item")]),
        ]

        with patch.dict("os.environ", {}, clear=True):
            result = summarize_execute({"clusters": json.dumps(clusters)})

        summaries = json.loads(result["outputs"]["summaries"])
        assert len(summaries) == 1
        assert summaries[0]["cluster_id"] == "c0"
        assert "summary" in summaries[0]
        assert "key_takeaways" in summaries[0]
        assert summaries[0]["degraded"] is True
        assert summaries[0]["degradation_code"] == "radar_summarize_placeholder"
        assert summaries[0]["degradation_note"] == (
            "Using placeholder summaries because Anthropic access is unavailable"
        )

        decisions = result["decisions"]
        assert decisions == []
        assert json.loads(result["outputs"]["decisions"]) == []

        assert result["warnings"] == [
            {
                "code": "radar_summarize_placeholder",
                "severity": "degraded",
                "summary": "Using placeholder summaries because Anthropic access is unavailable",
                "cause": "ANTHROPIC_API_KEY is not configured",
                "remediation": "Configure ANTHROPIC_API_KEY to enable live summaries",
                "affected_outputs": ["summaries"],
            }
        ]

    @patch("ops.radar_summarize.anthropic", None)
    def test_missing_sdk_returns_placeholder_warning(self):
        clusters = [_make_cluster("c0", [_make_item("a1", "Test Item")])]

        with patch.dict("os.environ", {"ANTHROPIC_API_KEY": "test-key"}, clear=True):
            result = summarize_execute({"clusters": json.dumps(clusters)})

        summaries = json.loads(result["outputs"]["summaries"])
        assert len(summaries) == 1
        assert summaries[0]["degraded"] is True
        assert summaries[0]["degradation_code"] == "radar_summarize_placeholder"
        assert summaries[0]["degradation_note"] == (
            "Using placeholder summaries because Anthropic access is unavailable"
        )

        assert result["decisions"] == []
        assert result["warnings"] == [
            {
                "code": "radar_summarize_placeholder",
                "severity": "degraded",
                "summary": "Using placeholder summaries because Anthropic access is unavailable",
                "cause": "anthropic SDK is not installed in the Radar Python environment",
                "remediation": "Install the anthropic package in the runtime Python environment",
                "affected_outputs": ["summaries"],
            }
        ]

    @patch("ops.radar_summarize.anthropic")
    def test_haiku_called_per_cluster(self, mock_anthropic):
        """3 clusters → 3 LLM calls, 3 decisions."""
        mock_client = MagicMock()
        mock_anthropic.Anthropic.return_value = mock_client

        mock_response = MagicMock()
        mock_response.content = [
            MagicMock(text='{"summary": "Test summary.", "key_takeaways": ["Point 1"]}')
        ]
        mock_client.messages.create.return_value = mock_response

        clusters = [
            _make_cluster("c0", [_make_item("a1", "Item A")]),
            _make_cluster("c1", [_make_item("b1", "Item B")]),
            _make_cluster("c2", [_make_item("c1", "Item C")]),
        ]

        with patch.dict("os.environ", {"ANTHROPIC_API_KEY": "test-key"}):
            result = summarize_execute({"clusters": json.dumps(clusters)})

        assert mock_client.messages.create.call_count == 3

        summaries = json.loads(result["outputs"]["summaries"])
        assert len(summaries) == 3

        decisions = result["decisions"]
        assert len(decisions) == 3

    @patch("ops.radar_summarize.anthropic")
    def test_summary_structure(self, mock_anthropic):
        """Summary has cluster_id, summary, key_takeaways, and explicit non-degraded fields."""
        mock_client = MagicMock()
        mock_anthropic.Anthropic.return_value = mock_client

        mock_response = MagicMock()
        mock_response.content = [
            MagicMock(text='{"summary": "A good summary.", "key_takeaways": ["First", "Second"]}')
        ]
        mock_client.messages.create.return_value = mock_response

        clusters = [_make_cluster("c0", [_make_item("a1", "Item")])]

        with patch.dict("os.environ", {"ANTHROPIC_API_KEY": "test-key"}):
            result = summarize_execute({"clusters": json.dumps(clusters)})

        summaries = json.loads(result["outputs"]["summaries"])
        s = summaries[0]
        assert s["cluster_id"] == "c0"
        assert s["summary"] == "A good summary."
        assert s["key_takeaways"] == ["First", "Second"]
        # Non-degraded success emits explicit false/None — same "no duct tape"
        # principle as M-WARN-01.
        assert s["degraded"] is False
        assert s["degradation_code"] is None
        assert s["degradation_note"] is None

    @patch("ops.radar_summarize.anthropic")
    def test_decision_recording(self, mock_anthropic):
        """Each summary call produces a recorded decision."""
        mock_client = MagicMock()
        mock_anthropic.Anthropic.return_value = mock_client

        mock_response = MagicMock()
        mock_response.content = [MagicMock(text='{"summary": "Sum.", "key_takeaways": ["T"]}')]
        mock_client.messages.create.return_value = mock_response

        clusters = [_make_cluster("c0", [_make_item("a1", "Item")], label="AI News")]

        with patch.dict("os.environ", {"ANTHROPIC_API_KEY": "test-key"}):
            result = summarize_execute({"clusters": json.dumps(clusters)})

        decisions = result["decisions"]
        d = decisions[0]
        assert d["decision_type"] == "cluster_summary"
        assert d["cluster_id"] == "c0"
        assert d["cluster_label"] == "AI News"
        assert "summary" in d

    @patch("ops.radar_summarize.anthropic")
    def test_llm_error_returns_fallback(self, mock_anthropic):
        """LLM error → fallback summary, per-summary degraded fields, no crash."""
        mock_client = MagicMock()
        mock_anthropic.Anthropic.return_value = mock_client
        mock_client.messages.create.side_effect = Exception("API error")

        clusters = [_make_cluster("c0", [_make_item("a1", "Item")])]

        with patch.dict("os.environ", {"ANTHROPIC_API_KEY": "test-key"}):
            result = summarize_execute({"clusters": json.dumps(clusters)})

        summaries = json.loads(result["outputs"]["summaries"])
        assert len(summaries) == 1
        assert "summary" in summaries[0]
        assert summaries[0]["degraded"] is True
        assert summaries[0]["degradation_code"] == "radar_summarize_llm_error"
        assert summaries[0]["degradation_note"] == (
            "Fell back to a placeholder summary after an LLM error"
        )

        decisions = result["decisions"]
        assert decisions == []
        assert json.loads(result["outputs"]["decisions"]) == []
        assert result["warnings"] == [
            {
                "code": "radar_summarize_llm_error",
                "severity": "degraded",
                "summary": "Fell back to a placeholder summary after an LLM error",
                "cause": "API error",
                "remediation": (
                    "Check Anthropic availability and credentials; "
                    "replay will preserve this degraded summary"
                ),
                "affected_outputs": ["summaries"],
            }
        ]

    @patch("ops.radar_summarize.anthropic")
    def test_mixed_llm_success_and_error_per_summary_flags(self, mock_anthropic):
        """Mixed clusters: one success and one LLM error → per-summary flags match each."""
        mock_client = MagicMock()
        mock_anthropic.Anthropic.return_value = mock_client

        success_response = MagicMock()
        success_response.content = [
            MagicMock(text='{"summary": "Clean summary.", "key_takeaways": ["OK"]}')
        ]
        mock_client.messages.create.side_effect = [
            success_response,
            Exception("boom"),
        ]

        clusters = [
            _make_cluster("c0", [_make_item("a1", "Alpha")]),
            _make_cluster("c1", [_make_item("b1", "Beta")]),
        ]

        with patch.dict("os.environ", {"ANTHROPIC_API_KEY": "test-key"}):
            result = summarize_execute({"clusters": json.dumps(clusters)})

        summaries = json.loads(result["outputs"]["summaries"])
        assert len(summaries) == 2

        # First cluster succeeded — explicit non-degraded.
        assert summaries[0]["cluster_id"] == "c0"
        assert summaries[0]["degraded"] is False
        assert summaries[0]["degradation_code"] is None
        assert summaries[0]["degradation_note"] is None

        # Second cluster hit an LLM error — per-summary flags set.
        assert summaries[1]["cluster_id"] == "c1"
        assert summaries[1]["degraded"] is True
        assert summaries[1]["degradation_code"] == "radar_summarize_llm_error"
        assert summaries[1]["degradation_note"] == (
            "Fell back to a placeholder summary after an LLM error"
        )

        # Only the failing cluster records a warning; the successful one records a decision.
        assert len(result["decisions"]) == 1
        assert result["decisions"][0]["cluster_id"] == "c0"
        assert len(result["warnings"]) == 1
        assert result["warnings"][0]["code"] == "radar_summarize_llm_error"
