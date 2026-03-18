"""Build LanceDB vector index from Liminara documentation.

Loads three markdown docs, splits into chunks, embeds with fastembed,
and stores in a LanceDB table. Uses all-MiniLM-L6-v2 (23MB, CPU-only).

Usage:
    uv run python examples/02_langchain/setup_index.py
"""

from __future__ import annotations

from pathlib import Path

import lancedb
from langchain_community.document_loaders import TextLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter

# Project root relative to this file (examples/02_langchain/ → integrations/python/ → liminara/)
_DEFAULT_DOCS_DIR = Path(__file__).resolve().parent.parent.parent.parent.parent

# The three docs to index
_DOC_PATHS = [
    "docs/analysis/08_Article_12_Summary.md",
    "docs/analysis/10_Synthesis.md",
    "docs/architecture/01_CORE.md",
]

_EMBEDDING_MODEL = "sentence-transformers/all-MiniLM-L6-v2"
_TABLE_NAME = "docs"


def build_index(db_path: Path, docs_dir: Path | None = None) -> dict:
    """Build vector index from markdown docs.

    Returns {"doc_count": N, "chunk_count": M, "table_name": str}.
    """
    if docs_dir is None:
        docs_dir = _DEFAULT_DOCS_DIR

    # Load documents
    docs = []
    for rel_path in _DOC_PATHS:
        full_path = docs_dir / rel_path
        loader = TextLoader(str(full_path))
        docs.extend(loader.load())

    doc_count = len(docs)

    # Split into chunks
    splitter = RecursiveCharacterTextSplitter(chunk_size=500, chunk_overlap=50)
    chunks = splitter.split_documents(docs)

    # Embed with fastembed
    from fastembed import TextEmbedding

    model = TextEmbedding(model_name=_EMBEDDING_MODEL)
    texts = [chunk.page_content for chunk in chunks]
    embeddings = list(model.embed(texts))

    # Store in LanceDB
    db = lancedb.connect(db_path)

    # Drop existing table if present (idempotent rebuild)
    if _TABLE_NAME in db.table_names():
        db.drop_table(_TABLE_NAME)

    data = [
        {
            "text": texts[i],
            "vector": embeddings[i].tolist(),
            "source": chunks[i].metadata.get("source", ""),
        }
        for i in range(len(chunks))
    ]

    db.create_table(_TABLE_NAME, data=data)

    return {"doc_count": doc_count, "chunk_count": len(chunks), "table_name": _TABLE_NAME}


if __name__ == "__main__":
    db_path = Path(__file__).parent / ".lancedb"
    stats = build_index(db_path=db_path)
    print(f"Indexed {stats['doc_count']} documents → {stats['chunk_count']} chunks")
    print(f"LanceDB table: {stats['table_name']} at {db_path}")
