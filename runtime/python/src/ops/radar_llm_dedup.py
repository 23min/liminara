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
    ambiguous_items = json.loads(inputs.get("items", "[]"))

    if not ambiguous_items:
        return {
            "outputs": {"items": json.dumps([]), "decisions": json.dumps([])},
            "decisions": [],
        }

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        # No API key — treat all ambiguous as "keep" (safe default)
        decisions = [
            {"item_id": item["id"], "verdict": "different", "rationale": "no API key, defaulting to keep"}
            for item in ambiguous_items
        ]
        return {
            "outputs": {
                "items": json.dumps(ambiguous_items),
                "decisions": json.dumps(decisions),
            },
            "decisions": decisions,
        }

    if anthropic is None:
        decisions = [
            {"item_id": item["id"], "verdict": "different", "rationale": "anthropic SDK not installed"}
            for item in ambiguous_items
        ]
        return {
            "outputs": {"items": json.dumps(ambiguous_items), "decisions": json.dumps(decisions)},
            "decisions": decisions,
        }
    client = anthropic.Anthropic(api_key=api_key)

    kept_items = []
    decisions = []

    for item in ambiguous_items:
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
            verdict_data = {"verdict": "different", "rationale": f"LLM error: {e}"}

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

    return {
        "outputs": {
            "items": json.dumps(kept_items),
            "decisions": json.dumps(decisions),
        },
        "decisions": decisions,
    }
