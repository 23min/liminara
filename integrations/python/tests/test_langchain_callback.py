"""Tests for LiminaraCallbackHandler — LangChain callback integration.

Spec reference: M-LC-01-callback-handler.md

Tests that the handler emits correct Liminara events for LangChain lifecycle
callbacks, without requiring real LLM calls. Uses mock LangChain objects to
simulate the callback interface.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any
from uuid import uuid4

import pytest
from langchain_core.messages import AIMessage
from langchain_core.outputs import ChatGeneration, LLMResult

from liminara.config import LiminaraConfig
from liminara.integrations.langchain import LiminaraCallbackHandler
from liminara.run import run


@pytest.fixture
def config(tmp_path: Path) -> LiminaraConfig:
    return LiminaraConfig(
        store_root=tmp_path / "store" / "artifacts",
        runs_root=tmp_path / "runs",
    )


def _serialized_chat_anthropic() -> dict[str, Any]:
    """Fake serialized config for ChatAnthropic, as LangChain passes it."""
    return {
        "lc": 1,
        "type": "constructor",
        "id": ["langchain", "chat_models", "anthropic", "ChatAnthropic"],
        "kwargs": {
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
        },
    }


def _serialized_chain() -> dict[str, Any]:
    """Fake serialized config for a RunnableSequence chain."""
    return {
        "lc": 1,
        "type": "constructor",
        "id": ["langchain", "schema", "runnable", "RunnableSequence"],
        "kwargs": {},
    }


def _llm_result_with_usage() -> LLMResult:
    """Fake LLMResult with token usage metadata."""
    message = AIMessage(
        content="Article 12 requires logging of AI system operations.",
        response_metadata={
            "model": "claude-haiku-4-5-20251001",
            "usage": {
                "input_tokens": 25,
                "output_tokens": 12,
            },
        },
    )
    generation = ChatGeneration(message=message)
    return LLMResult(
        generations=[[generation]],
        llm_output={
            "model": "claude-haiku-4-5-20251001",
            "usage": {
                "input_tokens": 25,
                "output_tokens": 12,
            },
        },
    )


class TestLLMStartEvent:
    """on_llm_start emits op_started event."""

    def test_op_started_emitted(self, config: LiminaraConfig):
        """on_llm_start emits an op_started event."""
        handler = LiminaraCallbackHandler()

        with run("test-pack", "1.0.0", config=config) as r:
            handler.on_llm_start(
                serialized=_serialized_chat_anthropic(),
                prompts=["What is Article 12?"],
                run_id=uuid4(),
            )

        events = r.event_log.read_all()
        op_started = [e for e in events if e["event_type"] == "op_started"]
        assert len(op_started) == 1
        assert op_started[0]["payload"]["op_id"] == "llm"

    def test_model_id_extracted(self, config: LiminaraConfig):
        """Model ID is extracted from serialized ChatAnthropic config."""
        handler = LiminaraCallbackHandler()

        with run("test-pack", "1.0.0", config=config) as r:
            handler.on_llm_start(
                serialized=_serialized_chat_anthropic(),
                prompts=["What is Article 12?"],
                run_id=uuid4(),
            )

        events = r.event_log.read_all()
        op_started = [e for e in events if e["event_type"] == "op_started"]
        payload = op_started[0]["payload"]
        assert payload["op_version"] == "claude-haiku-4-5-20251001"

    def test_prompt_hashed_as_input_artifact(self, config: LiminaraConfig):
        """Prompt is stored as an artifact and its hash appears in input_hashes."""
        handler = LiminaraCallbackHandler()

        with run("test-pack", "1.0.0", config=config) as r:
            handler.on_llm_start(
                serialized=_serialized_chat_anthropic(),
                prompts=["What is Article 12?"],
                run_id=uuid4(),
            )

        events = r.event_log.read_all()
        op_started = [e for e in events if e["event_type"] == "op_started"]
        input_hashes = op_started[0]["payload"]["input_hashes"]
        assert len(input_hashes) == 1
        assert input_hashes[0].startswith("sha256:")

        # Artifact should be retrievable
        content = r.artifact_store.read(input_hashes[0])
        assert b"What is Article 12?" in content


class TestLLMEndEvent:
    """on_llm_end emits decision_recorded and op_completed events."""

    def _run_llm_lifecycle(self, config: LiminaraConfig) -> tuple[Any, LiminaraCallbackHandler]:
        """Helper: run a full LLM start→end cycle, return (run_ctx, handler)."""
        handler = LiminaraCallbackHandler()
        lc_run_id = uuid4()

        with run("test-pack", "1.0.0", config=config) as r:
            handler.on_llm_start(
                serialized=_serialized_chat_anthropic(),
                prompts=["What is Article 12?"],
                run_id=lc_run_id,
            )
            handler.on_llm_end(
                response=_llm_result_with_usage(),
                run_id=lc_run_id,
            )

        return r, handler

    def test_decision_recorded_emitted(self, config: LiminaraConfig):
        """on_llm_end emits a decision_recorded event."""
        r, _ = self._run_llm_lifecycle(config)

        events = r.event_log.read_all()
        decision_events = [e for e in events if e["event_type"] == "decision_recorded"]
        assert len(decision_events) == 1
        assert decision_events[0]["payload"]["decision_type"] == "llm_response"

    def test_op_completed_emitted(self, config: LiminaraConfig):
        """on_llm_end emits an op_completed event after decision_recorded."""
        r, _ = self._run_llm_lifecycle(config)

        events = r.event_log.read_all()
        types = [e["event_type"] for e in events]
        assert "decision_recorded" in types
        assert "op_completed" in types
        # decision_recorded should come before op_completed
        assert types.index("decision_recorded") < types.index("op_completed")

    def test_decision_contains_model_id(self, config: LiminaraConfig):
        """Decision record contains the model ID."""
        r, _ = self._run_llm_lifecycle(config)

        events = r.event_log.read_all()
        decision_events = [e for e in events if e["event_type"] == "decision_recorded"]
        node_id = decision_events[0]["payload"]["node_id"]

        record = r.decision_store.read(node_id)
        assert record["op_version"] == "claude-haiku-4-5-20251001"

    def test_decision_contains_token_usage(self, config: LiminaraConfig):
        """Decision record captures token usage from LLM response."""
        r, _ = self._run_llm_lifecycle(config)

        events = r.event_log.read_all()
        decision_events = [e for e in events if e["event_type"] == "decision_recorded"]
        node_id = decision_events[0]["payload"]["node_id"]

        record = r.decision_store.read(node_id)
        assert record["inputs"]["token_usage"]["input_tokens"] == 25
        assert record["inputs"]["token_usage"]["output_tokens"] == 12

    def test_response_hashed_as_output_artifact(self, config: LiminaraConfig):
        """LLM response is stored as artifact and appears in op_completed output_hashes."""
        r, _ = self._run_llm_lifecycle(config)

        events = r.event_log.read_all()
        op_completed = [e for e in events if e["event_type"] == "op_completed"]
        assert len(op_completed) == 1
        output_hashes = op_completed[0]["payload"]["output_hashes"]
        assert len(output_hashes) == 1

        content = r.artifact_store.read(output_hashes[0])
        assert b"Article 12 requires logging" in content


class TestLLMErrorEvent:
    """on_llm_error emits op_failed event."""

    def test_op_failed_emitted(self, config: LiminaraConfig):
        """on_llm_error emits an op_failed event with error details."""
        handler = LiminaraCallbackHandler()
        lc_run_id = uuid4()

        with run("test-pack", "1.0.0", config=config) as r:
            handler.on_llm_start(
                serialized=_serialized_chat_anthropic(),
                prompts=["What is Article 12?"],
                run_id=lc_run_id,
            )
            handler.on_llm_error(
                error=Exception("API rate limit exceeded"),
                run_id=lc_run_id,
            )

        events = r.event_log.read_all()
        op_failed = [e for e in events if e["event_type"] == "op_failed"]
        assert len(op_failed) == 1
        assert op_failed[0]["payload"]["error_type"] == "Exception"
        assert "rate limit" in op_failed[0]["payload"]["error_message"]


class TestChainEvents:
    """on_chain_start/end/error emit op events."""

    def test_chain_start_emits_op_started(self, config: LiminaraConfig):
        """on_chain_start emits an op_started event with chain name."""
        handler = LiminaraCallbackHandler()

        with run("test-pack", "1.0.0", config=config) as r:
            handler.on_chain_start(
                serialized=_serialized_chain(),
                inputs={"query": "What is Article 12?"},
                run_id=uuid4(),
            )

        events = r.event_log.read_all()
        op_started = [e for e in events if e["event_type"] == "op_started"]
        assert len(op_started) == 1
        assert op_started[0]["payload"]["op_id"] == "chain"

    def test_chain_end_emits_op_completed(self, config: LiminaraConfig):
        """on_chain_end emits an op_completed event with output hashes."""
        handler = LiminaraCallbackHandler()
        lc_run_id = uuid4()

        with run("test-pack", "1.0.0", config=config) as r:
            handler.on_chain_start(
                serialized=_serialized_chain(),
                inputs={"query": "What is Article 12?"},
                run_id=lc_run_id,
            )
            handler.on_chain_end(
                outputs={"result": "Article 12 requires..."},
                run_id=lc_run_id,
            )

        events = r.event_log.read_all()
        op_completed = [e for e in events if e["event_type"] == "op_completed"]
        assert len(op_completed) == 1
        assert op_completed[0]["payload"]["output_hashes"]

    def test_chain_error_emits_op_failed(self, config: LiminaraConfig):
        """on_chain_error emits an op_failed event."""
        handler = LiminaraCallbackHandler()
        lc_run_id = uuid4()

        with run("test-pack", "1.0.0", config=config) as r:
            handler.on_chain_start(
                serialized=_serialized_chain(),
                inputs={"query": "What is Article 12?"},
                run_id=lc_run_id,
            )
            handler.on_chain_error(
                error=ValueError("Chain broke"),
                run_id=lc_run_id,
            )

        events = r.event_log.read_all()
        op_failed = [e for e in events if e["event_type"] == "op_failed"]
        assert len(op_failed) == 1
        assert op_failed[0]["payload"]["error_type"] == "ValueError"


class TestHashChain:
    """Hash chain remains valid after LangChain callback events."""

    def test_hash_chain_valid_after_llm_lifecycle(self, config: LiminaraConfig):
        """Hash chain is valid after a full LLM start → end cycle."""
        handler = LiminaraCallbackHandler()
        lc_run_id = uuid4()

        with run("test-pack", "1.0.0", config=config) as r:
            handler.on_llm_start(
                serialized=_serialized_chat_anthropic(),
                prompts=["What is Article 12?"],
                run_id=lc_run_id,
            )
            handler.on_llm_end(
                response=_llm_result_with_usage(),
                run_id=lc_run_id,
            )

        valid, error = r.event_log.verify()
        assert valid, f"Hash chain broken: {error}"

    def test_hash_chain_valid_after_chain_lifecycle(self, config: LiminaraConfig):
        """Hash chain is valid after chain start → end cycle."""
        handler = LiminaraCallbackHandler()
        lc_run_id = uuid4()

        with run("test-pack", "1.0.0", config=config) as r:
            handler.on_chain_start(
                serialized=_serialized_chain(),
                inputs={"query": "test"},
                run_id=lc_run_id,
            )
            handler.on_chain_end(
                outputs={"result": "answer"},
                run_id=lc_run_id,
            )

        valid, error = r.event_log.verify()
        assert valid, f"Hash chain broken: {error}"


class TestRunContext:
    """Handler works with and without explicit run context."""

    def test_works_with_explicit_run_context(self, config: LiminaraConfig):
        """Handler emits events into an existing run context."""
        handler = LiminaraCallbackHandler()

        with run("test-pack", "1.0.0", config=config) as r:
            handler.on_llm_start(
                serialized=_serialized_chat_anthropic(),
                prompts=["test"],
                run_id=uuid4(),
            )

        events = r.event_log.read_all()
        # run_started + op_started + run_completed
        assert len(events) == 3
        assert events[0]["event_type"] == "run_started"
        assert events[1]["event_type"] == "op_started"
        assert events[2]["event_type"] == "run_completed"

    def test_works_without_run_context(self, config: LiminaraConfig, tmp_path: Path):
        """Handler creates its own run context when used standalone."""
        handler = LiminaraCallbackHandler(config=config)
        lc_run_id = uuid4()

        handler.on_llm_start(
            serialized=_serialized_chat_anthropic(),
            prompts=["test"],
            run_id=lc_run_id,
        )
        handler.on_llm_end(
            response=_llm_result_with_usage(),
            run_id=lc_run_id,
        )

        # Handler should have created a run and recorded events
        assert handler.run_context is not None
        events = handler.run_context.event_log.read_all()
        assert any(e["event_type"] == "op_started" for e in events)
        assert any(e["event_type"] == "decision_recorded" for e in events)

    def test_multiple_handlers_share_run(self, config: LiminaraConfig):
        """Multiple handlers in the same run produce events in the same log."""
        handler1 = LiminaraCallbackHandler()
        handler2 = LiminaraCallbackHandler()

        with run("test-pack", "1.0.0", config=config) as r:
            handler1.on_llm_start(
                serialized=_serialized_chat_anthropic(),
                prompts=["question 1"],
                run_id=uuid4(),
            )
            handler2.on_llm_start(
                serialized=_serialized_chat_anthropic(),
                prompts=["question 2"],
                run_id=uuid4(),
            )

        events = r.event_log.read_all()
        op_started = [e for e in events if e["event_type"] == "op_started"]
        assert len(op_started) == 2


class TestMultipleLLMCalls:
    """Multiple LLM calls in one run produce sequential events."""

    def test_sequential_events_with_valid_chain(self, config: LiminaraConfig):
        """Multiple LLM calls produce sequential events with valid hash chain."""
        handler = LiminaraCallbackHandler()

        with run("test-pack", "1.0.0", config=config) as r:
            for i in range(3):
                lc_run_id = uuid4()
                handler.on_llm_start(
                    serialized=_serialized_chat_anthropic(),
                    prompts=[f"Question {i}"],
                    run_id=lc_run_id,
                )
                handler.on_llm_end(
                    response=_llm_result_with_usage(),
                    run_id=lc_run_id,
                )

        events = r.event_log.read_all()
        # run_started + 3*(op_started + decision_recorded + op_completed) + run_completed
        assert len(events) == 11

        valid, error = r.event_log.verify()
        assert valid, f"Hash chain broken: {error}"

    def test_node_ids_increment(self, config: LiminaraConfig):
        """Each LLM call gets a unique incrementing node_id."""
        handler = LiminaraCallbackHandler()

        with run("test-pack", "1.0.0", config=config) as r:
            for _ in range(3):
                lc_run_id = uuid4()
                handler.on_llm_start(
                    serialized=_serialized_chat_anthropic(),
                    prompts=["test"],
                    run_id=lc_run_id,
                )
                handler.on_llm_end(
                    response=_llm_result_with_usage(),
                    run_id=lc_run_id,
                )

        events = r.event_log.read_all()
        op_started = [e for e in events if e["event_type"] == "op_started"]
        node_ids = [e["payload"]["node_id"] for e in op_started]
        assert node_ids == ["llm-001", "llm-002", "llm-003"]
