"""Store paths and configuration defaults."""

import os
from dataclasses import dataclass
from pathlib import Path


def _resolve_path(arg: Path | str | None, env_var: str, default: Path) -> Path:
    """Resolve path: constructor arg > env var > default."""
    if arg is not None:
        return Path(arg)
    env = os.environ.get(env_var)
    if env is not None:
        return Path(env)
    return default


@dataclass
class LiminaraConfig:
    """Configuration for Liminara store and run paths.

    Resolution order: constructor arg > env var > default.
    """

    store_root: Path | str | None = None
    runs_root: Path | str | None = None

    def __post_init__(self):
        self.store_root = _resolve_path(
            self.store_root,
            "LIMINARA_STORE_ROOT",
            Path.cwd() / ".liminara" / "store" / "artifacts",
        )
        self.runs_root = _resolve_path(
            self.runs_root,
            "LIMINARA_RUNS_ROOT",
            Path.cwd() / ".liminara" / "runs",
        )
