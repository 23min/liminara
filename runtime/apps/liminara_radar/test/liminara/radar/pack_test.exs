defmodule Liminara.Radar.PackTest do
  use ExUnit.Case, async: true

  alias Liminara.Radar
  alias Liminara.Plan

  @rss_source %{
    "id" => "src_rss",
    "name" => "RSS Source",
    "type" => "rss",
    "feed_url" => "https://example.com/feed.xml",
    "tags" => ["tech"],
    "enabled" => true
  }

  @web_source %{
    "id" => "src_web",
    "name" => "Web Source",
    "type" => "web",
    "url" => "https://example.com/blog",
    "tags" => ["ai"],
    "enabled" => true
  }

  describe "Pack behaviour" do
    test "id returns :radar" do
      assert Radar.id() == :radar
    end

    test "version returns a semver string" do
      assert Radar.version() =~ ~r/^\d+\.\d+\.\d+$/
    end

    test "ops returns a list of modules" do
      ops = Radar.ops()
      assert is_list(ops)
      assert length(ops) > 0
      assert Enum.all?(ops, &is_atom/1)
    end
  end

  describe "plan/1" do
    test "builds plan with fetch + pipeline nodes" do
      sources = [@rss_source, @web_source]
      plan = Radar.plan(sources)

      assert %Plan{} = plan
      nodes = Plan.nodes(plan)

      # 2 fetch + collect + normalize + embed + dedup + llm_dedup_check + merge_results
      # + cluster + rank + summarize + compose_briefing + render_html = 13
      assert map_size(nodes) == 13

      assert Map.has_key?(nodes, "fetch_src_rss")
      assert Map.has_key?(nodes, "fetch_src_web")
      assert Map.has_key?(nodes, "collect_items")
      assert Map.has_key?(nodes, "normalize")
      assert Map.has_key?(nodes, "embed")
      assert Map.has_key?(nodes, "dedup")
      assert Map.has_key?(nodes, "llm_dedup_check")
      assert Map.has_key?(nodes, "merge_results")
      assert Map.has_key?(nodes, "cluster")
      assert Map.has_key?(nodes, "rank")
      assert Map.has_key?(nodes, "summarize")
      assert Map.has_key?(nodes, "compose_briefing")
      assert Map.has_key?(nodes, "render_html")
    end

    test "RSS sources get FetchRss op module" do
      plan = Radar.plan([@rss_source])
      node = Plan.get_node(plan, "fetch_src_rss")

      assert node.op_module == Liminara.Radar.Ops.FetchRss
    end

    test "web sources get FetchWeb op module" do
      plan = Radar.plan([@web_source])
      node = Plan.get_node(plan, "fetch_src_web")

      assert node.op_module == Liminara.Radar.Ops.FetchWeb
    end

    test "collect node references all fetch nodes" do
      sources = [@rss_source, @web_source]
      plan = Radar.plan(sources)
      collect = Plan.get_node(plan, "collect_items")

      input_refs =
        collect.inputs
        |> Map.values()
        |> Enum.map(fn
          {:ref, ref_id, _key} -> ref_id
          {:ref, ref_id} -> ref_id
        end)

      assert "fetch_src_rss" in input_refs
      assert "fetch_src_web" in input_refs
    end

    test "normalize follows collect" do
      plan = Radar.plan([@rss_source])
      normalize = Plan.get_node(plan, "normalize")
      assert normalize.inputs["items"] == {:ref, "collect_items", "items"}
    end

    test "embed follows normalize" do
      plan = Radar.plan([@rss_source])
      embed = Plan.get_node(plan, "embed")
      assert embed.inputs["items"] == {:ref, "normalize", "items"}
    end

    test "dedup follows embed" do
      plan = Radar.plan([@rss_source])
      dedup = Plan.get_node(plan, "dedup")
      assert dedup.inputs["items"] == {:ref, "embed", "items"}
    end

    test "merge_results combines dedup new + llm kept" do
      plan = Radar.plan([@rss_source])
      merge = Plan.get_node(plan, "merge_results")
      assert merge.inputs["dedup_result"] == {:ref, "dedup", "result"}
      assert merge.inputs["llm_kept_items"] == {:ref, "llm_dedup_check", "items"}
    end

    test "empty source list produces plan with pipeline nodes only" do
      plan = Radar.plan([])
      nodes = Plan.nodes(plan)

      # collect + normalize + embed + dedup + llm_dedup_check + merge_results
      # + cluster + rank + summarize + compose_briefing + render_html = 11
      assert map_size(nodes) == 11
      assert Map.has_key?(nodes, "collect_items")
      assert Map.has_key?(nodes, "merge_results")
    end

    test "plan validates successfully" do
      plan = Radar.plan([@rss_source, @web_source])
      assert :ok = Plan.validate(plan)
    end

    test "dedup and compose_briefing do not synthesize runtime run_id inputs" do
      plan = Radar.plan([@rss_source])
      dedup = Plan.get_node(plan, "dedup")
      compose = Plan.get_node(plan, "compose_briefing")

      refute Map.has_key?(dedup.inputs, "run_id")
      refute Map.has_key?(compose.inputs, "run_id")
      assert Map.has_key?(compose.inputs, "date")
    end

    test "rank receives an explicit no-history contract and reference_time" do
      plan = Radar.plan([@rss_source])
      rank = Plan.get_node(plan, "rank")

      refute Map.has_key?(rank.inputs, "historical_centroid")

      {:literal, history_basis} = rank.inputs["history_basis"]
      assert history_basis == "none"

      {:literal, ref_time} = rank.inputs["reference_time"]
      assert ref_time =~ ~r/^\d{4}-\d{2}-\d{2}T/
    end
  end
end
