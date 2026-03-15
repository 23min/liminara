# Example 01: Raw Python + Anthropic SDK

Demonstrates Liminara's compliance value on a simple document summarization pipeline.

## What this proves

1. **Raw pipeline** (`pipeline_raw.py`) — calls an LLM, gets a summary. No logs, no audit trail, not Article 12 compliant.
2. **Instrumented pipeline** (`pipeline_instrumented.py`) — same logic, same function bodies. Only difference: `@op` and `@decision` decorators plus a `with run(...)` wrapper. Every nondeterministic choice (the LLM response) is recorded as a decision.
3. **Both runs are compliant** — each has a complete event log, hash chain, tamper-evident seal, and Article 12 compliance report.
4. **Decisions enable replay** — stored decision records mean the Elixir runtime (future) can replay any run deterministically.

## Usage

```bash
# Install the anthropic SDK (optional dependency)
uv sync --extra anthropic

# Option A: set your API key in a .env file
cp .env.example .env
# Edit .env and add your key

# Option B: or export it directly
export ANTHROPIC_API_KEY=sk-ant-...

# Run the full demo
uv run python examples/01_raw_python/demo.py
```

## Swapping LLM providers

The LLM call is isolated in `llm.py` — a single function:

```python
def call_llm(prompt: str) -> str:
    ...
```

To use a different provider (OpenAI, a local model, etc.), replace the body of this function. The rest of the pipeline is unchanged. The `@op`/`@decision` decorators don't care what's inside — they record the input and output regardless.

## Files

- `llm.py` — LLM abstraction (Anthropic default)
- `pipeline_raw.py` — uninstrumented pipeline
- `pipeline_instrumented.py` — instrumented pipeline with `@op`/`@decision`
- `demo.py` — runs the full compliance demo arc
