defmodule Liminara.Radar.Ops.ComposeBriefing do
  @behaviour Liminara.Op

  @impl true
  def name, do: "compose_briefing"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(inputs) do
    clusters = Jason.decode!(inputs["ranked_clusters"])
    summaries = Jason.decode!(inputs["summaries"])
    source_health = Jason.decode!(inputs["source_health"])
    run_id = inputs["run_id"]
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
      "run_id" => run_id,
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
