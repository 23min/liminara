defmodule Liminara.ExecutionContractStructsTest do
  use ExUnit.Case, async: true

  alias Liminara.{ExecutionContext, ExecutionSpec, OpResult, Warning}

  test "ExecutionSpec has canonical section defaults" do
    spec = ExecutionSpec.new()

    assert %ExecutionSpec.Identity{} = spec.identity
    assert %ExecutionSpec.Determinism{} = spec.determinism
    assert %ExecutionSpec.Execution{} = spec.execution
    assert %ExecutionSpec.Isolation{} = spec.isolation
    assert %ExecutionSpec.Contracts{} = spec.contracts

    assert spec.determinism.class == nil
    assert spec.determinism.cache_policy == nil
    assert spec.determinism.replay_policy == nil
    assert spec.execution.executor == nil
    assert spec.execution.entrypoint == nil
    assert spec.execution.timeout_ms == nil
    assert spec.execution.requires_execution_context == false
    assert spec.isolation.env_vars == []
    assert spec.isolation.network == :none
    assert spec.contracts.inputs == %{}
    assert spec.contracts.outputs == %{}
    assert spec.contracts.decisions == %{may_emit: false}
    assert spec.contracts.warnings == %{may_emit: false}
  end

  test "ExecutionSpec normalizes nested section maps into canonical structs" do
    spec =
      ExecutionSpec.new(%{
        identity: %{name: "radar_summarize", version: "0.1.0"},
        determinism: %{
          class: :recordable,
          cache_policy: :content_addressed,
          replay_policy: :replay_required
        },
        execution: %{
          executor: :port,
          entrypoint: "radar_summarize",
          timeout_ms: 30_000,
          requires_execution_context: true
        },
        isolation: %{
          env_vars: ["ANTHROPIC_API_KEY"],
          network: :tcp_outbound,
          bootstrap_read_paths: [:op_code, :runtime_deps],
          runtime_read_paths: [],
          runtime_write_paths: []
        },
        contracts: %{
          inputs: %{items: :artifact},
          outputs: %{summary: :artifact},
          decisions: %{may_emit: true},
          warnings: %{may_emit: true}
        }
      })

    assert %ExecutionSpec.Identity{name: "radar_summarize", version: "0.1.0"} = spec.identity

    assert %ExecutionSpec.Determinism{
             class: :recordable,
             cache_policy: :content_addressed,
             replay_policy: :replay_required
           } = spec.determinism

    assert %ExecutionSpec.Execution{
             executor: :port,
             entrypoint: "radar_summarize",
             timeout_ms: 30_000,
             requires_execution_context: true
           } = spec.execution

    assert %ExecutionSpec.Isolation{
             env_vars: ["ANTHROPIC_API_KEY"],
             network: :tcp_outbound,
             bootstrap_read_paths: [:op_code, :runtime_deps],
             runtime_read_paths: [],
             runtime_write_paths: []
           } = spec.isolation

    assert %ExecutionSpec.Contracts{
             inputs: %{items: :artifact},
             outputs: %{summary: :artifact},
             decisions: %{may_emit: true},
             warnings: %{may_emit: true}
           } = spec.contracts
  end

  test "OpResult defaults to empty decisions and warnings" do
    result = %OpResult{}

    assert result.outputs == %{}
    assert result.decisions == []
    assert result.warnings == []
  end

  test "Warning supports affected_outputs list" do
    warning = %Warning{code: "radar_placeholder_summary", severity: :degraded}

    assert warning.code == "radar_placeholder_summary"
    assert warning.severity == :degraded
    assert warning.affected_outputs == []
  end

  test "ExecutionContext carries runtime identity fields" do
    context =
      %ExecutionContext{
        run_id: "run_123",
        started_at: "2026-04-03T12:00:00Z",
        pack_id: "radar",
        pack_version: "0.1.0"
      }

    assert context.run_id == "run_123"
    assert context.started_at == "2026-04-03T12:00:00Z"
    assert context.pack_id == "radar"
    assert context.pack_version == "0.1.0"
    assert context.replay_of_run_id == nil
    assert context.topic_id == nil
  end
end
