defmodule Liminara.Radar.OpContractTest do
  use ExUnit.Case, async: true

  alias Liminara.Op
  alias Liminara.Radar.Ops

  @expectations %{
    Ops.FetchRss => %{class: :side_effecting, executor: :port, entrypoint: "radar_fetch_rss"},
    Ops.FetchWeb => %{class: :side_effecting, executor: :port, entrypoint: "radar_fetch_web"},
    Ops.CollectItems => %{class: :pure, executor: :inline, entrypoint: "collect_items"},
    Ops.Normalize => %{class: :pure, executor: :port, entrypoint: "radar_normalize"},
    Ops.Embed => %{class: :pinned_env, executor: :port, entrypoint: "radar_embed"},
    Ops.Dedup => %{
      class: :side_effecting,
      executor: :port,
      entrypoint: "radar_dedup",
      requires_execution_context: true
    },
    Ops.LlmDedupCheck => %{class: :recordable, executor: :port, entrypoint: "radar_llm_dedup"},
    Ops.MergeResults => %{class: :pure, executor: :inline, entrypoint: "merge_results"},
    Ops.Cluster => %{class: :pure, executor: :port, entrypoint: "radar_cluster"},
    Ops.Rank => %{class: :pure, executor: :port, entrypoint: "radar_rank"},
    Ops.Summarize => %{class: :recordable, executor: :port, entrypoint: "radar_summarize"},
    Ops.ComposeBriefing => %{
      class: :pure,
      executor: :inline,
      entrypoint: "compose_briefing",
      requires_execution_context: true
    },
    Ops.RenderHtml => %{class: :pure, executor: :inline, entrypoint: "render_html"}
  }

  test "all Radar ops in the pack export explicit execution specs" do
    for {op_module, expected} <- @expectations do
      assert {:module, ^op_module} = Code.ensure_loaded(op_module)

      assert function_exported?(op_module, :execution_spec, 0),
             "#{inspect(op_module)} should export execution_spec/0"

      spec = Op.execution_spec(op_module)

      assert spec.identity.name == op_module.name()
      assert spec.identity.version == op_module.version()
      assert spec.determinism.class == expected.class
      assert spec.execution.executor == expected.executor
      assert spec.execution.entrypoint == expected.entrypoint

      assert spec.execution.requires_execution_context ==
               Map.get(expected, :requires_execution_context, false)
    end
  end

  test "recordable and side-effecting Radar specs keep truthful replay boundaries" do
    dedup = Op.execution_spec(Ops.Dedup)
    summarize = Op.execution_spec(Ops.Summarize)
    llm_dedup = Op.execution_spec(Ops.LlmDedupCheck)
    fetch_rss = Op.execution_spec(Ops.FetchRss)
    fetch_web = Op.execution_spec(Ops.FetchWeb)

    assert dedup.determinism.cache_policy == :none
    assert dedup.determinism.replay_policy == :replay_recorded

    assert summarize.determinism.cache_policy == :none
    assert summarize.determinism.replay_policy == :replay_recorded

    assert llm_dedup.determinism.cache_policy == :none
    assert llm_dedup.determinism.replay_policy == :replay_recorded

    assert fetch_rss.determinism.cache_policy == :none
    assert fetch_rss.determinism.replay_policy == :skip

    assert fetch_web.determinism.cache_policy == :none
    assert fetch_web.determinism.replay_policy == :skip
  end

  test "Radar ops no longer export legacy execution hint callbacks" do
    port_ops = [
      Ops.FetchRss,
      Ops.FetchWeb,
      Ops.Normalize,
      Ops.Embed,
      Ops.Dedup,
      Ops.LlmDedupCheck,
      Ops.Cluster,
      Ops.Rank,
      Ops.Summarize
    ]

    for op_module <- port_ops do
      assert {:module, ^op_module} = Code.ensure_loaded(op_module)

      refute function_exported?(op_module, :executor, 0),
             "#{inspect(op_module)} should not export legacy executor/0"

      refute function_exported?(op_module, :python_op, 0),
             "#{inspect(op_module)} should not export legacy python_op/0"

      refute function_exported?(op_module, :env_vars, 0),
             "#{inspect(op_module)} should not export legacy env_vars/0"
    end
  end
end
