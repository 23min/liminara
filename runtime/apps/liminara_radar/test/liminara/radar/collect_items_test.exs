defmodule Liminara.Radar.Ops.CollectItemsTest do
  use ExUnit.Case, async: true

  alias Liminara.Radar.Ops.CollectItems

  @src1_items %{
    "items" => [
      %{"title" => "Item A", "url" => "https://a.com/1", "source_id" => "src_1"},
      %{"title" => "Item B", "url" => "https://b.com/1", "source_id" => "src_1"}
    ],
    "error" => nil
  }

  @src2_items %{
    "items" => [
      %{"title" => "Item C", "url" => "https://c.com/1", "source_id" => "src_2"}
    ],
    "error" => nil
  }

  @src2_dup %{
    "items" => [
      %{"title" => "Item A (dup)", "url" => "https://a.com/1", "source_id" => "src_2"}
    ],
    "error" => nil
  }

  @src_error %{
    "items" => [],
    "error" => "HTTP 500: Internal Server Error"
  }

  describe "execute/1" do
    test "merges items from multiple sources" do
      inputs = %{
        "fetch_src_1" => Jason.encode!(@src1_items),
        "fetch_src_2" => Jason.encode!(@src2_items)
      }

      {:ok, outputs} = CollectItems.execute(inputs)

      items = Jason.decode!(outputs["items"])
      assert length(items) == 3
    end

    test "deduplicates by URL (keeps first seen)" do
      inputs = %{
        "fetch_src_1" => Jason.encode!(@src1_items),
        "fetch_src_2" => Jason.encode!(@src2_dup)
      }

      {:ok, outputs} = CollectItems.execute(inputs)

      items = Jason.decode!(outputs["items"])
      urls = Enum.map(items, & &1["url"])

      # https://a.com/1 appears once, from src_1 (first seen)
      assert Enum.count(urls, &(&1 == "https://a.com/1")) == 1
      dup_item = Enum.find(items, &(&1["url"] == "https://a.com/1"))
      assert dup_item["source_id"] == "src_1"
    end

    test "handles source errors gracefully" do
      inputs = %{
        "fetch_src_1" => Jason.encode!(@src1_items),
        "fetch_src_err" => Jason.encode!(@src_error)
      }

      {:ok, outputs} = CollectItems.execute(inputs)

      items = Jason.decode!(outputs["items"])
      assert length(items) == 2

      health = Jason.decode!(outputs["source_health"])
      err_health = Enum.find(health, &(&1["source_id"] == "src_err"))
      assert err_health["error"] == "HTTP 500: Internal Server Error"
    end

    test "all sources empty returns empty list" do
      inputs = %{
        "fetch_src_1" => Jason.encode!(%{"items" => [], "error" => nil})
      }

      {:ok, outputs} = CollectItems.execute(inputs)

      items = Jason.decode!(outputs["items"])
      assert items == []
    end

    test "produces source health artifact" do
      inputs = %{
        "fetch_src_1" => Jason.encode!(@src1_items),
        "fetch_src_2" => Jason.encode!(@src2_items)
      }

      {:ok, outputs} = CollectItems.execute(inputs)

      health = Jason.decode!(outputs["source_health"])
      assert is_list(health)
      assert length(health) == 2

      src1_health = Enum.find(health, &(&1["source_id"] == "src_1"))
      assert src1_health["items_fetched"] == 2
      assert src1_health["error"] == nil
    end
  end
end
