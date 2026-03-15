# Python Tooling Reference (2026)

Quality tools, AI aids, and development infrastructure for Python projects.
Last updated: 2026-03-15.

---

## Code quality stack

All four core tools are from the **Astral ecosystem** (uv, ruff, ty) — Rust-based, fast, and designed to work together. This is the modern Python stack replacing the legacy combination of pip/pipenv/poetry + flake8 + black + isort + mypy.

### Package management: uv

**uv** replaces pip, pip-tools, pipenv, poetry, pyenv, and virtualenv. Written in Rust, 10-100x faster than pip. Manages Python versions, virtual environments, dependencies, and script execution in one tool.

```bash
# Install
curl -LsSf https://astral.sh/uv/install.sh | sh

# Project setup
uv init myproject
uv add click                    # add dependency
uv add --dev pytest ruff ty     # add dev dependency
uv sync                         # install everything
uv run pytest                   # run in project virtualenv
uv run ruff check .             # run any tool
```

**Key features:**
- Lockfile (`uv.lock`) for reproducible installs — commit this to git
- Workspace support for monorepos
- Python version management (`uv python install 3.12`)
- Script runner (`uv run`) replaces `python -m` and virtualenv activation

- uv docs: https://docs.astral.sh/uv/
- GitHub: https://github.com/astral-sh/uv

### Linting and formatting: Ruff

**Ruff** replaces flake8, isort, black, pyflakes, pycodestyle, pydocstyle, and dozens of flake8 plugins. Single tool for both linting and formatting.

```toml
# pyproject.toml
[tool.ruff]
target-version = "py312"
line-length = 99

[tool.ruff.lint]
select = ["B", "C4", "E", "F", "I", "PT", "RUF", "SIM", "UP", "W"]
```

**Recommended rule categories:**

| Code | Source | What it catches |
|------|--------|-----------------|
| `E` | pycodestyle errors | Basic style violations |
| `W` | pycodestyle warnings | Style warnings (whitespace, etc.) |
| `F` | pyflakes | Logical errors, unused imports/variables |
| `I` | isort | Import sorting and grouping |
| `B` | flake8-bugbear | Common bugs: mutable default args, broad exceptions, etc. |
| `UP` | pyupgrade | Modernize syntax for target Python version |
| `SIM` | flake8-simplify | Simplifiable code patterns |
| `C4` | flake8-comprehensions | Unnecessary list/dict/set calls |
| `PT` | flake8-pytest-style | Pytest best practices (match params, fixture style) |
| `RUF` | ruff-specific | Ruff's own rules (prefer `next()`, unused noqa, etc.) |

**Optional categories** (add when relevant):
- `N` — PEP 8 naming conventions
- `D` — pydocstyle (docstring conventions) — useful for public APIs
- `S` — flake8-bandit (security checks) — add for web-facing code
- `C90` — McCabe complexity
- `PLR` — Pylint refactor rules

```bash
ruff check .                    # lint
ruff check . --fix              # auto-fix what's safe
ruff check . --fix --unsafe-fixes  # auto-fix everything (review changes)
ruff format .                   # format (replaces black)
ruff format --check .           # check formatting without changing
```

- Ruff docs: https://docs.astral.sh/ruff/
- Rule reference: https://docs.astral.sh/ruff/rules/
- GitHub: https://github.com/astral-sh/ruff

### Type checking: ty

**ty** is Astral's type checker (beta, 2025). Written in Rust, designed as the type-checking counterpart to ruff. Replaces mypy and pyright for most use cases.

```bash
ty check           # type-check the project
ty check --watch   # watch mode
```

**Why ty over mypy/pyright:**
- Same ecosystem as ruff and uv — consistent tooling
- Rust-based, significantly faster than mypy
- Better error messages than mypy
- Understands modern Python type syntax natively (PEP 604 unions, etc.)

**py.typed marker (PEP 561):** If your project is a library/SDK, add an empty `py.typed` file in the package root so downstream consumers get type information:

