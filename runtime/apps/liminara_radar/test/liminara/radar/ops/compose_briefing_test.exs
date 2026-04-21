defmodule Liminara.Radar.Ops.ComposeBriefingTest do
  use ExUnit.Case, async: true

  alias Liminara.{ExecutionContext, Op}
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
                        "key_takeaways" => ["Breakthrough in reasoning", "Cost reduction"],
                        "degraded" => false,
                        "degradation_code" => nil,
                        "degradation_note" => nil
                      },
                      %{
                        "cluster_id" => "c1",
                        "summary" => "Elixir hits version 2.",
                        "key_takeaways" => ["Major release"],
                        "degraded" => false,
                        "degradation_code" => nil,
                        "degradation_note" => nil
                      }
                    ])

  @sample_health Jason.encode!([
                   %{"source_id" => "s1", "items_fetched" => 5, "error" => nil},
                   %{"source_id" => "s2", "items_fetched" => 3, "error" => nil},
                   %{"source_id" => "s3", "items_fetched" => 0, "error" => "timeout"}
                 ])

  defp compose_briefing(opts \\ []) do
    ranked_clusters = Keyword.get(opts, :ranked_clusters, @sample_clusters)
    summaries = Keyword.get(opts, :summaries, @sample_summaries)
    source_health = Keyword.get(opts, :source_health, @sample_health)
    run_id = Keyword.get(opts, :run_id, "run_001")
    date = Keyword.get(opts, :date, "2026-04-02")

    ComposeBriefing.execute(
      %{
        "ranked_clusters" => ranked_clusters,
        "summaries" => summaries,
        "source_health" => source_health,
        "date" => date
      },
      %ExecutionContext{
        run_id: run_id,
        started_at: date <> "T12:00:00Z",
        pack_id: "radar",
        pack_version: "0.1.0",
        replay_of_run_id: nil,
        topic_id: nil
      }
    )
  end

  describe "ComposeBriefing" do
    test "assembles briefing with all expected fields" do
      {:ok, outputs} = compose_briefing()

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
      {:ok, outputs} = compose_briefing()

      briefing = Jason.decode!(outputs["briefing"])
      cluster_ids = Enum.map(briefing["clusters"], & &1["cluster_id"])
      assert cluster_ids == ["c0", "c1"]
    end

    test "items within clusters are in ranked order" do
      {:ok, outputs} = compose_briefing()

      briefing = Jason.decode!(outputs["briefing"])
      first_cluster = hd(briefing["clusters"])
      item_ids = Enum.map(first_cluster["items"], & &1["id"])
      assert item_ids == ["a1", "a2"]
    end

    test "summaries are attached to clusters" do
      {:ok, outputs} = compose_briefing()

      briefing = Jason.decode!(outputs["briefing"])
      first = hd(briefing["clusters"])
      assert first["summary"] == "AI is advancing rapidly."
      assert first["key_takeaways"] == ["Breakthrough in reasoning", "Cost reduction"]
    end

    test "source health included" do
      {:ok, outputs} = compose_briefing()

      briefing = Jason.decode!(outputs["briefing"])
      assert is_list(briefing["source_health"])
      assert length(briefing["source_health"]) == 3
    end

    test "empty clusters produce valid briefing" do
      {:ok, outputs} =
        compose_briefing(
          ranked_clusters: Jason.encode!([]),
          summaries: Jason.encode!([]),
          source_health: Jason.encode!([]),
          run_id: "run_empty"
        )

      briefing = Jason.decode!(outputs["briefing"])
      assert briefing["clusters"] == []
      assert briefing["stats"]["cluster_count"] == 0
      assert briefing["stats"]["item_count"] == 0
    end

    test "uses runtime execution context for run identity" do
      {:ok, outputs} = compose_briefing(run_id: "runtime-run-123")

      briefing = Jason.decode!(outputs["briefing"])
      assert briefing["run_id"] == "runtime-run-123"
    end
  end

  describe "ComposeBriefing degraded propagation" do
    test "all-success clusters: per-cluster false, root false, empty degraded_cluster_ids" do
      {:ok, outputs} = compose_briefing()

      briefing = Jason.decode!(outputs["briefing"])

      for cluster <- briefing["clusters"] do
        assert cluster["degraded"] == false
        assert cluster["degradation_code"] == nil
        assert cluster["degradation_note"] == nil
      end

      assert briefing["degraded"] == false
      assert briefing["degraded_cluster_ids"] == []
    end

    test "one degraded cluster: per-cluster flags set, root degraded true, list contains id" do
      mixed_summaries =
        Jason.encode!([
          %{
            "cluster_id" => "c0",
            "summary" => "AI is advancing rapidly.",
            "key_takeaways" => ["Breakthrough in reasoning"],
            "degraded" => false,
            "degradation_code" => nil,
            "degradation_note" => nil
          },
          %{
            "cluster_id" => "c1",
            "summary" => "Cluster 'Elixir Updates' contains 1 item(s): Elixir 2.0.",
            "key_takeaways" => ["Contains 1 related items"],
            "degraded" => true,
            "degradation_code" => "radar_summarize_placeholder",
            "degradation_note" =>
              "Using placeholder summaries because Anthropic access is unavailable"
          }
        ])

      {:ok, outputs} = compose_briefing(summaries: mixed_summaries)

      briefing = Jason.decode!(outputs["briefing"])
      [first, second] = briefing["clusters"]

      assert first["cluster_id"] == "c0"
      assert first["degraded"] == false
      assert first["degradation_code"] == nil
      assert first["degradation_note"] == nil

      assert second["cluster_id"] == "c1"
      assert second["degraded"] == true
      assert second["degradation_code"] == "radar_summarize_placeholder"

      assert second["degradation_note"] ==
               "Using placeholder summaries because Anthropic access is unavailable"

      assert briefing["degraded"] == true
      assert briefing["degraded_cluster_ids"] == ["c1"]
    end

    test "all degraded clusters: root degraded true, sorted id list" do
      all_degraded =
        Jason.encode!([
          %{
            "cluster_id" => "c0",
            "summary" => "Placeholder c0",
            "key_takeaways" => [],
            "degraded" => true,
            "degradation_code" => "radar_summarize_placeholder",
            "degradation_note" =>
              "Using placeholder summaries because Anthropic access is unavailable"
          },
          %{
            "cluster_id" => "c1",
            "summary" => "Placeholder c1",
            "key_takeaways" => [],
            "degraded" => true,
            "degradation_code" => "radar_summarize_llm_error",
            "degradation_note" => "Fell back to a placeholder summary after an LLM error"
          }
        ])

      {:ok, outputs} = compose_briefing(summaries: all_degraded)

      briefing = Jason.decode!(outputs["briefing"])

      for cluster <- briefing["clusters"] do
        assert cluster["degraded"] == true
      end

      assert briefing["degraded"] == true
      # sorted alphabetically
      assert briefing["degraded_cluster_ids"] == ["c0", "c1"]
    end

    test "zero clusters: root degraded false, empty degraded_cluster_ids, no crash" do
      {:ok, outputs} =
        compose_briefing(
          ranked_clusters: Jason.encode!([]),
          summaries: Jason.encode!([]),
          source_health: Jason.encode!([]),
          run_id: "run_empty_degraded"
        )

      briefing = Jason.decode!(outputs["briefing"])

      assert briefing["clusters"] == []
      assert briefing["degraded"] == false
      assert briefing["degraded_cluster_ids"] == []
    end

    test "degraded_cluster_ids is sorted regardless of summary input order" do
      unsorted =
        Jason.encode!([
          %{
            "cluster_id" => "c1",
            "summary" => "Placeholder c1",
            "key_takeaways" => [],
            "degraded" => true,
            "degradation_code" => "radar_summarize_placeholder",
            "degradation_note" =>
              "Using placeholder summaries because Anthropic access is unavailable"
          },
          %{
            "cluster_id" => "c0",
            "summary" => "Placeholder c0",
            "key_takeaways" => [],
            "degraded" => true,
            "degradation_code" => "radar_summarize_placeholder",
            "degradation_note" =>
              "Using placeholder summaries because Anthropic access is unavailable"
          }
        ])

      # Matches the cluster order (c0, c1) in @sample_clusters.
      {:ok, outputs} = compose_briefing(summaries: unsorted)

      briefing = Jason.decode!(outputs["briefing"])
      assert briefing["degraded_cluster_ids"] == ["c0", "c1"]
    end

    test "malformed summaries (missing degraded fields) raises" do
      malformed =
        Jason.encode!([
          %{
            "cluster_id" => "c0",
            "summary" => "AI is advancing rapidly.",
            "key_takeaways" => ["Breakthrough in reasoning"]
          },
          %{
            "cluster_id" => "c1",
            "summary" => "Elixir hits version 2.",
            "key_takeaways" => ["Major release"]
          }
        ])

      assert_raise KeyError, fn -> compose_briefing(summaries: malformed) end
    end

    test "malformed summaries (missing degradation_code) raises" do
      malformed =
        Jason.encode!([
          %{
            "cluster_id" => "c0",
            "summary" => "AI is advancing rapidly.",
            "key_takeaways" => ["Breakthrough in reasoning"],
            "degraded" => false,
            "degradation_note" => nil
          },
          %{
            "cluster_id" => "c1",
            "summary" => "Elixir hits version 2.",
            "key_takeaways" => ["Major release"],
            "degraded" => false,
            "degradation_note" => nil
          }
        ])

      assert_raise KeyError, fn -> compose_briefing(summaries: malformed) end
    end

    test "malformed summaries (missing degradation_note) raises" do
      malformed =
        Jason.encode!([
          %{
            "cluster_id" => "c0",
            "summary" => "AI is advancing rapidly.",
            "key_takeaways" => ["Breakthrough in reasoning"],
            "degraded" => false,
            "degradation_code" => nil
          },
          %{
            "cluster_id" => "c1",
            "summary" => "Elixir hits version 2.",
            "key_takeaways" => ["Major release"],
            "degraded" => false,
            "degradation_code" => nil
          }
        ])

      assert_raise KeyError, fn -> compose_briefing(summaries: malformed) end
    end

    test "malformed summaries (missing summary) raises" do
      malformed =
        Jason.encode!([
          %{
            "cluster_id" => "c0",
            "key_takeaways" => ["Breakthrough in reasoning"],
            "degraded" => false,
            "degradation_code" => nil,
            "degradation_note" => nil
          },
          %{
            "cluster_id" => "c1",
            "key_takeaways" => ["Major release"],
            "degraded" => false,
            "degradation_code" => nil,
            "degradation_note" => nil
          }
        ])

      assert_raise KeyError, fn -> compose_briefing(summaries: malformed) end
    end

    test "malformed summaries (missing key_takeaways) raises" do
      malformed =
        Jason.encode!([
          %{
            "cluster_id" => "c0",
            "summary" => "AI is advancing rapidly.",
            "degraded" => false,
            "degradation_code" => nil,
            "degradation_note" => nil
          },
          %{
            "cluster_id" => "c1",
            "summary" => "Elixir hits version 2.",
            "degraded" => false,
            "degradation_code" => nil,
            "degradation_note" => nil
          }
        ])

      assert_raise KeyError, fn -> compose_briefing(summaries: malformed) end
    end

    test "missing summary for a listed cluster raises (no silent default)" do
      only_c0 =
        Jason.encode!([
          %{
            "cluster_id" => "c0",
            "summary" => "AI is advancing rapidly.",
            "key_takeaways" => ["Breakthrough in reasoning"],
            "degraded" => false,
            "degradation_code" => nil,
            "degradation_note" => nil
          }
        ])

      assert_raise KeyError, fn -> compose_briefing(summaries: only_c0) end
    end
  end

  describe "Op behaviour" do
    test "name" do
      assert ComposeBriefing.name() == "compose_briefing"
    end

    test "execution spec requires runtime execution context" do
      spec = Op.execution_spec(ComposeBriefing)

      assert spec.identity.name == "compose_briefing"
      assert spec.determinism.class == :pure
      assert spec.execution.entrypoint == "compose_briefing"
      assert spec.execution.requires_execution_context == true
    end
  end
end
