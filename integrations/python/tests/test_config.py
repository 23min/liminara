"""Tests for config.py — LiminaraConfig dataclass.

Spec reference: M-CS-03-decorators.md § config.py — LiminaraConfig

Resolution order: constructor arg > env var > default.
Defaults: store_root=.liminara/store/artifacts, runs_root=.liminara/runs (relative to cwd).
"""

from pathlib import Path

from liminara.config import LiminaraConfig


class TestDefaults:
    """Default paths when no args or env vars are provided."""

    def test_default_store_root(self):
        """Default store_root is .liminara/store/artifacts relative to cwd."""
        config = LiminaraConfig()
        expected = Path.cwd() / ".liminara" / "store" / "artifacts"
        assert config.store_root == expected

    def test_default_runs_root(self):
        """Default runs_root is .liminara/runs relative to cwd."""
        config = LiminaraConfig()
        expected = Path.cwd() / ".liminara" / "runs"
        assert config.runs_root == expected

    def test_no_args_no_env(self, monkeypatch):
        """With no args and no env vars, defaults are used."""
        monkeypatch.delenv("LIMINARA_STORE_ROOT", raising=False)
        monkeypatch.delenv("LIMINARA_RUNS_ROOT", raising=False)
        config = LiminaraConfig()
        assert config.store_root == Path.cwd() / ".liminara" / "store" / "artifacts"
        assert config.runs_root == Path.cwd() / ".liminara" / "runs"


class TestConstructorOverrides:
    """Constructor arguments override defaults and env vars."""

    def test_constructor_overrides_store_root(self, tmp_path: Path):
        """Constructor arg for store_root overrides default."""
        custom = tmp_path / "custom_store"
        config = LiminaraConfig(store_root=custom)
        assert config.store_root == custom

    def test_constructor_overrides_runs_root(self, tmp_path: Path):
        """Constructor arg for runs_root overrides default."""
        custom = tmp_path / "custom_runs"
        config = LiminaraConfig(runs_root=custom)
        assert config.runs_root == custom

    def test_constructor_overrides_env_var(self, tmp_path: Path, monkeypatch):
        """Constructor arg takes precedence over env var."""
        monkeypatch.setenv("LIMINARA_STORE_ROOT", "/env/store")
        monkeypatch.setenv("LIMINARA_RUNS_ROOT", "/env/runs")
        custom_store = tmp_path / "arg_store"
        custom_runs = tmp_path / "arg_runs"
        config = LiminaraConfig(store_root=custom_store, runs_root=custom_runs)
        assert config.store_root == custom_store
        assert config.runs_root == custom_runs


class TestEnvVarOverrides:
    """Env vars override defaults but not constructor args."""

    def test_env_var_overrides_store_root(self, monkeypatch):
        """LIMINARA_STORE_ROOT env var overrides default store_root."""
        monkeypatch.setenv("LIMINARA_STORE_ROOT", "/custom/env/store")
        config = LiminaraConfig()
        assert config.store_root == Path("/custom/env/store")

    def test_env_var_overrides_runs_root(self, monkeypatch):
        """LIMINARA_RUNS_ROOT env var overrides default runs_root."""
        monkeypatch.setenv("LIMINARA_RUNS_ROOT", "/custom/env/runs")
        config = LiminaraConfig()
        assert config.runs_root == Path("/custom/env/runs")


class TestPathConversion:
    """String paths are converted to Path objects."""

    def test_string_store_root_converted(self):
        """String store_root is converted to Path."""
        config = LiminaraConfig(store_root="/some/path")
        assert isinstance(config.store_root, Path)
        assert config.store_root == Path("/some/path")

    def test_string_runs_root_converted(self):
        """String runs_root is converted to Path."""
        config = LiminaraConfig(runs_root="/some/runs")
        assert isinstance(config.runs_root, Path)
        assert config.runs_root == Path("/some/runs")
