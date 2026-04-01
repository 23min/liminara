"""Mock embedding provider for testing — deterministic, no API calls."""

import hashlib
import math


class MockEmbeddingProvider:
    """Generates deterministic embeddings from text content via hashing.
    Useful for testing the pipeline without API keys."""

    def __init__(self, dims: int = 64, **kwargs):
        self._dims = dims

    def embed(self, texts: list[str]) -> list[list[float]]:
        return [self._text_to_embedding(t) for t in texts]

    def dimensions(self) -> int:
        return self._dims

    def model_name(self) -> str:
        return "mock-embedding-v1"

    def _text_to_embedding(self, text: str) -> list[float]:
        """Hash-based deterministic embedding. Same text → same vector."""
        h = hashlib.sha256(text.encode("utf-8")).digest()
        # Expand hash bytes into floats, normalize to unit vector
        raw = [((b - 128) / 128.0) for b in h]
        # Repeat/truncate to desired dimensions
        while len(raw) < self._dims:
            raw = raw + raw
        raw = raw[: self._dims]
        # L2 normalize
        norm = math.sqrt(sum(x * x for x in raw))
        if norm > 0:
            raw = [x / norm for x in raw]
        return raw
