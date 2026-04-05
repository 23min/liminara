"""Radar LLM dedup check — resolves ambiguous items via Haiku."""

import json
import os

try:
    import anthropic
except ImportError:
    anthropic = None


PROMPT_TEMPLATE = """Compare these two news items. Are they about the same story/event from different sources, or genuinely different stories?

Item A (new):
Title: {new_title}
URL: {new_url}
Text: {new_text}

Item B (existing in history):
Title: {match_title}
URL: {match_url}

Respond with JSON only:
{{"verdict": "same" or "different", "rationale": "one sentence explanation"}}"""


def execute(inputs):
    items_raw = json.loads(inputs.get("items", "[]"))
    # Input may be the full dedup result dict or a direct list of items
    if isinstance(items_raw, dict):
        ambiguous_items = items_raw.get("ambiguous_items", [])
    else:
        ambiguous_items = items_raw

    if not ambiguous_items:
        return {
            "outputs": {"items": json.dumps([]), "decisions": json.dumps([])},
            "decisions": [],
        }

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        return {
            "outputs": {
                "items": json.dumps(ambiguous_items),
                "decisions": json.dumps([]),
            },
            "decisions": [],
            "warnings": [
                _safe_default_warning(
                    "ANTHROPIC_API_KEY is not configured",
                    "Configure ANTHROPIC_API_KEY to enable LLM dedup resolution",
                )
            ],
        }

    if anthropic is None:
        return {
            "outputs": {"items": json.dumps(ambiguous_items), "decisions": json.dumps([])},
            "decisions": [],
            "warnings": [
                _safe_default_warning(
                    "anthropic SDK is not installed in the Radar Python environment",
                    "Install the anthropic package in the runtime Python environment",
                )
            ],
        }
    client = anthropic.Anthropic(api_key=api_key)

    kept_items = []
    decisions = []
    warnings = []

    for item in ambiguous_items:
        llm_failed = False
        prompt = PROMPT_TEMPLATE.format(
            new_title=item.get("title", ""),
            new_url=item.get("url", ""),
            new_text=item.get("clean_text", "")[:500],
            match_title=item.get("_match_title", ""),
            match_url=item.get("_match_url", ""),
        )

        try:
            response = client.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=200,
                messages=[{"role": "user", "content": prompt}],
            )
            response_text = response.content[0].text
            verdict_data = json.loads(response_text)
        except Exception as e:
            verdict_data = {"verdict": "different", "rationale": "safe default keep"}
            warnings.append(_llm_error_warning(str(e)))
            llm_failed = True

        if not llm_failed:
            decision = {
                "decision_type": "llm_dedup_check",
                "item_id": item["id"],
                "item_title": item.get("title", ""),
                "match_title": item.get("_match_title", ""),
                "similarity": item.get("_similarity", 0),
                "verdict": verdict_data.get("verdict", "different"),
                "rationale": verdict_data.get("rationale", ""),
            }
            decisions.append(decision)

        if verdict_data.get("verdict") == "different":
            kept_items.append(item)

    result = {
        "outputs": {
            "items": json.dumps(kept_items),
            "decisions": json.dumps(decisions),
        },
        "decisions": decisions,
    }

    if warnings:
        result["warnings"] = warnings

    return result


def _safe_default_warning(cause, remediation):
    return {
        "code": "radar_llm_dedup_safe_default",
        "severity": "degraded",
        "summary": "Keeping ambiguous items because LLM dedup is unavailable",
        "cause": cause,
        "remediation": remediation,
        "affected_outputs": ["items"],
    }


def _llm_error_warning(cause):
    return {
        "code": "radar_llm_dedup_llm_error",
        "severity": "degraded",
        "summary": "Keeping ambiguous items after an LLM dedup error",
        "cause": cause,
        "remediation": "Check Anthropic availability and credentials; replay will preserve this degraded keep decision",
        "affected_outputs": ["items"],
    }
