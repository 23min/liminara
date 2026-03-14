---
id: M-LC-01-callback-handler
epic: E-03-langchain-integration
status: draft
---

# M-LC-01: LiminaraCallbackHandler

## Goal

Implement the LangChain callback handler that automatically records Liminara events and decisions for any LangChain chain or LLM call. This is the "one-line integration" — adding `callbacks=[LiminaraCallbackHandler()]` to an existing LangChain application.

## Context: How LangChain callbacks work

LangChain provides `BaseCallbackHandler` with methods that fire at lifecycle points: when an LLM call starts, when it ends, when a chain starts, etc. You subclass it, implement the methods you care about, and pass an instance as a callback. LangChain calls your methods automatically.

Key methods:
- `on_llm_start(serialized, prompts, **kwargs)` — LLM call begins
- `on_llm_end(response, **kwargs)` — LLM call completes, response available
- `on_llm_error(error, **kwargs)` — LLM call failed
- `on_chain_start(serialized, inputs, **kwargs)` — chain begins
- `on_chain_end(outputs, **kwargs)` — chain completes
- `on_chain_error(error, **kwargs)` — chain failed

## Acceptance criteria

### LiminaraCallbackHandler (`liminara/integrations/langchain.py`)

- [ ] Subclasses `BaseCallbackHandler` from `langchain_core`
- [ ] Constructor accepts optional `run` context (if not provided, creates one)
- [ ] `on_llm_start`: emits `op_started` event, captures model name from serialized config, hashes prompt as input artifact
- [ ] `on_llm_end`: records decision (model ID, prompt hash, response hash, token usage from response.llm_output), emits `decision_recorded` and `op_completed` events
- [ ] `on_llm_error`: emits `op_failed` event with error details
- [ ] `on_chain_start`: emits `op_started` event with chain name and input hashes
- [ ] `on_chain_end`: emits `op_completed` event with output hashes
- [ ] `on_chain_error`: emits `op_failed` event
- [ ] Extracts model ID from LangChain's serialized model config (handles `ChatAnthropic`, `ChatOpenAI`, etc.)
- [ ] Extracts token usage from LangChain's response metadata

### Integration with Liminara run context

- [ ] If used within a `with liminara.run(...)` context, events go to that run
- [ ] If used standalone, creates its own run context
- [ ] Multiple callback handler instances in the same run produce events in the same event log

### Usage pattern

```python
from liminara.integrations.langchain import LiminaraCallbackHandler
from langchain_anthropic import ChatAnthropic

handler = LiminaraCallbackHandler()
llm = ChatAnthropic(model="claude-haiku-4-5-20251001")

# Option A: per-call
result = llm.invoke("What is Article 12?", config={"callbacks": [handler]})

# Option B: on the model
llm_with_callbacks = ChatAnthropic(
    model="claude-haiku-4-5-20251001",
    callbacks=[handler]
)
result = llm_with_callbacks.invoke("What is Article 12?")
```

## Tests

- `test_langchain_callback.py`:
  - Handler emits op_started on LLM call
  - Handler emits decision_recorded with model ID and token usage on LLM completion
  - Handler emits op_failed on LLM error
  - Handler emits chain start/end events
  - Decision record contains correct model ID (extracted from LangChain config)
  - Token usage is captured in decision record
  - Hash chain is valid after a LangChain invocation
  - Handler works with and without explicit run context
  - Multiple LLM calls in one run produce sequential events with correct hash chain

## Out of scope

- Retriever callbacks (`on_retriever_start`, `on_retriever_end`) — add if needed in M-LC-02
- Tool callbacks (`on_tool_start`, `on_tool_end`)
- Streaming callbacks (`on_llm_new_token`)
- Agent callbacks

## Spec reference

- `docs/analysis/09_Compliance_Demo_Tool.md` § LiminaraCallbackHandler
- `docs/analysis/07_Compliance_Layer.md` § Model A
- LangChain callbacks: https://python.langchain.com/docs/how_to/custom_callbacks/
