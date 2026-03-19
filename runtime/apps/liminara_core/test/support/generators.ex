defmodule Liminara.Generators do
  @moduledoc "StreamData generators for property-based testing of the Liminara runtime."

  use ExUnitProperties

  alias Liminara.Plan

  # Only ops that take "text" input and produce "result" output
  @ops [
    Liminara.TestOps.Upcase,
    Liminara.TestOps.Reverse
  ]

  @failing_ops [
    Liminara.TestOps.Raise
  ]

  @doc """
  Generate a random valid DAG plan.

  Builds layer by layer — each layer's nodes can only reference nodes in
  previous layers, guaranteeing acyclicity by construction.
  """
  def dag_plan(opts \\ []) do
    max_depth = Keyword.get(opts, :max_depth, 5)
    max_width = Keyword.get(opts, :max_width, 5)
    include_failures = Keyword.get(opts, :include_failures, false)

    ops = if include_failures, do: @ops ++ @failing_ops, else: @ops

    gen all(
          depth <- integer(1..max_depth),
          widths <- list_of(integer(1..max_width), length: depth)
        ) do
      build_dag(widths, ops)
    end
  end

  defp build_dag(widths, ops) do
    {plan, _all_nodes} =
      widths
      |> Enum.with_index()
      |> Enum.reduce({Plan.new(), []}, fn {width, layer_idx}, {plan, prev_nodes} ->
        layer_nodes =
          for i <- 0..(width - 1) do
            "n_#{layer_idx}_#{i}"
          end

        plan =
          Enum.reduce(layer_nodes, plan, fn node_id, plan ->
            op = Enum.random(ops)
            inputs = build_inputs(prev_nodes, layer_idx)
            Plan.add_node(plan, node_id, op, inputs)
          end)

        {plan, prev_nodes ++ layer_nodes}
      end)

    plan
  end

  defp build_inputs([], _layer_idx) do
    # First layer: use literals
    %{"text" => {:literal, "input_#{:rand.uniform(1000)}"}}
  end

  defp build_inputs(prev_nodes, _layer_idx) do
    # Pick a random previous node as input
    ref_node = Enum.random(prev_nodes)
    %{"text" => {:ref, ref_node, "result"}}
  end
end
