"""LangChain callback handler integration for Liminara event recording."""

from __future__ import annotations

import time
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from langchain_core.callbacks import BaseCallbackHandler
from langchain_core.outputs import ChatGeneration, LLMResult

from liminara.config import LiminaraConfig
from liminara.hash import canonical_json
from liminara.run import RunContext, get_current_run, run


class LiminaraCallbackHandler(BaseCallbackHandler):
    """Records Liminara events for LangChain LLM and chain calls.

    Usage:
        # Inside an existing run context:
        handler = LiminaraCallbackHandler()
        result = llm.invoke("...", config={"callbacks": [handler]})

        # Standalone (creates its own run):
        handler = LiminaraCallbackHandler(config=LiminaraConfig())
        result = llm.invoke("...", config={"callbacks": [handler]})
    """

    def __init__(self, config: LiminaraConfig | None = None) -> None:
        super().__init__()
        self.config = config
        self.run_context: RunContext | None = None
        # Map LangChain run_id → (node_id, start_time) for correlating start/end
        self._active_llms: dict[UUID, tuple[str, float]] = {}
        self._active_chains: dict[UUID, tuple[str, float]] = {}
        # For standalone mode
        self._own_run_cm: Any = None

    def _get_run_context(self) -> RunContext:
        """Get active run context, creating one if standalone."""
        ctx = get_current_run()
        if ctx is not None:
            return ctx

        if self.run_context is not None:
            return self.run_context

        # Standalone: create our own run
        if self.config is None:
            self.config = LiminaraConfig()
        self._own_run_cm = run("langchain", "0.0.0", config=self.config)
        self.run_context = self._own_run_cm.__enter__()
        return self.run_context

    def _extract_model_id(self, serialized: dict[str, Any]) -> str:
        """Extract model ID from LangChain's serialized config."""
        kwargs = serialized.get("kwargs", {})
        return kwargs.get("model", kwargs.get("model_name", "unknown"))

    def _extract_chain_name(self, serialized: dict[str, Any]) -> str:
        """Extract chain name from serialized config."""
        ids = serialized.get("id", [])
        if ids:
            return ids[-1]
        return "chain"

    # -- LLM callbacks --

    def on_llm_start(
        self,
        serialized: dict[str, Any],
        prompts: list[str],
        *,
        run_id: UUID,
        **kwargs: Any,
    ) -> None:
        ctx = self._get_run_context()
        model_id = self._extract_model_id(serialized)
        node_id = ctx.next_node_id("llm")

        # Store prompt as artifact
        prompt_bytes = canonical_json(prompts)
        input_hash = ctx.artifact_store.write(prompt_bytes)
        ctx.track_artifact(input_hash)

        ctx.event_log.append(
            event_type="op_started",
            payload={
                "node_id": node_id,
                "op_id": "llm",
                "op_version": model_id,
                "determinism": "recordable",
                "input_hashes": [input_hash],
            },
        )

        self._active_llms[run_id] = (node_id, time.perf_counter())

    def on_llm_end(
        self,
        response: LLMResult,
        *,
        run_id: UUID,
        **kwargs: Any,
    ) -> None:
        ctx = self._get_run_context()
        node_id, start_time = self._active_llms.pop(run_id)
        duration_ms = (time.perf_counter() - start_time) * 1000

        # Extract response text and metadata
        generation = response.generations[0][0]
        if isinstance(generation, ChatGeneration):
            response_text = generation.message.content
        else:
            response_text = generation.text

        # Extract model ID and token usage from llm_output
        llm_output = response.llm_output or {}
        model_id = llm_output.get("model", "unknown")
        token_usage = llm_output.get("usage", {})

        # Store response as artifact
        response_bytes = canonical_json(response_text)
        output_hash = ctx.artifact_store.write(response_bytes)
        ctx.track_artifact(output_hash)

        # Store prompt hash (from the op_started event)
        events = ctx.event_log.read_all()
        op_started = [
            e
            for e in events
            if e["event_type"] == "op_started" and e["payload"]["node_id"] == node_id
        ]
        prompt_hash = op_started[0]["payload"]["input_hashes"][0] if op_started else None

        # Record decision
        timestamp = (
            datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%S.")
            + f"{datetime.now(UTC).microsecond // 1000:03d}Z"
        )
        record = {
            "node_id": node_id,
            "op_id": "llm",
            "op_version": model_id,
            "decision_type": "llm_response",
            "inputs": {
                "args_hash": prompt_hash,
                "token_usage": token_usage,
            },
            "output": {
                "result_hash": output_hash,
            },
            "recorded_at": timestamp,
        }
        decision_hash = ctx.decision_store.write(record)

        ctx.event_log.append(
            event_type="decision_recorded",
            payload={
                "node_id": node_id,
                "decision_hash": decision_hash,
                "decision_type": "llm_response",
            },
        )

        ctx.event_log.append(
            event_type="op_completed",
            payload={
                "node_id": node_id,
                "output_hashes": [output_hash],
                "cache_hit": False,
                "duration_ms": duration_ms,
            },
        )

    def on_llm_error(
        self,
        error: BaseException,
        *,
        run_id: UUID,
        **kwargs: Any,
    ) -> None:
        ctx = self._get_run_context()
        node_id, _ = self._active_llms.pop(run_id, ("unknown", 0))

        ctx.event_log.append(
            event_type="op_failed",
            payload={
                "node_id": node_id,
                "error_type": type(error).__name__,
                "error_message": str(error),
            },
        )

    # -- Chain callbacks --

    def on_chain_start(
        self,
        serialized: dict[str, Any],
        inputs: dict[str, Any],
        *,
        run_id: UUID,
        **kwargs: Any,
    ) -> None:
        ctx = self._get_run_context()
        chain_name = self._extract_chain_name(serialized)
        node_id = ctx.next_node_id("chain")

        input_bytes = canonical_json(inputs)
        input_hash = ctx.artifact_store.write(input_bytes)
        ctx.track_artifact(input_hash)

        ctx.event_log.append(
            event_type="op_started",
            payload={
                "node_id": node_id,
                "op_id": "chain",
                "op_version": chain_name,
                "determinism": "recordable",
                "input_hashes": [input_hash],
            },
        )

        self._active_chains[run_id] = (node_id, time.perf_counter())

    def on_chain_end(
        self,
        outputs: dict[str, Any],
        *,
        run_id: UUID,
        **kwargs: Any,
    ) -> None:
        ctx = self._get_run_context()
        node_id, start_time = self._active_chains.pop(run_id)
        duration_ms = (time.perf_counter() - start_time) * 1000

        output_bytes = canonical_json(outputs)
        output_hash = ctx.artifact_store.write(output_bytes)
        ctx.track_artifact(output_hash)

        ctx.event_log.append(
            event_type="op_completed",
            payload={
                "node_id": node_id,
                "output_hashes": [output_hash],
                "cache_hit": False,
                "duration_ms": duration_ms,
            },
        )

    def on_chain_error(
        self,
        error: BaseException,
        *,
        run_id: UUID,
        **kwargs: Any,
    ) -> None:
        ctx = self._get_run_context()
        node_id, _ = self._active_chains.pop(run_id, ("unknown", 0))

        ctx.event_log.append(
            event_type="op_failed",
            payload={
                "node_id": node_id,
                "error_type": type(error).__name__,
                "error_message": str(error),
            },
        )
