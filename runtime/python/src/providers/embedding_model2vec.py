"""Local embedding provider using model2vec (no API, no PyTorch, no ONNX)."""

from model2vec import StaticModel


class Model2VecEmbeddingProvider:
    """Uses model2vec static embeddings for fast, local, offline embedding."""

    def __init__(self, model_name: str = "minishlab/potion-base-8M", **kwargs):
        self._model_name = model_name
        self._model = StaticModel.from_pretrained(model_name)

    def embed(self, texts: list[str]) -> list[list[float]]:
        if not texts:
            return []
        embeddings = self._model.encode(texts)
        return [e.tolist() for e in embeddings]

    def dimensions(self) -> int:
        # potion-base-8M = 256, potion-base-32M = 512
        return self._model.dim

    def model_name(self) -> str:
        return self._model_name
