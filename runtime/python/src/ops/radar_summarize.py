"""Radar summarize op — per-cluster Haiku summaries (recordable)."""

import json
import os

try:
    import anthropic
except ImportError:
    anthropic = None


PROMPT_TEMPLATE = """You are summarizing a cluster of related news items \
for a daily intelligence briefing.

Cluster topic: {label}

Items in this cluster:
{items_text}

Write 2-3 paragraphs summarizing:
1. What happened / what's new
2. Why it matters
3. Any conflicting viewpoints or nuances

Also provide 2-3 key takeaways as bullet points.

Respond in JSON only:
{{"summary": "...", "key_takeaways": ["...", "..."]}}"""


def execute(inputs):
    clusters = json.loads(inputs.get("clusters", "[]"))

    if not clusters:
        return {
            "outputs": {"summaries": json.dumps([]), "decisions": json.dumps([])},
            "decisions": [],
        }

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")

    if not api_key or anthropic is None:
        return _placeholder_summaries(clusters, api_key)

    client = anthropic.Anthropic(api_key=api_key)
    summaries = []
    decisions = []
    warnings = []

    for cluster in clusters:
        items_text = _format_items(cluster["items"])
        prompt = PROMPT_TEMPLATE.format(
            label=cluster.get("label", "Unknown"),
            items_text=items_text,
        )
        llm_failed = False

        try:
            response = client.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=500,
                messages=[{"role": "user", "content": prompt}],
            )
            response_text = response.content[0].text
            data = json.loads(response_text)
        except Exception as e:
            data = {
                "summary": f"Summary unavailable for cluster: {cluster.get('label', 'Unknown')}",
                "key_takeaways": ["Summary generation failed; see warning details"],
            }
            warnings.append(_llm_error_warning(str(e)))
            llm_failed = True

        summary = {
            "cluster_id": cluster["cluster_id"],
            "summary": data.get("summary", ""),
            "key_takeaways": data.get("key_takeaways", []),
        }
        summaries.append(summary)

        if not llm_failed:
            decision = {
                "decision_type": "cluster_summary",
                "cluster_id": cluster["cluster_id"],
                "cluster_label": cluster.get("label", ""),
                "item_count": len(cluster["items"]),
                "summary": data.get("summary", ""),
                "rationale": _decision_rationale(data),
            }
            decisions.append(decision)

    result = {
        "outputs": {
            "summaries": json.dumps(summaries),
            "decisions": json.dumps(decisions),
        },
        "decisions": decisions,
    }

    if warnings:
        result["warnings"] = warnings

    return result


def _decision_rationale(data):
    return "haiku summary"


def _placeholder_summaries(clusters, api_key):
    """Generate placeholder summaries when no API key or SDK available."""
    if not api_key:
        cause = "ANTHROPIC_API_KEY is not configured"
        remediation = "Configure ANTHROPIC_API_KEY to enable live summaries"
    else:
        cause = "anthropic SDK is not installed in the Radar Python environment"
        remediation = "Install the anthropic package in the runtime Python environment"
    summaries = []

    for cluster in clusters:
        titles = [item.get("title", "") for item in cluster["items"]]
        summary = {
            "cluster_id": cluster["cluster_id"],
            "summary": (
                f"Cluster '{cluster.get('label', 'Unknown')}' contains "
                f"{len(cluster['items'])} item(s): {'; '.join(titles[:5])}."
            ),
            "key_takeaways": [f"Contains {len(cluster['items'])} related items"],
        }
        summaries.append(summary)

    return {
        "outputs": {
            "summaries": json.dumps(summaries),
            "decisions": json.dumps([]),
        },
        "decisions": [],
        "warnings": [
            {
                "code": "radar_summarize_placeholder",
                "severity": "degraded",
                "summary": "Using placeholder summaries because Anthropic access is unavailable",
                "cause": cause,
                "remediation": remediation,
                "affected_outputs": ["summaries"],
            }
        ],
    }


def _llm_error_warning(cause):
    return {
        "code": "radar_summarize_llm_error",
        "severity": "degraded",
        "summary": "Fell back to a placeholder summary after an LLM error",
        "cause": cause,
        "remediation": "Check Anthropic availability and credentials; replay will preserve this degraded summary",
        "affected_outputs": ["summaries"],
    }


def _format_items(items):
    parts = []
    for item in items[:10]:  # Cap at 10 items per cluster prompt
        title = item.get("title", "Untitled")
        source = item.get("source_id", "unknown")
        text = item.get("clean_text", "")[:500]
        parts.append(f"- {title} (source: {source})\n  {text}")
    return "\n\n".join(parts)
