"""Embedding provider protocol and factory."""

from __future__ import annotations

from typing import Protocol


class EmbeddingProvider(Protocol):
    def embed(self, texts: list[str]) -> list[list[float]]: ...
    def dimensions(self) -> int: ...
    def model_name(self) -> str: ...


def get_provider(provider_name: str, **kwargs) -> EmbeddingProvider:
    """Factory: instantiate an embedding provider by name."""
    if provider_name == "mock":
        from providers.embedding_mock import MockEmbeddingProvider
        return MockEmbeddingProvider(**kwargs)
    elif provider_name == "model2vec":
        from providers.embedding_model2vec import Model2VecEmbeddingProvider
        return Model2VecEmbeddingProvider(**kwargs)
    elif provider_name == "voyage":
        from providers.embedding_voyage import VoyageEmbeddingProvider
        return VoyageEmbeddingProvider(**kwargs)
    else:
        raise ValueError(f"Unknown embedding provider: {provider_name}")
