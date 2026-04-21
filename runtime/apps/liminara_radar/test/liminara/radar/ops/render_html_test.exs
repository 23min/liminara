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
                         "degraded" => false,
                         "degradation_code" => nil,
                         "degradation_note" => nil,
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
                         "degraded" => false,
                         "degradation_code" => nil,
                         "degradation_note" => nil,
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
                     ],
                     "degraded" => false,
                     "degraded_cluster_ids" => []
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
          "source_health" => [],
          "degraded" => false,
          "degraded_cluster_ids" => []
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

  describe "RenderHtml degraded surfaces" do
    defp degraded_briefing(opts) do
      c0_degraded = Keyword.get(opts, :c0_degraded, false)
      c1_degraded = Keyword.get(opts, :c1_degraded, false)
      c0_code = Keyword.get(opts, :c0_code, nil)
      c0_note = Keyword.get(opts, :c0_note, nil)
      c1_code = Keyword.get(opts, :c1_code, nil)
      c1_note = Keyword.get(opts, :c1_note, nil)

      degraded_ids =
        [{c0_degraded, "c0"}, {c1_degraded, "c1"}]
        |> Enum.filter(fn {d, _} -> d end)
        |> Enum.map(fn {_, id} -> id end)

      Jason.encode!(%{
        "run_id" => "run_degraded",
        "date" => "2026-04-02",
        "stats" => %{"cluster_count" => 2, "item_count" => 2, "source_count" => 0},
        "clusters" => [
          %{
            "cluster_id" => "c0",
            "label" => "AI News",
            "summary" => "AI summary c0",
            "key_takeaways" => [],
            "degraded" => c0_degraded,
            "degradation_code" => c0_code,
            "degradation_note" => c0_note,
            "items" => [
              %{
                "id" => "a1",
                "title" => "AI item",
                "url" => "https://a.com",
                "source_id" => "s1"
              }
            ]
          },
          %{
            "cluster_id" => "c1",
            "label" => "Elixir Updates",
            "summary" => "Elixir summary c1",
            "key_takeaways" => [],
            "degraded" => c1_degraded,
            "degradation_code" => c1_code,
            "degradation_note" => c1_note,
            "items" => [
              %{
                "id" => "b1",
                "title" => "Elixir item",
                "url" => "https://b.com",
                "source_id" => "s2"
              }
            ]
          }
        ],
        "source_health" => [],
        "degraded" => degraded_ids != [],
        "degraded_cluster_ids" => degraded_ids
      })
    end

    test "non-degraded briefing renders with zero degraded surface" do
      {:ok, outputs} = RenderHtml.execute(%{"briefing" => @sample_briefing})
      html = outputs["html"]

      # The CSS rule for the class is always present; the rendered element must not be.
      refute String.contains?(html, ~s(class="briefing--degraded"))
      refute String.contains?(html, ~s(class="cluster--degraded"))
      refute String.contains?(html, "cluster summaries are degraded")
    end

    test "mixed clusters: banner present, pill only on the degraded cluster" do
      briefing =
        degraded_briefing(
          c1_degraded: true,
          c1_code: "radar_summarize_placeholder",
          c1_note: "Using placeholder summaries because Anthropic access is unavailable"
        )

      {:ok, outputs} = RenderHtml.execute(%{"briefing" => briefing})
      html = outputs["html"]

      # Top-of-briefing banner element with stable class
      assert String.contains?(html, ~s(class="briefing--degraded"))
      assert String.contains?(html, "1 of 2 cluster summaries are degraded")

      # Banner cites the reason (degradation_note text, deduplicated)
      assert String.contains?(
               html,
               "Using placeholder summaries because Anthropic access is unavailable"
             )

      # Banner should mention the degraded cluster id so the operator can locate the cluster
      assert String.contains?(html, "c1")

      # Pill only on the degraded cluster — c1 carries it, c0 does not
      assert String.contains?(html, ~s(class="cluster--degraded"))

      pill_count =
        html
        |> String.split(~s(class="cluster--degraded"))
        |> length()
        |> Kernel.-(1)

      assert pill_count == 1
    end

    test "all-degraded briefing: banner once, pill on every cluster" do
      briefing =
        degraded_briefing(
          c0_degraded: true,
          c0_code: "radar_summarize_placeholder",
          c0_note: "Using placeholder summaries because Anthropic access is unavailable",
          c1_degraded: true,
          c1_code: "radar_summarize_placeholder",
          c1_note: "Using placeholder summaries because Anthropic access is unavailable"
        )

      {:ok, outputs} = RenderHtml.execute(%{"briefing" => briefing})
      html = outputs["html"]

      # Banner element appears exactly once
      banner_count =
        html
        |> String.split(~s(class="briefing--degraded"))
        |> length()
        |> Kernel.-(1)

      assert banner_count == 1

      # Banner is present
      assert String.contains?(
               html,
               "Using placeholder summaries because Anthropic access is unavailable"
             )

      # Pill element on both clusters
      pill_count =
        html
        |> String.split(~s(class="cluster--degraded"))
        |> length()
        |> Kernel.-(1)

      assert pill_count == 2
    end

    test "banner deduplicates identical degradation notes across clusters" do
      briefing =
        degraded_briefing(
          c0_degraded: true,
          c0_code: "radar_summarize_placeholder",
          c0_note: "Same placeholder reason",
          c1_degraded: true,
          c1_code: "radar_summarize_placeholder",
          c1_note: "Same placeholder reason"
        )

      {:ok, outputs} = RenderHtml.execute(%{"briefing" => briefing})
      html = outputs["html"]

      # Extract the banner section only, and count the note inside it.
      [_pre, post] = String.split(html, ~s(class="briefing--degraded"), parts: 2)
      [banner_section | _] = String.split(post, "</section>", parts: 2)

      banner_note_count =
        banner_section
        |> String.split("Same placeholder reason")
        |> length()
        |> Kernel.-(1)

      assert banner_note_count == 1
    end

    test "mixed LLM error and placeholder: banner lists both notes" do
      briefing =
        degraded_briefing(
          c0_degraded: true,
          c0_code: "radar_summarize_llm_error",
          c0_note: "Fell back to a placeholder summary after an LLM error",
          c1_degraded: true,
          c1_code: "radar_summarize_placeholder",
          c1_note: "Using placeholder summaries because Anthropic access is unavailable"
        )

      {:ok, outputs} = RenderHtml.execute(%{"briefing" => briefing})
      html = outputs["html"]

      [_pre, post] = String.split(html, ~s(class="briefing--degraded"), parts: 2)
      [banner_section | _] = String.split(post, "</section>", parts: 2)

      assert String.contains?(
               banner_section,
               "Fell back to a placeholder summary after an LLM error"
             )

      assert String.contains?(
               banner_section,
               "Using placeholder summaries because Anthropic access is unavailable"
             )
    end

    test "pill text uses the per-cluster degradation_note" do
      briefing =
        degraded_briefing(
          c1_degraded: true,
          c1_code: "radar_summarize_placeholder",
          c1_note: "Specific cluster reason"
        )

      {:ok, outputs} = RenderHtml.execute(%{"briefing" => briefing})
      html = outputs["html"]

      # Cluster c1 carries the pill with its note text
      [_pre, pill_post] = String.split(html, ~s(class="cluster--degraded"), parts: 2)
      [pill_section | _] = String.split(pill_post, "</span>", parts: 2)

      assert String.contains?(pill_section, "Specific cluster reason")
    end

    test "banner title states N of M counts" do
      # 3-cluster briefing with 2 degraded — banner should say "2 of 3".
      briefing =
        Jason.encode!(%{
          "run_id" => "run_counts",
          "date" => "2026-04-17",
          "stats" => %{"cluster_count" => 3, "item_count" => 0, "source_count" => 0},
          "clusters" => [
            %{
              "cluster_id" => "c0",
              "label" => "c0 label",
              "items" => [],
              "summary" => "Healthy",
              "key_takeaways" => [],
              "degraded" => false,
              "degradation_code" => nil,
              "degradation_note" => nil
            },
            %{
              "cluster_id" => "c1",
              "label" => "c1 label",
              "items" => [],
              "summary" => "Placeholder",
              "key_takeaways" => [],
              "degraded" => true,
              "degradation_code" => "radar_summarize_placeholder",
              "degradation_note" => "note one"
            },
            %{
              "cluster_id" => "c2",
              "label" => "c2 label",
              "items" => [],
              "summary" => "Placeholder",
              "key_takeaways" => [],
              "degraded" => true,
              "degradation_code" => "radar_summarize_placeholder",
              "degradation_note" => "note two"
            }
          ],
          "source_health" => [],
          "degraded" => true,
          "degraded_cluster_ids" => ["c1", "c2"]
        })

      {:ok, outputs} = RenderHtml.execute(%{"briefing" => briefing})
      html = outputs["html"]

      assert String.contains?(html, "2 of 3 cluster summaries are degraded")
    end

    test "pill renders fallback label when degradation_note is nil" do
      briefing =
        Jason.encode!(%{
          "run_id" => "run_nil_note",
          "date" => "2026-04-17",
          "stats" => %{"cluster_count" => 1, "item_count" => 0, "source_count" => 0},
          "clusters" => [
            %{
              "cluster_id" => "c0",
              "label" => "c0 label",
              "items" => [],
              "summary" => "Placeholder",
              "key_takeaways" => [],
              "degraded" => true,
              "degradation_code" => "some_code",
              "degradation_note" => nil
            }
          ],
          "source_health" => [],
          "degraded" => true,
          "degraded_cluster_ids" => ["c0"]
        })

      {:ok, outputs} = RenderHtml.execute(%{"briefing" => briefing})
      html = outputs["html"]

      # Pill element is present with the stable class
      assert String.contains?(html, ~s(class="cluster--degraded"))

      # Fallback label "Degraded" renders inside the pill when the note is nil
      [_pre, pill_post] = String.split(html, ~s(class="cluster--degraded"), parts: 2)
      [pill_section | _] = String.split(pill_post, "</span>", parts: 2)
      assert String.contains?(pill_section, "Degraded")
    end

    test "zero clusters non-degraded briefing: no banner, no pill element" do
      empty_non_degraded =
        Jason.encode!(%{
          "run_id" => "run_empty",
          "date" => "2026-04-02",
          "stats" => %{"cluster_count" => 0, "item_count" => 0, "source_count" => 0},
          "clusters" => [],
          "source_health" => [],
          "degraded" => false,
          "degraded_cluster_ids" => []
        })

      {:ok, outputs} = RenderHtml.execute(%{"briefing" => empty_non_degraded})
      html = outputs["html"]

      refute String.contains?(html, ~s(class="briefing--degraded"))
      refute String.contains?(html, ~s(class="cluster--degraded"))
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
