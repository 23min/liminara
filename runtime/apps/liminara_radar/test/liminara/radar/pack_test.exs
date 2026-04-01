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
    test "builds plan with one fetch node per source + collect node" do
      sources = [@rss_source, @web_source]
      plan = Radar.plan(sources)

      assert %Plan{} = plan
      nodes = Plan.nodes(plan)

      # 2 fetch nodes + 1 collect node = 3
      assert map_size(nodes) == 3

      # Fetch nodes exist
      assert Map.has_key?(nodes, "fetch_src_rss")
      assert Map.has_key?(nodes, "fetch_src_web")

      # Collect node exists
      assert Map.has_key?(nodes, "collect_items")
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

      # Collect inputs should reference both fetch nodes
      input_refs =
        collect.inputs
        |> Map.values()
        |> Enum.map(fn {:ref, ref_id, _key} -> ref_id; {:ref, ref_id} -> ref_id end)

      assert "fetch_src_rss" in input_refs
      assert "fetch_src_web" in input_refs
    end

    test "empty source list produces plan with only collect node" do
      plan = Radar.plan([])
      nodes = Plan.nodes(plan)

      assert map_size(nodes) == 1
      assert Map.has_key?(nodes, "collect_items")
    end

    test "plan validates successfully" do
      plan = Radar.plan([@rss_source, @web_source])
      assert :ok = Plan.validate(plan)
    end
  end
end
