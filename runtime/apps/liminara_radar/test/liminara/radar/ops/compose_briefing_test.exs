defmodule Liminara.Radar.Ops.ComposeBriefingTest do
  use ExUnit.Case, async: true

  alias Liminara.Radar.Ops.ComposeBriefing

  @sample_clusters Jason.encode!([
                     %{
                       "cluster_id" => "c0",
                       "label" => "AI News",
                       "cluster_score" => 1.5,
                       "items" => [
                         %{
                           "id" => "a1",
                           "title" => "AI breakthrough",
                           "url" => "https://a.com",
                           "source_id" => "s1",
                           "novelty_score" => 0.9
                         },
                         %{
                           "id" => "a2",
                           "title" => "AI update",
                           "url" => "https://b.com",
                           "source_id" => "s2",
                           "novelty_score" => 0.5
                         }
                       ]
                     },
                     %{
                       "cluster_id" => "c1",
                       "label" => "Elixir Updates",
                       "cluster_score" => 1.2,
                       "items" => [
                         %{
                           "id" => "b1",
                           "title" => "Elixir 2.0",
                           "url" => "https://c.com",
                           "source_id" => "s3",
                           "novelty_score" => 0.8
                         }
                       ]
                     }
                   ])

  @sample_summaries Jason.encode!([
                      %{
                        "cluster_id" => "c0",
                        "summary" => "AI is advancing rapidly.",
                        "key_takeaways" => ["Breakthrough in reasoning", "Cost reduction"]
                      },
                      %{
                        "cluster_id" => "c1",
                        "summary" => "Elixir hits version 2.",
                        "key_takeaways" => ["Major release"]
                      }
                    ])

  @sample_health Jason.encode!([
                   %{"source_id" => "s1", "items_fetched" => 5, "error" => nil},
                   %{"source_id" => "s2", "items_fetched" => 3, "error" => nil},
                   %{"source_id" => "s3", "items_fetched" => 0, "error" => "timeout"}
                 ])

  describe "ComposeBriefing" do
    test "assembles briefing with all expected fields" do
      {:ok, outputs} =
        ComposeBriefing.execute(%{
          "ranked_clusters" => @sample_clusters,
          "summaries" => @sample_summaries,
          "source_health" => @sample_health,
          "run_id" => "run_001",
          "date" => "2026-04-02"
        })

      briefing = Jason.decode!(outputs["briefing"])

      assert briefing["run_id"] == "run_001"
      assert briefing["date"] == "2026-04-02"
      assert briefing["stats"]["cluster_count"] == 2
      assert briefing["stats"]["item_count"] == 3
      assert briefing["stats"]["source_count"] == 3
      assert is_list(briefing["clusters"])
      assert length(briefing["clusters"]) == 2
    end

    test "clusters are in ranked order" do
      {:ok, outputs} =
        ComposeBriefing.execute(%{
          "ranked_clusters" => @sample_clusters,
          "summaries" => @sample_summaries,
          "source_health" => @sample_health,
          "run_id" => "run_001",
          "date" => "2026-04-02"
        })

      briefing = Jason.decode!(outputs["briefing"])
      cluster_ids = Enum.map(briefing["clusters"], & &1["cluster_id"])
      assert cluster_ids == ["c0", "c1"]
    end

    test "items within clusters are in ranked order" do
      {:ok, outputs} =
        ComposeBriefing.execute(%{
          "ranked_clusters" => @sample_clusters,
          "summaries" => @sample_summaries,
          "source_health" => @sample_health,
          "run_id" => "run_001",
          "date" => "2026-04-02"
        })

      briefing = Jason.decode!(outputs["briefing"])
      first_cluster = hd(briefing["clusters"])
      item_ids = Enum.map(first_cluster["items"], & &1["id"])
      assert item_ids == ["a1", "a2"]
    end

    test "summaries are attached to clusters" do
      {:ok, outputs} =
        ComposeBriefing.execute(%{
          "ranked_clusters" => @sample_clusters,
          "summaries" => @sample_summaries,
          "source_health" => @sample_health,
          "run_id" => "run_001",
          "date" => "2026-04-02"
        })

      briefing = Jason.decode!(outputs["briefing"])
      first = hd(briefing["clusters"])
      assert first["summary"] == "AI is advancing rapidly."
      assert first["key_takeaways"] == ["Breakthrough in reasoning", "Cost reduction"]
    end

    test "source health included" do
      {:ok, outputs} =
        ComposeBriefing.execute(%{
          "ranked_clusters" => @sample_clusters,
          "summaries" => @sample_summaries,
          "source_health" => @sample_health,
          "run_id" => "run_001",
          "date" => "2026-04-02"
        })

      briefing = Jason.decode!(outputs["briefing"])
      assert is_list(briefing["source_health"])
      assert length(briefing["source_health"]) == 3
    end

    test "empty clusters produce valid briefing" do
      {:ok, outputs} =
        ComposeBriefing.execute(%{
          "ranked_clusters" => Jason.encode!([]),
          "summaries" => Jason.encode!([]),
          "source_health" => Jason.encode!([]),
          "run_id" => "run_empty",
          "date" => "2026-04-02"
        })

      briefing = Jason.decode!(outputs["briefing"])
      assert briefing["clusters"] == []
      assert briefing["stats"]["cluster_count"] == 0
      assert briefing["stats"]["item_count"] == 0
    end
  end

  describe "Op behaviour" do
    test "name" do
      assert ComposeBriefing.name() == "compose_briefing"
    end

    test "determinism is pure" do
      assert ComposeBriefing.determinism() == :pure
    end
  end
end
