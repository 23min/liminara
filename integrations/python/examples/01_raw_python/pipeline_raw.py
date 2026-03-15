"""Uninstrumented pipeline — no Liminara, no compliance.

A simple document summarization pipeline using raw Python and the
Anthropic SDK. No event logging, no decision recording, no audit trail.
This represents what most teams have today.
"""

from llm import call_llm

DOCUMENTS = [
    "Recent advances in transformer architectures show that sparse attention "
    "mechanisms can reduce computational cost while maintaining accuracy.",
    "A new study from MIT demonstrates that chain-of-thought prompting "
    "significantly improves reasoning capabilities in large language models.",
    "Industry adoption of large language models has accelerated, with 78% of "
    "Fortune 500 companies now using AI-powered text generation in production.",
]


def load_documents() -> list[str]:
    """Load documents. In a real pipeline, this might read from a database or API."""
    return DOCUMENTS


def summarize(docs: list[str]) -> str:
    """Summarize documents using an LLM."""
    content = "\n\n".join(docs)
    prompt = f"Summarize the following documents in 2-3 sentences:\n\n{content}"
    return call_llm(prompt)


def run_pipeline() -> str:
    """Run the full pipeline: load documents, summarize, return result."""
    docs = load_documents()
    return summarize(docs)


if __name__ == "__main__":
    print(run_pipeline())
