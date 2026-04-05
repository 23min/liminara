defmodule Liminara.RadarReplayTestPack do
  @moduledoc """
  Test pack for full Radar pipeline replay testing.

  Builds a plan with cluster → rank → summarize → compose → render
  using literal fixture items. No network calls, no LanceDB, no embedding model.
  """

  @behaviour Liminara.Pack

  alias Liminara.Plan

  alias Liminara.Radar.Ops.{
    Cluster,
    Rank,
    Summarize,
    ComposeBriefing,
    RenderHtml
  }

  @impl true
  def id, do: :radar_replay_test

  @impl true
  def version, do: "0.1.0"

  @impl true
  def ops, do: [Cluster, Rank, Summarize, ComposeBriefing, RenderHtml]

  @impl true
  def plan(_input) do
    # 4 items across 2 topics with mock 32-dim embeddings
    items = [
      %{
        "id" => "a1",
        "title" => "AI breakthrough in reasoning",
        "clean_text" => "Researchers announce major advance in AI reasoning capabilities.",
        "url" => "https://test.example.com/ai1",
        "source_id" => "src_ai",
        "published" => "2026-04-01T10:00:00Z"
      },
      %{
        "id" => "a2",
        "title" => "New AI model released",
        "clean_text" => "A new large language model shows improved performance.",
        "url" => "https://test.example.com/ai2",
        "source_id" => "src_tech",
        "published" => "2026-04-01T09:00:00Z"
      },
      %{
        "id" => "b1",
        "title" => "Elixir 2.0 announced",
        "clean_text" => "The Elixir programming language reaches version 2.0.",
        "url" => "https://test.example.com/elixir1",
        "source_id" => "src_dev",
        "published" => "2026-04-01T08:00:00Z"
      },
      %{
        "id" => "b2",
        "title" => "Phoenix LiveView improvements",
        "clean_text" => "Phoenix framework gets major LiveView updates.",
        "url" => "https://test.example.com/elixir2",
        "source_id" => "src_dev",
        "published" => "2026-04-01T07:00:00Z"
      }
    ]

    # Mock embeddings: topic A items cluster together, topic B items cluster together
    topic_a_base = List.duplicate(1.0, 16) ++ List.duplicate(0.0, 16)
    topic_b_base = List.duplicate(0.0, 16) ++ List.duplicate(1.0, 16)

    embedded_items =
      Enum.zip(items, [topic_a_base, topic_a_base, topic_b_base, topic_b_base])
      |> Enum.map(fn {item, emb} -> Map.put(item, "embedding", emb) end)

    ref_time = "2026-04-01T12:00:00Z"

    Plan.new()
    |> Plan.add_node("cluster", Cluster, %{
      "items" => {:literal, Jason.encode!(items)},
      "embedded_items" => {:literal, Jason.encode!(embedded_items)}
    })
    |> Plan.add_node("rank", Rank, %{
      "clusters" => {:ref, "cluster", "clusters"},
      "history_basis" => {:literal, "none"},
      "reference_time" => {:literal, ref_time}
    })
    |> Plan.add_node("summarize", Summarize, %{
      "clusters" => {:ref, "rank", "ranked_clusters"}
    })
    |> Plan.add_node("compose_briefing", ComposeBriefing, %{
      "ranked_clusters" => {:ref, "rank", "ranked_clusters"},
      "summaries" => {:ref, "summarize", "summaries"},
      "source_health" => {:literal, Jason.encode!([])},
      "date" => {:literal, "2026-04-01"}
    })
    |> Plan.add_node("render_html", RenderHtml, %{
      "briefing" => {:ref, "compose_briefing", "briefing"}
    })
  end
end
