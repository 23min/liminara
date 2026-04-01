defmodule Liminara.Radar do
  @moduledoc """
  Radar Pack — daily intelligence briefing pipeline.
  """

  @behaviour Liminara.Pack

  alias Liminara.Plan
  alias Liminara.Radar.Ops.{CollectItems, FetchRss, FetchWeb}

  @impl true
  def id, do: :radar

  @impl true
  def version, do: "0.1.0"

  @impl true
  def ops, do: [FetchRss, FetchWeb, CollectItems]

  @impl true
  def plan(sources) when is_list(sources) do
    fetch_nodes =
      Enum.map(sources, fn source ->
        node_id = "fetch_#{source["id"]}"
        op_module = op_for_type(source["type"])
        {node_id, op_module, source}
      end)

    plan =
      Enum.reduce(fetch_nodes, Plan.new(), fn {node_id, op_module, source}, plan ->
        Plan.add_node(plan, node_id, op_module, %{
          "source" => {:literal, Jason.encode!(source)}
        })
      end)

    # Collect node references all fetch nodes
    collect_inputs =
      fetch_nodes
      |> Enum.with_index()
      |> Map.new(fn {{node_id, _op, _src}, _idx} ->
        {node_id, {:ref, node_id, "result"}}
      end)

    Plan.add_node(plan, "collect_items", CollectItems, collect_inputs)
  end

  defp op_for_type("rss"), do: FetchRss
  defp op_for_type("web"), do: FetchWeb
  defp op_for_type("api"), do: FetchRss
end
