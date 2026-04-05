defmodule Liminara.Radar.Ops.ComposeBriefing do
  @behaviour Liminara.Op

  alias Liminara.{ExecutionContext, ExecutionSpec}

  @impl true
  def name, do: "compose_briefing"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "compose_briefing", version: "1.0"},
      determinism: %{class: :pure, cache_policy: :content_addressed, replay_policy: :reexecute},
      execution: %{
        executor: :inline,
        entrypoint: "compose_briefing",
        requires_execution_context: true
      },
      contracts: %{outputs: %{briefing: :artifact}}
    })
  end

  @impl true
  def execute(_inputs) do
    raise "runtime execution context required"
  end

  @impl true
  def execute(inputs, %ExecutionContext{} = context) do
    clusters = Jason.decode!(inputs["ranked_clusters"])
    summaries = Jason.decode!(inputs["summaries"])
    source_health = Jason.decode!(inputs["source_health"])
    date = inputs["date"]

    summary_map = Map.new(summaries, fn s -> {s["cluster_id"], s} end)

    enriched_clusters =
      Enum.map(clusters, fn cluster ->
        summary_data = Map.get(summary_map, cluster["cluster_id"], %{})

        cluster
        |> Map.put("summary", summary_data["summary"] || "")
        |> Map.put("key_takeaways", summary_data["key_takeaways"] || [])
      end)

    item_count =
      Enum.reduce(enriched_clusters, 0, fn c, acc -> acc + length(c["items"]) end)

    briefing = %{
      "run_id" => context.run_id,
      "date" => date,
      "stats" => %{
        "cluster_count" => length(enriched_clusters),
        "item_count" => item_count,
        "source_count" => length(source_health)
      },
      "clusters" => enriched_clusters,
      "source_health" => source_health
    }

    {:ok, %{"briefing" => Jason.encode!(briefing)}}
  end
end
