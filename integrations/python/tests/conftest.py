"""Shared test fixtures."""

import os
from pathlib import Path

import pytest


def pytest_addoption(parser: pytest.Parser) -> None:
    parser.addoption(
        "--run-integration",
        action="store_true",
        default=False,
        help="Run integration tests that require ANTHROPIC_API_KEY",
    )


def pytest_collection_modifyitems(config: pytest.Config, items: list[pytest.Item]) -> None:
    if config.getoption("--run-integration"):
        # Only skip if API key is missing
        skip = pytest.mark.skip(reason="ANTHROPIC_API_KEY not set")
        for item in items:
            if "integration" in item.keywords and not os.environ.get("ANTHROPIC_API_KEY"):
                item.add_marker(skip)
    # else: -m 'not integration' in addopts already excludes them


@pytest.fixture
def tmp_store(tmp_path: Path) -> Path:
    """Provide a temporary directory for artifact/event storage."""
    store = tmp_path / "store"
    store.mkdir()
    return store
