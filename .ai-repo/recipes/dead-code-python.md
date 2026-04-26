---
name: python
fileExts: [.py]
excludePaths:
  - .venv/
  - __pycache__/
  - .pytest_cache/
  - .ruff_cache/
  - dist/
  - build/
  - .scratch/
  - .ai-repo/scratch/
tool: ruff + vulture
toolCmd: "uvx ruff check runtime/python integrations/python --select F,ARG,RUF100 --output-format=json > /tmp/ruff.json 2>&1; uvx vulture runtime/python integrations/python --min-confidence 60 > /tmp/vulture.out 2>&1; echo '=== ruff ==='; cat /tmp/ruff.json; echo; echo '=== vulture ==='; cat /tmp/vulture.out"
---

# Dead-code recipe: Python (ruff + vulture via uvx)

Two tools, one pass. Ruff handles the file-local layer (unused imports, unused locals, unused args, stale `noqa`); vulture handles cross-module unused symbols. Both run via `uvx` so neither becomes a project dependency.

## Why two tools

Astral's lineup doesn't ship a cross-module dead-code tool — `ty` is a type checker, not a reachability tool. Ruff alone leaves cross-module unused functions invisible to the recipe. Vulture fills that gap with one ephemeral install via `uvx`; no `pyproject.toml` change in either project, no lockfile churn.

## Things to look out for in this stack

Liminara's Python ops run via `:port` — the Elixir side spawns a Python process and exchanges JSON over stdin/stdout. Static dead-code tools cannot see this dispatch.

- **Op entry points** — any `def` in `runtime/python/` registered as an op handler (typically dispatched on a JSON message type field) is runtime-resolved. Grep for the function name as a string literal before flagging.
- **CLI entry points** — `if __name__ == "__main__"` blocks and any function exposed in `pyproject.toml`'s `[project.scripts]` table.
- **pytest fixtures** — `@pytest.fixture`-decorated functions are discovered by name; collection helpers, `conftest.py` contents, parametrize sources.
- **Pydantic / dataclass fields** — model fields read via `.dict()` / `.model_dump()` / serialization look unused; vulture occasionally flags them.
- **Type-only imports** — `if TYPE_CHECKING:` imports may parse as unused; ruff F401 already special-cases these but verify.
- **Plugin / decorator registrations** — anything that registers itself by import-time side-effect (e.g. `@register("name")`).

## Public surface notes

- `runtime/python/` is the Elixir-side port surface — its public functions are called from Elixir over the wire. Cross-module callers may be Elixir, not Python; grep the Elixir tree for the function name as a string before confirming dead.
- `integrations/python/` is the integration surface — consumed by external systems or scheduled jobs. Treat module-level public functions as live unless specifically confirmed orphaned.

## Tool-specific notes

- **ruff** rules: `F` (pyflakes — unused imports/vars/redefined), `ARG` (unused arguments), `RUF100` (stale `noqa` comments). Suppress nothing extra at recipe level — project-level `pyproject.toml` already filters its noise.
- **vulture** confidence: 60 is a deliberate floor — high enough to keep noise manageable, low enough to surface dynamic-dispatch suspects for human triage. Drop to 80 if the report grows too noisy; raise to 50 if real findings are getting filtered.
- Both tools emit different formats — ruff JSON, vulture plain text. The composite `toolCmd` prefixes each section; the LLM reader splits on `=== ruff ===` / `=== vulture ===`.

## Blind-spot families to sweep manually

- **Orphan fixtures** — `.json`, `.yaml`, `.csv` fixture files under `tests/fixtures/` or `runtime/python/tests/` with no test reference.
- **Stale ADRs** — `docs/decisions/NNNN-*.md` citing Python modules/functions absent from the HEAD tree.
- **Schema fields with no consumers** — Pydantic / dataclass fields not produced or consumed.
- **Helpers retained "for stability"** — exported functions with zero callers and a "kept for compat" comment.
- **Deprecated CLI subcommands** — argparse / click subcommands wired up but never invoked.
