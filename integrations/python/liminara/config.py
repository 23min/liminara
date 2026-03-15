"""Store paths and configuration defaults."""

import os
from dataclasses import dataclass, field
from pathlib import Path


def _resolve_path(arg: Path | str | None, env_var: str, default: Path) -> Path:
    """Resolve path: constructor arg > env var > default."""
    if arg is not None:
        return Path(arg)
    env = os.environ.get(env_var)
    if env is not None:
        return Path(env)
    return default


def _default_store_root() -> Path:
    default = Path.cwd() / ".liminara" / "store" / "artifacts"
    return _resolve_path(None, "LIMINARA_STORE_ROOT", default)


def _default_runs_root() -> Path:
    return _resolve_path(None, "LIMINARA_RUNS_ROOT", Path.cwd() / ".liminara" / "runs")


@dataclass
class LiminaraConfig:
    """Configuration for Liminara store and run paths.

    Resolution order: constructor arg > env var > default.

    Accepts Path, str, or None. After init, both fields are always Path.
    """

    store_root: Path = field(default_factory=_default_store_root)
    runs_root: Path = field(default_factory=_default_runs_root)

    def __init__(
        self,
        store_root: Path | str | None = None,
        runs_root: Path | str | None = None,
    ) -> None:
        self.store_root = _resolve_path(
            store_root,
            "LIMINARA_STORE_ROOT",
            Path.cwd() / ".liminara" / "store" / "artifacts",
        )
        self.runs_root = _resolve_path(
            runs_root,
            "LIMINARA_RUNS_ROOT",
            Path.cwd() / ".liminara" / "runs",
        )
