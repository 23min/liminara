defmodule Liminara.CanonicalTest do
  use ExUnit.Case, async: true

  alias Liminara.Canonical

  describe "encode/1" do
    test "sorts keys lexicographically" do
      assert Canonical.encode(%{"z" => 1, "a" => 2, "m" => 3}) ==
               ~s({"a":2,"m":3,"z":1})
    end

    test "nested objects sort recursively" do
      input = %{"b" => %{"z" => 1, "a" => 2}, "a" => 1}
      assert Canonical.encode(input) == ~s({"a":1,"b":{"a":2,"z":1}})
    end

    test "null serializes correctly" do
      assert Canonical.encode(%{"a" => nil}) == ~s({"a":null})
    end

    test "boolean values serialize correctly" do
      assert Canonical.encode(%{"t" => true, "f" => false}) ==
               ~s({"f":false,"t":true})
    end

    test "arrays preserve order" do
      assert Canonical.encode(%{"a" => [3, 1, 2]}) == ~s({"a":[3,1,2]})
    end

    test "integers have no trailing zeros" do
      assert Canonical.encode(%{"n" => 42}) == ~s({"n":42})
    end

    test "floats serialize per RFC 8785" do
      # 0.7 should be represented as 0.7, not 0.69999... or 7e-1
      assert Canonical.encode(%{"n" => 0.7}) == ~s({"n":0.7})
    end

    test "strings with special characters" do
      assert Canonical.encode(%{"s" => "hello\nworld"}) ==
               ~s({"s":"hello\\nworld"})
    end

    test "empty objects and arrays" do
      assert Canonical.encode(%{"a" => [], "b" => %{}}) ==
               ~s({"a":[],"b":{}})
    end

    test "canary: known object produces expected canonical bytes" do
      canary = %{"z" => 1, "a" => [true, nil, "hello"], "m" => %{"nested" => 42}}

      assert Canonical.encode(canary) ==
               ~s({"a":[true,null,"hello"],"m":{"nested":42},"z":1})
    end
  end
end
