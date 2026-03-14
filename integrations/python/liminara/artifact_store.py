"""Content-addressed filesystem blob store (SHA-256, sharded directories)."""

from pathlib import Path

from liminara.hash import hash_bytes


class ArtifactStore:
    """Content-addressed blob store with Git-style directory sharding.

    Layout: {root}/{hex[0:2]}/{hex[2:4]}/{hex}
    """

    def __init__(self, root: Path) -> None:
        self.root = root

    def write(self, content: bytes) -> str:
        """Write blob, return its hash. Idempotent — same content won't create duplicate files."""
        content_hash = hash_bytes(content)
        path = self._hash_to_path(content_hash)
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        return content_hash

    def read(self, content_hash: str) -> bytes:
        """Read blob by hash. Raises FileNotFoundError if not found."""
        path = self._hash_to_path(content_hash)
        return path.read_bytes()

    def _hash_to_path(self, content_hash: str) -> Path:
        """Convert hash to sharded filesystem path."""
        hex_part = content_hash[7:]  # strip "sha256:"
        return self.root / hex_part[0:2] / hex_part[2:4] / hex_part