```
mypackage/
  __init__.py
  py.typed        # empty file, signals "this package ships type info"
```

**Fallback:** If ty doesn't cover a specific case (still in beta), **basedpyright** is the production-ready alternative. Community fork of Microsoft's pyright with stricter defaults and better error messages. **mypy** remains widely used but is slower.

- ty announcement: https://astral.sh/blog/ty
- GitHub: https://github.com/astral-sh/ty

### Testing: pytest + pytest-cov

**pytest** is the standard Python test framework. **pytest-cov** adds coverage reporting.

```toml
# pyproject.toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "--cov=mypackage --cov-report=term-missing"

[tool.coverage.run]
source = ["mypackage"]

[tool.coverage.report]
show_missing = true
```

```bash
uv run pytest                   # run tests with coverage
uv run pytest -q                # quiet output
uv run pytest tests/test_foo.py # run specific file
uv run pytest -k "test_name"    # run tests matching pattern
uv run pytest -x               # stop on first failure
uv run pytest --no-cov          # skip coverage (faster for iteration)
```

**Test file conventions:**
- Test files: `tests/test_*.py`
- Test classes: `class TestFeatureName:`
- Test functions: `def test_specific_behavior(self):`
- Fixtures in `tests/conftest.py`
- Use `pytest.raises(ExceptionType, match="pattern")` — always include `match`

- pytest docs: https://docs.pytest.org/
- pytest-cov docs: https://pytest-cov.readthedocs.io/

### Validation pipeline

```bash
uv run ruff check .
uv run ruff format --check .
uv run ty check
uv run pytest
```

Run all four before every commit. All must pass.

---

## Project setup template

### pyproject.toml (minimal)

```toml
[project]
name = "myproject"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = []

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-cov>=6.0",
    "ruff>=0.8",
    "ty",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.ruff]
target-version = "py312"
line-length = 99

[tool.ruff.lint]
select = ["B", "C4", "E", "F", "I", "PT", "RUF", "SIM", "UP", "W"]

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "--cov=myproject --cov-report=term-missing"

[tool.coverage.run]
source = ["myproject"]

[tool.coverage.report]
show_missing = true
```

### Directory structure

```
myproject/
  pyproject.toml
  uv.lock              # commit this
  myproject/
    __init__.py
    py.typed            # if library/SDK
    ...
  tests/
    conftest.py
    test_*.py
```

### First-time setup

```bash
uv init myproject
cd myproject
uv add --dev pytest pytest-cov ruff ty
# configure pyproject.toml as above
uv sync
uv run ruff check .
uv run ty check
uv run pytest
```

---

## AI development aids

### Context7 MCP server

Broad library documentation fetching across ecosystems. Lets AI assistants look up real library docs instead of relying on training data.

- GitHub: https://github.com/upstash/context7

### What doesn't help AI assistants

**Language servers** (Pylance, Jedi LSP, python-lsp-server) help your *editor* with completions, go-to-definition, and inline diagnostics. They do NOT help Claude Code or other AI coding tools — those don't use LSP. Still worth setting up for your own editing experience.

---

## What we don't use (and why)

| Tool | Status | Why not |
|------|--------|---------|
| **black** | Replaced | Ruff formatter is a drop-in replacement, faster, and part of the same toolchain |
| **isort** | Replaced | Ruff `I` rules handle import sorting |
| **flake8** | Replaced | Ruff implements all flake8 rules and plugins, faster |
| **mypy** | Replaced | ty is faster, same ecosystem. basedpyright as fallback if needed |
| **pip / pip-tools** | Replaced | uv handles everything pip does, 10-100x faster |
| **poetry / pipenv** | Replaced | uv is simpler and faster for dependency management |
| **tox / nox** | Not needed | uv + pytest handle test environments; add if multi-Python-version testing is needed |
| **bandit** | Deferred | Ruff `S` rules cover the same checks; add when security-sensitive code exists |
