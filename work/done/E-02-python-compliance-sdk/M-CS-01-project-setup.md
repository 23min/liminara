---
id: M-CS-01-project-setup
epic: E-02-python-compliance-sdk
status: draft
---

# M-CS-01: Python Project Scaffolding

## Goal

Set up the Python project structure with `uv`, `pyproject.toml`, directory layout, and basic tooling so that subsequent milestones can focus on implementation.

## Acceptance criteria

- [ ] `integrations/python/` directory exists with the full layout below
- [ ] `pyproject.toml` configured with project metadata, Python 3.12+ requirement, dependencies, and CLI entry point
- [ ] `uv lock` succeeds and produces `uv.lock`
- [ ] `uv run liminara --help` prints CLI help (stub — just the help text, no real commands yet)
- [ ] `uv run pytest` runs and passes (with a single placeholder test)
- [ ] Linting/formatting configured: `ruff` for both linting and formatting
- [ ] `uv run ruff check .` and `uv run ruff format --check .` pass

## Directory layout

```
integrations/python/
  pyproject.toml
  uv.lock
  README.md                          # Brief: what this is, how to install, how to run
  liminara/
    __init__.py                      # Package init, version
    cli.py                           # Click CLI entry point (stubs)
    config.py                        # Store paths, defaults
    hash.py                          # (stub) SHA-256, canonical JSON
    event_log.py                     # (stub)
    artifact_store.py                # (stub)
    decision_store.py                # (stub)
    decorators.py                    # (stub)
    run.py                           # (stub)
    report.py                        # (stub)
    integrations/
      __init__.py
      langchain.py                   # (stub, for E-03)
  examples/
    01_raw_python/
      README.md                      # What this example demonstrates
    02_langchain/
      README.md                      # What this example demonstrates
  tests/
    __init__.py
    conftest.py                      # Shared fixtures (tmp_path for store, etc.)
    test_placeholder.py              # Single passing test to verify setup
```

## Dependencies (pyproject.toml)

```toml
[project]
name = "liminara"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "click>=8.0",
    "canonicaljson>=2.0",
]

[project.optional-dependencies]
anthropic = ["anthropic>=0.40"]
langchain = [
    "langchain-core>=0.3",
    "langchain-anthropic>=0.3",
    "langchain-chroma>=0.2",
    "langchain-community>=0.3",
    "sentence-transformers>=3.0",
    "chromadb>=0.5",
]
dev = [
    "pytest>=8.0",
    "ruff>=0.8",
]

[project.scripts]
liminara = "liminara.cli:main"
```

## Out of scope

- Any real implementation (all modules are stubs with docstrings and `pass`)
- Tests beyond the placeholder
- CI/CD configuration

## Spec reference

`docs/analysis/09_Compliance_Demo_Tool.md` § Repository structure
