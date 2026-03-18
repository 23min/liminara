defmodule Liminara.PlanTest do
  use ExUnit.Case, async: true

  alias Liminara.Plan

  describe "construction" do
    test "new/0 creates an empty plan" do
      plan = Plan.new()
      assert Plan.nodes(plan) == %{}
    end

    test "add_node/4 adds a node" do
      plan =
        Plan.new()
        |> Plan.add_node("fetch", MyOp, %{})

      assert Map.has_key?(Plan.nodes(plan), "fetch")
    end

    test "multiple nodes can be added" do
      plan =
        Plan.new()
        |> Plan.add_node("a", OpA, %{})
        |> Plan.add_node("b", OpB, %{})
        |> Plan.add_node("c", OpC, %{})

      assert map_size(Plan.nodes(plan)) == 3
    end

    test "node with literal inputs" do
      plan =
        Plan.new()
        |> Plan.add_node("fetch", FetchOp, %{"url" => {:literal, "https://example.com"}})

      node = Plan.get_node(plan, "fetch")
      assert node.inputs == %{"url" => {:literal, "https://example.com"}}
    end

    test "node with ref inputs" do
      plan =
        Plan.new()
        |> Plan.add_node("fetch", FetchOp, %{})
        |> Plan.add_node("process", ProcessOp, %{"data" => {:ref, "fetch"}})

      node = Plan.get_node(plan, "process")
      assert node.inputs == %{"data" => {:ref, "fetch"}}
    end

    test "node with mixed literal and ref inputs" do
      plan =
        Plan.new()
        |> Plan.add_node("fetch", FetchOp, %{})
        |> Plan.add_node("process", ProcessOp, %{
          "data" => {:ref, "fetch"},
          "config" => {:literal, %{"mode" => "fast"}}
        })

      node = Plan.get_node(plan, "process")
      assert node.inputs["data"] == {:ref, "fetch"}
      assert node.inputs["config"] == {:literal, %{"mode" => "fast"}}
    end

    test "get_node/2 returns node definition" do
      plan = Plan.new() |> Plan.add_node("a", OpA, %{})
      node = Plan.get_node(plan, "a")

      assert node.node_id == "a"
      assert node.op_module == OpA
      assert node.inputs == %{}
    end
  end

  describe "ready_nodes/2" do
    test "empty plan has no ready nodes" do
      plan = Plan.new()
      assert Plan.ready_nodes(plan, MapSet.new()) == []
    end

    test "single node with no inputs is immediately ready" do
      plan = Plan.new() |> Plan.add_node("a", OpA, %{})
      assert Plan.ready_nodes(plan, MapSet.new()) == ["a"]
    end

    test "single node with only literal inputs is immediately ready" do
      plan =
        Plan.new()
        |> Plan.add_node("a", OpA, %{"x" => {:literal, 42}})

      assert Plan.ready_nodes(plan, MapSet.new()) == ["a"]
    end

    test "linear chain: A → B → C" do
      plan =
        Plan.new()
        |> Plan.add_node("a", OpA, %{})
        |> Plan.add_node("b", OpB, %{"in" => {:ref, "a"}})
        |> Plan.add_node("c", OpC, %{"in" => {:ref, "b"}})

      # Initially only A is ready
      assert Plan.ready_nodes(plan, MapSet.new()) == ["a"]

      # After A completes, B is ready
      assert Plan.ready_nodes(plan, MapSet.new(["a"])) == ["b"]

      # After A and B complete, C is ready
      assert Plan.ready_nodes(plan, MapSet.new(["a", "b"])) == ["c"]

      # After all complete, nothing ready
      assert Plan.ready_nodes(plan, MapSet.new(["a", "b", "c"])) == []
    end

    test "fan-out: A → B, A → C" do
      plan =
        Plan.new()
        |> Plan.add_node("a", OpA, %{})
        |> Plan.add_node("b", OpB, %{"in" => {:ref, "a"}})
        |> Plan.add_node("c", OpC, %{"in" => {:ref, "a"}})

      assert Plan.ready_nodes(plan, MapSet.new()) == ["a"]

      ready = Plan.ready_nodes(plan, MapSet.new(["a"]))
      assert Enum.sort(ready) == ["b", "c"]
    end

    test "fan-in: A → C, B → C" do
      plan =
        Plan.new()
        |> Plan.add_node("a", OpA, %{})
        |> Plan.add_node("b", OpB, %{})
        |> Plan.add_node("c", OpC, %{"x" => {:ref, "a"}, "y" => {:ref, "b"}})

      # Initially A and B are ready
      ready = Plan.ready_nodes(plan, MapSet.new())
      assert Enum.sort(ready) == ["a", "b"]

      # After only A, C is not ready yet
      assert Plan.ready_nodes(plan, MapSet.new(["a"])) == ["b"]

      # After both A and B, C is ready
      assert Plan.ready_nodes(plan, MapSet.new(["a", "b"])) == ["c"]
    end

    test "completed nodes are not returned as ready" do
      plan = Plan.new() |> Plan.add_node("a", OpA, %{})
      assert Plan.ready_nodes(plan, MapSet.new(["a"])) == []
    end
  end

  describe "all_complete?/2" do
    test "empty plan is complete" do
      assert Plan.all_complete?(Plan.new(), MapSet.new())
    end

    test "plan with uncompleted nodes is not complete" do
      plan = Plan.new() |> Plan.add_node("a", OpA, %{})
      refute Plan.all_complete?(plan, MapSet.new())
    end

    test "plan with all nodes completed" do
      plan =
        Plan.new()
        |> Plan.add_node("a", OpA, %{})
        |> Plan.add_node("b", OpB, %{})

      assert Plan.all_complete?(plan, MapSet.new(["a", "b"]))
    end
  end

  describe "validate/1" do
    test "valid linear plan passes" do
      plan =
        Plan.new()
        |> Plan.add_node("a", OpA, %{})
        |> Plan.add_node("b", OpB, %{"in" => {:ref, "a"}})

      assert :ok = Plan.validate(plan)
    end

    test "valid fan-out plan passes" do
      plan =
        Plan.new()
        |> Plan.add_node("a", OpA, %{})
        |> Plan.add_node("b", OpB, %{"in" => {:ref, "a"}})
        |> Plan.add_node("c", OpC, %{"in" => {:ref, "a"}})

      assert :ok = Plan.validate(plan)
    end

    test "empty plan passes" do
      assert :ok = Plan.validate(Plan.new())
    end

    test "duplicate node_id rejected" do
      plan =
        Plan.new()
        |> Plan.add_node("a", OpA, %{})
        |> Plan.add_node("a", OpB, %{})

      assert {:error, {:duplicate_node, "a"}} = Plan.validate(plan)
    end

    test "dangling ref rejected" do
      plan =
        Plan.new()
        |> Plan.add_node("b", OpB, %{"in" => {:ref, "nonexistent"}})

      assert {:error, {:dangling_ref, "b", "nonexistent"}} = Plan.validate(plan)
    end

    test "cycle rejected" do
      plan =
        Plan.new()
        |> Plan.add_node("a", OpA, %{"in" => {:ref, "b"}})
        |> Plan.add_node("b", OpB, %{"in" => {:ref, "a"}})

      assert {:error, {:cycle, _}} = Plan.validate(plan)
    end

    test "self-referencing node rejected" do
      plan =
        Plan.new()
        |> Plan.add_node("a", OpA, %{"in" => {:ref, "a"}})

      assert {:error, {:cycle, _}} = Plan.validate(plan)
    end
  end

  describe "hash/1" do
    test "same plan produces same hash" do
      plan =
        Plan.new()
        |> Plan.add_node("a", OpA, %{})
        |> Plan.add_node("b", OpB, %{"in" => {:ref, "a"}})

      assert Plan.hash(plan) == Plan.hash(plan)
    end

    test "different plans produce different hashes" do
      plan1 =
        Plan.new()
        |> Plan.add_node("a", OpA, %{})

      plan2 =
        Plan.new()
        |> Plan.add_node("b", OpB, %{})

      assert Plan.hash(plan1) != Plan.hash(plan2)
    end

    test "hash is in sha256 format" do
      plan = Plan.new() |> Plan.add_node("a", OpA, %{})
      assert Plan.hash(plan) =~ ~r/^sha256:[a-f0-9]{64}$/
    end
  end
end
