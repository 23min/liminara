"""RAG pipeline: ask questions about Liminara docs.

Retrieves relevant chunks from a LanceDB index, builds a prompt,
and calls an LLM via LangChain — all instrumented with Liminara.

Usage:
    uv run python examples/02_langchain/run.py                          # interactive REPL
    uv run python examples/02_langchain/run.py "What is Article 12?"    # single question
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import lancedb
from fastembed import TextEmbedding
from langchain_core.language_models import BaseChatModel
from langchain_core.messages import HumanMessage, SystemMessage
from langchain_core.output_parsers import StrOutputParser

from liminara.config import LiminaraConfig
from liminara.integrations.langchain import LiminaraCallbackHandler
from liminara.run import run

_TABLE_NAME = "docs"
_EMBEDDING_MODEL = "sentence-transformers/all-MiniLM-L6-v2"
_K = 4  # number of chunks to retrieve

_SYSTEM_PROMPT = """You are a helpful assistant answering questions about Liminara, \
a runtime for reproducible nondeterministic computation. \
Answer based only on the provided context. If the context doesn't contain \
enough information, say so."""


def _retrieve(question: str, db_path: Path, k: int = _K) -> list[str]:
    """Retrieve top-k relevant chunks from LanceDB."""
    db = lancedb.connect(db_path)
    table = db.open_table(_TABLE_NAME)

    model = TextEmbedding(model_name=_EMBEDDING_MODEL)
    query_embedding = next(iter(model.embed([question]))).tolist()

    results = table.search(query_embedding).limit(k).to_list()
    return [r["text"] for r in results]


def ask_question(
    question: str,
    db_path: Path,
    llm: BaseChatModel | None = None,
    config: LiminaraConfig | None = None,
) -> tuple[str, str, int, str]:
    """Ask a question against the index.

    Returns (answer, run_id, event_count, seal_hash).
    """
    if llm is None:
        from langchain_anthropic import ChatAnthropic

        llm = ChatAnthropic(model="claude-haiku-4-5-20251001")

    # Retrieve relevant chunks
    chunks = _retrieve(question, db_path)
    context = "\n\n---\n\n".join(chunks)

    # Build messages
    messages = [
        SystemMessage(content=_SYSTEM_PROMPT),
        HumanMessage(content=f"Context:\n{context}\n\nQuestion: {question}"),
    ]

    # Run with Liminara instrumentation
    handler = LiminaraCallbackHandler()

    with run("langchain-rag", "1.0.0", config=config) as r:
        response = llm.invoke(messages, config={"callbacks": [handler]})
        answer = StrOutputParser().invoke(response)

    # Read seal
    events = r.event_log.read_all()
    seal_path = (config or LiminaraConfig()).runs_root / r.run_id / "seal.json"
    seal_data = json.loads(seal_path.read_bytes())

    return answer, r.run_id, len(events), seal_data["run_seal"]


def main() -> None:
    """Interactive REPL or single-question mode."""
    from setup_index import build_index

    db_path = Path(__file__).parent / ".lancedb"

    # Build index if it doesn't exist
    if not db_path.exists() or _TABLE_NAME not in lancedb.connect(db_path).table_names():
        docs_dir = Path(__file__).resolve().parent.parent.parent.parent.parent
        print("Building index...")
        stats = build_index(db_path=db_path, docs_dir=docs_dir)
        print(f"Indexed {stats['doc_count']} documents → {stats['chunk_count']} chunks")

    # Load index stats
    db = lancedb.connect(db_path)
    table = db.open_table(_TABLE_NAME)
    chunk_count = table.count_rows()
    print(f"Loaded index: {chunk_count} chunks")

    # Single-question mode
    if len(sys.argv) > 1:
        question = " ".join(sys.argv[1:])
        answer, run_id, event_count, seal = ask_question(question, db_path)
        print(f"\n{answer}")
        print(f"\n[Run {run_id} | {event_count} events | seal: {seal[:15]}...]")
        return

    # Interactive REPL
    print('Type a question, or "quit" to exit.\n')
    run_count = 0

    while True:
        try:
            question = input("? ")
        except (EOFError, KeyboardInterrupt):
            break

        if question.strip().lower() in ("quit", "exit", "q"):
            break

        if not question.strip():
            continue

        answer, run_id, event_count, seal = ask_question(question, db_path)
        print(f"\n{answer}")
        print(f"\n[Run {run_id} | {event_count} events | seal: {seal[:15]}...]")
        print()
        run_count += 1

    print(f"\n{run_count} runs recorded. Run 'liminara list' to see them.")


if __name__ == "__main__":
    main()
