"""Shared test fixtures."""

from pathlib import Path

import pytest


@pytest.fixture
def tmp_store(tmp_path: Path) -> Path:
    """Provide a temporary directory for artifact/event storage."""
    store = tmp_path / "store"
    store.mkdir()
    return store
