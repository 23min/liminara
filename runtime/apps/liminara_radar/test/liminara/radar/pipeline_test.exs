defmodule Liminara.Radar.PipelineTest do
  @moduledoc """
  Integration test: cluster → rank → summarize → compose → render
  with fixture data. Verifies the full post-dedup pipeline produces
  a valid, readable HTML briefing containing expected content.
  """
  use ExUnit.Case, async: true

  alias Liminara.Radar.Ops.{ComposeBriefing, RenderHtml}

  # Fixture: 4 items across 2 topics, pre-clustered and ranked
  @clusters [
    %{
      "cluster_id" => "c0",
      "label" => "AI Advances",
      "cluster_score" => 1.8,
      "items" => [
        %{
          "id" => "a1",
          "title" => "New LLM breakthrough",
          "url" => "https://ai.example.com/1",
          "source_id" => "src_ai",
          "novelty_score" => 0.9
        },
        %{
          "id" => "a2",
          "title" => "GPT-5 announced",
          "url" => "https://ai.example.com/2",
          "source_id" => "src_news",
          "novelty_score" => 0.7
        }
      ]
    },
    %{
      "cluster_id" => "c1",
      "label" => "Elixir Ecosystem",
      "cluster_score" => 1.2,
      "items" => [
        %{
          "id" => "b1",
          "title" => "Phoenix 2.0 released",
          "url" => "https://elixir.example.com/1",
          "source_id" => "src_elixir",
          "novelty_score" => 0.8
        },
        %{
          "id" => "b2",
          "title" => "LiveView improvements",
          "url" => "https://elixir.example.com/2",
          "source_id" => "src_elixir",
          "novelty_score" => 0.5
        }
      ]
    }
  ]

  @summaries [
    %{
      "cluster_id" => "c0",
      "summary" => "Major advances in AI this week.",
      "key_takeaways" => ["LLM quality improving", "Competition intensifying"]
    },
    %{
      "cluster_id" => "c1",
      "summary" => "Elixir ecosystem continues to grow.",
      "key_takeaways" => ["Phoenix 2.0 is a big release"]
    }
  ]

  @source_health [
    %{"source_id" => "src_ai", "items_fetched" => 10, "error" => nil},
    %{"source_id" => "src_news", "items_fetched" => 5, "error" => nil},
    %{"source_id" => "src_elixir", "items_fetched" => 8, "error" => nil}
  ]

  describe "post-dedup pipeline integration" do
    test "compose + render produces valid HTML with all expected content" do
      # Step 1: Compose briefing
      {:ok, compose_out} =
        ComposeBriefing.execute(%{
          "ranked_clusters" => Jason.encode!(@clusters),
          "summaries" => Jason.encode!(@summaries),
          "source_health" => Jason.encode!(@source_health),
          "run_id" => "radar-20260402T120000",
          "date" => "2026-04-02"
        })

      briefing_json = compose_out["briefing"]
      briefing = Jason.decode!(briefing_json)

      # Verify briefing structure
      assert briefing["run_id"] == "radar-20260402T120000"
      assert briefing["date"] == "2026-04-02"
      assert briefing["stats"]["cluster_count"] == 2
      assert briefing["stats"]["item_count"] == 4
      assert briefing["stats"]["source_count"] == 3
      assert length(briefing["clusters"]) == 2

      # Verify summaries are attached
      assert hd(briefing["clusters"])["summary"] == "Major advances in AI this week."

      # Step 2: Render HTML
      {:ok, render_out} = RenderHtml.execute(%{"briefing" => briefing_json})

      html = render_out["html"]

      # Verify HTML is self-contained and complete
      assert String.starts_with?(html, "<!DOCTYPE html>")
      assert String.contains?(html, "</html>")

      # Verify HTML contains cluster content
      assert String.contains?(html, "AI Advances")
      assert String.contains?(html, "Elixir Ecosystem")
      assert String.contains?(html, "Major advances in AI this week.")
      assert String.contains?(html, "Elixir ecosystem continues to grow.")

      # Verify HTML contains item links
      assert String.contains?(html, "https://ai.example.com/1")
      assert String.contains?(html, "New LLM breakthrough")
      assert String.contains?(html, "Phoenix 2.0 released")

      # Verify HTML contains key takeaways
      assert String.contains?(html, "LLM quality improving")
      assert String.contains?(html, "Phoenix 2.0 is a big release")

      # Verify HTML contains source health
      assert String.contains?(html, "src_ai")
      assert String.contains?(html, "src_elixir")

      # Verify HTML contains run metadata
      assert String.contains?(html, "radar-20260402T120000")
      assert String.contains?(html, "2026-04-02")

      # Verify self-contained (no external references)
      refute String.contains?(html, ~s(<link rel="stylesheet"))
      refute String.contains?(html, ~s(<script src=))
    end

    test "empty pipeline produces valid HTML with no-items message" do
      {:ok, compose_out} =
        ComposeBriefing.execute(%{
          "ranked_clusters" => Jason.encode!([]),
          "summaries" => Jason.encode!([]),
          "source_health" => Jason.encode!([]),
          "run_id" => "radar-empty",
          "date" => "2026-04-02"
        })

      {:ok, render_out} = RenderHtml.execute(%{"briefing" => compose_out["briefing"]})

      html = render_out["html"]
      assert String.starts_with?(html, "<!DOCTYPE html>")
      assert String.contains?(html, "No items")
    end
  end
end
