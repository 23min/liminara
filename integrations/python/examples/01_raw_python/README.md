# Example 01: Raw Python + Anthropic SDK

Demonstrates Liminara instrumentation on a simple pipeline (load document, summarize with Claude Haiku, save output) using raw Python and the Anthropic SDK directly.

Two versions of the same pipeline:
- `pipeline_raw.py` — uninstrumented (no Liminara)
- `pipeline_instrumented.py` — same logic, wrapped with `@op` and `@decision` decorators

## Usage

```bash
export ANTHROPIC_API_KEY=your-key
uv run python examples/01_raw_python/run.py
```
