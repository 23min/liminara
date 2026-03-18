defmodule Liminara.CacheTest do
  use ExUnit.Case, async: false

  alias Liminara.Cache

  setup do
    table = :ets.new(:test_cache, [:set, :public])
    %{cache: table}
  end

  describe "lookup and store" do
    test "miss on empty cache", %{cache: cache} do
      assert :miss = Cache.lookup(cache, Liminara.TestOps.Upcase, ["sha256:abc123"])
    end

    test "store then lookup returns hit", %{cache: cache} do
      input_hashes = ["sha256:abc123"]
      output_hashes = %{"result" => "sha256:def456"}

      :ok = Cache.store(cache, Liminara.TestOps.Upcase, input_hashes, output_hashes)
      assert {:hit, ^output_hashes} = Cache.lookup(cache, Liminara.TestOps.Upcase, input_hashes)
    end

    test "different op same inputs is a miss", %{cache: cache} do
      input_hashes = ["sha256:abc123"]
      :ok = Cache.store(cache, Liminara.TestOps.Upcase, input_hashes, %{"r" => "sha256:x"})

      assert :miss = Cache.lookup(cache, Liminara.TestOps.Concat, input_hashes)
    end

    test "same op different inputs is a miss", %{cache: cache} do
      :ok = Cache.store(cache, Liminara.TestOps.Upcase, ["sha256:aaa"], %{"r" => "sha256:x"})

      assert :miss = Cache.lookup(cache, Liminara.TestOps.Upcase, ["sha256:bbb"])
    end
  end

  describe "cache key" do
    test "same op and inputs produces same key", %{cache: cache} do
      inputs = ["sha256:abc", "sha256:def"]
      :ok = Cache.store(cache, Liminara.TestOps.Upcase, inputs, %{"r" => "sha256:x"})
      assert {:hit, _} = Cache.lookup(cache, Liminara.TestOps.Upcase, inputs)
    end

    test "input hash order doesnt matter (sorted internally)", %{cache: cache} do
      :ok =
        Cache.store(cache, Liminara.TestOps.Upcase, ["sha256:bbb", "sha256:aaa"], %{
          "r" => "sha256:x"
        })

      assert {:hit, _} =
               Cache.lookup(cache, Liminara.TestOps.Upcase, ["sha256:aaa", "sha256:bbb"])
    end
  end

  describe "clear" do
    test "clear removes all entries", %{cache: cache} do
      :ok = Cache.store(cache, Liminara.TestOps.Upcase, ["sha256:a"], %{"r" => "sha256:x"})
      assert {:hit, _} = Cache.lookup(cache, Liminara.TestOps.Upcase, ["sha256:a"])

      :ok = Cache.clear(cache)
      assert :miss = Cache.lookup(cache, Liminara.TestOps.Upcase, ["sha256:a"])
    end
  end
end
