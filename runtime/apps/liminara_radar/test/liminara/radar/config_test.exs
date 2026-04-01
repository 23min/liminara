defmodule Liminara.Radar.ConfigTest do
  use ExUnit.Case, async: true

  alias Liminara.Radar.Config

  @fixtures_dir Path.expand("../../fixtures", __DIR__)

  setup do
    File.mkdir_p!(@fixtures_dir)

    valid_jsonl = """
    {"id":"src_1","name":"Source One","type":"rss","feed_url":"https://example.com/feed.xml","tags":["tech"],"enabled":true}
    {"id":"src_2","name":"Source Two","type":"web","url":"https://example.com/blog","tags":["ai","ml"],"enabled":true}
    {"id":"src_3","name":"Source Three","type":"rss","feed_url":"https://example.com/disabled.xml","tags":["tech"],"enabled":false}
    """

    valid_path = Path.join(@fixtures_dir, "valid_sources.jsonl")
    File.write!(valid_path, valid_jsonl)

    on_exit(fn -> File.rm_rf!(@fixtures_dir) end)

    %{valid_path: valid_path}
  end

  describe "load/1" do
    test "loads valid JSONL config and returns source list", %{valid_path: path} do
      assert {:ok, sources} = Config.load(path)
      assert length(sources) == 3
      assert Enum.all?(sources, &is_map/1)
    end

    test "each source has required fields", %{valid_path: path} do
      {:ok, sources} = Config.load(path)

      for source <- sources do
        assert Map.has_key?(source, "id")
        assert Map.has_key?(source, "name")
        assert Map.has_key?(source, "type")
        assert Map.has_key?(source, "tags")
        assert Map.has_key?(source, "enabled")
      end
    end

    test "returns error for missing file" do
      assert {:error, _reason} = Config.load("/nonexistent/path.jsonl")
    end

    test "returns error for invalid JSON line" do
      path = Path.join(@fixtures_dir, "bad.jsonl")
      File.write!(path, "not json\n")

      assert {:error, _reason} = Config.load(path)
    end

    test "returns error for missing required field" do
      path = Path.join(@fixtures_dir, "missing_field.jsonl")
      File.write!(path, ~s|{"id":"x","name":"X","type":"rss","tags":[]}\n|)

      assert {:error, _reason} = Config.load(path)
    end
  end

  describe "enabled/1" do
    test "filters to only enabled sources", %{valid_path: path} do
      {:ok, sources} = Config.load(path)
      enabled = Config.enabled(sources)

      assert length(enabled) == 2
      assert Enum.all?(enabled, &(&1["enabled"] == true))
    end
  end

  describe "by_tags/2" do
    test "filters sources by tag", %{valid_path: path} do
      {:ok, sources} = Config.load(path)
      ai_sources = Config.by_tags(sources, ["ai"])

      assert length(ai_sources) == 1
      assert hd(ai_sources)["id"] == "src_2"
    end

    test "returns empty list when no tags match", %{valid_path: path} do
      {:ok, sources} = Config.load(path)
      assert Config.by_tags(sources, ["nonexistent"]) == []
    end
  end
end
