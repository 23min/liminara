"""Tests for artifact_store.py — content-addressed blob storage.

Spec reference: docs/analysis/11_Data_Model_Spec.md

Sharding: {store_root}/{hex[0:2]}/{hex[2:4]}/{hex}
where hex is the 64 hex chars (sha256: prefix stripped for path construction).
Git-style sharding. Spec example:
  hash = sha256:2c624232cdd221771294dfbb310acbc8f347f4a1c695fc8e2d0a48967caa8b97
  path = {store_root}/2c/62/2c624232cdd221771294dfbb310acbc8f347f4a1c695fc8e2d0a48967caa8b97
"""

import hashlib
from pathlib import Path

import pytest

from liminara.artifact_store import ArtifactStore


@pytest.fixture
def store(tmp_path: Path) -> ArtifactStore:
    """Create an ArtifactStore rooted in a temp directory."""
    return ArtifactStore(tmp_path / "artifacts")


class TestWriteAndRead:
    """Write blob → read blob round-trip."""

    def test_write_returns_hash(self, store: ArtifactStore):
        """write() returns the sha256:{hex} hash of the content."""
        content = b"hello world"
        result = store.write(content)
        expected = "sha256:" + hashlib.sha256(content).hexdigest()
        assert result == expected

    def test_read_returns_content(self, store: ArtifactStore):
        """read() returns the exact bytes that were written."""
        content = b"hello world"
        h = store.write(content)
        assert store.read(h) == content

    def test_round_trip_binary(self, store: ArtifactStore):
        """Binary content survives write + read."""
        content = bytes(range(256))
        h = store.write(content)
        assert store.read(h) == content

    def test_read_nonexistent_raises(self, store: ArtifactStore):
        """Reading a hash that doesn't exist raises an error."""
        fake_hash = "sha256:" + "ab" * 32
        with pytest.raises(FileNotFoundError):
            store.read(fake_hash)


class TestIdempotentWrite:
    """Same content written twice → one file, same hash."""

    def test_same_hash(self, store: ArtifactStore):
        """Writing identical content returns the same hash."""
        content = b"duplicate"
        h1 = store.write(content)
        h2 = store.write(content)
        assert h1 == h2

    def test_single_file(self, store: ArtifactStore):
        """Writing identical content doesn't create additional files."""
        content = b"duplicate"
        store.write(content)
        store.write(content)

        # Count all files under the store root
        all_files = list(store.root.rglob("*"))
        blob_files = [f for f in all_files if f.is_file()]
        assert len(blob_files) == 1


class TestDirectorySharding:
    """Artifact stored at {store_root}/{hex[0:2]}/{hex[2:4]}/{hex} (Git-style).

    Spec example:
      sha256:2c624232cdd221771294dfbb310acbc8f347f4a1c695fc8e2d0a48967caa8b97
      → {store_root}/2c/62/2c624232cdd221771294dfbb310acbc8f347f4a1c695fc8e2d0a48967caa8b97
    """

    def test_sharding_matches_spec_example(self, store: ArtifactStore):
        """File is stored with correct directory sharding per spec example."""
        content = b"test content"
        h = store.write(content)
        hex_part = h[7:]  # strip "sha256:"

        # Spec: hex[0:2] / hex[2:4] / full_hex
        shard1 = hex_part[0:2]
        shard2 = hex_part[2:4]
        expected_path = store.root / shard1 / shard2 / hex_part
        assert expected_path.exists()
        assert expected_path.read_bytes() == content

    def test_known_hash_sharding(self, store: ArtifactStore):
        """Verify sharding with a precomputed hash."""
        # SHA-256 of empty bytes is well-known
        content = b""
        h = store.write(content)
        hex_part = h[7:]
        # e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        assert hex_part == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        expected_path = store.root / hex_part[0:2] / hex_part[2:4] / hex_part
        assert expected_path.exists()


class TestEmptyContent:
    """Empty bytes have correct hash and are stored correctly."""

    def test_empty_hash(self, store: ArtifactStore):
        """Empty content produces the well-known SHA-256 empty hash."""
        h = store.write(b"")
        assert h == "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    def test_empty_read_back(self, store: ArtifactStore):
        """Empty content can be read back."""
        h = store.write(b"")
        assert store.read(h) == b""
