defmodule Liminara.Radar.Ops.RenderHtmlTest do
  use ExUnit.Case, async: true

  alias Liminara.Radar.Ops.RenderHtml

  @sample_briefing Jason.encode!(%{
                     "run_id" => "run_001",
                     "date" => "2026-04-02",
                     "stats" => %{
                       "cluster_count" => 2,
                       "item_count" => 3,
                       "source_count" => 5
                     },
                     "clusters" => [
                       %{
                         "cluster_id" => "c0",
                         "label" => "AI News",
                         "summary" => "AI is advancing rapidly.",
                         "key_takeaways" => ["Breakthrough in reasoning", "Cost reduction"],
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
                         "summary" => "Elixir hits version 2.",
                         "key_takeaways" => ["Major release"],
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
                     ],
                     "source_health" => [
                       %{"source_id" => "s1", "items_fetched" => 5, "error" => nil},
                       %{"source_id" => "s2", "items_fetched" => 3, "error" => nil}
                     ]
                   })

  describe "RenderHtml" do
    test "produces valid HTML string" do
      {:ok, outputs} = RenderHtml.execute(%{"briefing" => @sample_briefing})

      html = outputs["html"]
      assert is_binary(html)
      assert String.starts_with?(html, "<!DOCTYPE html>")
      assert String.contains?(html, "</html>")
    end

    test "HTML contains date header" do
      {:ok, outputs} = RenderHtml.execute(%{"briefing" => @sample_briefing})
      assert String.contains?(outputs["html"], "2026-04-02")
    end

    test "HTML contains cluster sections" do
      {:ok, outputs} = RenderHtml.execute(%{"briefing" => @sample_briefing})
      html = outputs["html"]
      assert String.contains?(html, "AI News")
      assert String.contains?(html, "Elixir Updates")
    end

    test "HTML contains item links" do
      {:ok, outputs} = RenderHtml.execute(%{"briefing" => @sample_briefing})
      html = outputs["html"]
      assert String.contains?(html, "https://a.com")
      assert String.contains?(html, "AI breakthrough")
    end

    test "HTML contains cluster summaries" do
      {:ok, outputs} = RenderHtml.execute(%{"briefing" => @sample_briefing})
      html = outputs["html"]
      assert String.contains?(html, "AI is advancing rapidly.")
      assert String.contains?(html, "Breakthrough in reasoning")
    end

    test "self-contained — no external CSS or JS references" do
      {:ok, outputs} = RenderHtml.execute(%{"briefing" => @sample_briefing})
      html = outputs["html"]
      refute String.contains?(html, ~s(<link rel="stylesheet"))
      refute String.contains?(html, ~s(<script src=))
    end

    test "empty briefing renders with no-items message" do
      empty =
        Jason.encode!(%{
          "run_id" => "run_empty",
          "date" => "2026-04-02",
          "stats" => %{"cluster_count" => 0, "item_count" => 0, "source_count" => 0},
          "clusters" => [],
          "source_health" => []
        })

      {:ok, outputs} = RenderHtml.execute(%{"briefing" => empty})
      html = outputs["html"]
      assert String.contains?(html, "No items")
    end

    test "HTML contains source health section" do
      {:ok, outputs} = RenderHtml.execute(%{"briefing" => @sample_briefing})
      html = outputs["html"]
      assert String.contains?(html, "Source Health") or String.contains?(html, "source")
    end

    test "HTML contains run metadata" do
      {:ok, outputs} = RenderHtml.execute(%{"briefing" => @sample_briefing})
      html = outputs["html"]
      assert String.contains?(html, "run_001")
    end
  end

  describe "Op behaviour" do
    test "name" do
      assert RenderHtml.name() == "render_html"
    end

    test "determinism is pure" do
      assert RenderHtml.determinism() == :pure
    end
  end
end
