"""Instrumented pipeline — same logic, with Liminara compliance.

Same document summarization pipeline as pipeline_raw.py, but with
@op and @decision decorators. Function bodies are identical.
Every nondeterministic choice (the LLM response) is recorded as a
decision, enabling replay, auditing, and Article 12 compliance.
"""

from llm import call_llm

from liminara import LiminaraConfig, decision, op, run

DOCUMENTS = [
    "Recent advances in transformer architectures show that sparse attention "
    "mechanisms can reduce computational cost while maintaining accuracy.",
    "A new study from MIT demonstrates that chain-of-thought prompting "
    "significantly improves reasoning capabilities in large language models.",
    "Industry adoption of large language models has accelerated, with 78% of "
    "Fortune 500 companies now using AI-powered text generation in production.",
]


@op(name="load_documents", version="1.0.0", determinism="pure")
def load_documents() -> list[str]:
    """Load documents. In a real pipeline, this might read from a database or API."""
    return DOCUMENTS


@op(name="summarize", version="1.0.0", determinism="recordable")
@decision(decision_type="llm_response")
def summarize(docs: list[str]) -> str:
    """Summarize documents using an LLM."""
    content = "\n\n".join(docs)
    prompt = f"Summarize the following documents in 2-3 sentences:\n\n{content}"
    return call_llm(prompt)


def run_pipeline(config: LiminaraConfig | None = None) -> tuple[str, str]:
    """Run the instrumented pipeline. Returns (summary, run_id)."""
    with run("example-01", "1.0.0", config=config) as r:
        docs = load_documents()
        summary = summarize(docs)
    return summary, r.run_id


if __name__ == "__main__":
    result, rid = run_pipeline()
    print(result)
    print(f"\nRun ID: {rid}")
