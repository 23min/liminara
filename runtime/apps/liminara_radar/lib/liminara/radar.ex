defmodule Liminara.Radar do
  @moduledoc """
  Radar Pack — daily intelligence briefing pipeline.
  """

  @behaviour Liminara.Pack

  alias Liminara.Plan

  alias Liminara.Radar.Ops.{
    CollectItems,
    Dedup,
    Embed,
    FetchRss,
    FetchWeb,
    LlmDedupCheck,
    MergeResults,
    Normalize
  }

  @impl true
  def id, do: :radar

  @impl true
  def version, do: "0.1.0"

  @impl true
  def ops,
    do: [FetchRss, FetchWeb, CollectItems, Normalize, Embed, Dedup, LlmDedupCheck, MergeResults]

  @impl true
  def plan(sources) when is_list(sources) do
    plan = build_fetch_plan(sources)

    plan
    |> add_normalize()
    |> add_embed()
    |> add_dedup()
    |> add_llm_dedup_check()
    |> add_merge_results()
  end

  defp build_fetch_plan(sources) do
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
      |> Map.new(fn {node_id, _op, _src} ->
        {node_id, {:ref, node_id, "result"}}
      end)

    Plan.add_node(plan, "collect_items", CollectItems, collect_inputs)
  end

  defp add_normalize(plan) do
    Plan.add_node(plan, "normalize", Normalize, %{
      "items" => {:ref, "collect_items", "items"}
    })
  end

  defp add_embed(plan) do
    provider = Application.get_env(:liminara_radar, :embedding_provider, "model2vec")
    provider_config = Application.get_env(:liminara_radar, :embedding_config, %{})

    Plan.add_node(plan, "embed", Embed, %{
      "items" => {:ref, "normalize", "items"},
      "provider" => {:literal, provider},
      "provider_config" => {:literal, Jason.encode!(provider_config)}
    })
  end

  defp add_dedup(plan) do
    dims = Application.get_env(:liminara_radar, :embedding_dims, 256)

    Plan.add_node(plan, "dedup", Dedup, %{
      "items" => {:ref, "embed", "items"},
      "lancedb_path" => {:literal, lancedb_path()},
      "run_id" => {:literal, "placeholder"},
      "dims" => {:literal, Integer.to_string(dims)}
    })
  end

  defp add_llm_dedup_check(plan) do
    Plan.add_node(plan, "llm_dedup_check", LlmDedupCheck, %{
      "items" => {:ref, "dedup", "result"}
    })
  end

  defp add_merge_results(plan) do
    Plan.add_node(plan, "merge_results", MergeResults, %{
      "dedup_result" => {:ref, "dedup", "result"},
      "llm_kept_items" => {:ref, "llm_dedup_check", "items"}
    })
  end

  defp op_for_type("rss"), do: FetchRss
  defp op_for_type("web"), do: FetchWeb
  defp op_for_type("api"), do: FetchRss

  defp lancedb_path do
    Application.get_env(:liminara_radar, :lancedb_path) ||
      Path.expand("../../data/radar/lancedb", Application.app_dir(:liminara_core, "priv"))
  end
end
