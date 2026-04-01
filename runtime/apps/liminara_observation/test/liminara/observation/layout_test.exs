defmodule Liminara.Observation.LayoutTest do
  use ExUnit.Case, async: true

  alias Liminara.Observation.Layout
  alias Liminara.Plan

  # ── Plan helpers ──────────────────────────────────────────────────────

  # Linear: A → B → C
  defp linear_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hi"}})
    |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
    |> Plan.add_node("c", Liminara.TestOps.Upcase, %{"text" => {:ref, "b", "result"}})
  end

  # Fan-out: A → B, A → C, A → D
  defp fanout_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hi"}})
    |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
    |> Plan.add_node("c", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
    |> Plan.add_node("d", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
  end

  # Fan-in: A → C, B → C
  defp fanin_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
    |> Plan.add_node("b", Liminara.TestOps.Upcase, %{"text" => {:literal, "world"}})
    |> Plan.add_node("c", Liminara.TestOps.Reverse, %{
      "text" => {:ref, "a", "result"},
      "other" => {:ref, "b", "result"}
    })
  end

  # Diamond: A → B, A → C, B → D, C → D
  defp diamond_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "top"}})
    |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
    |> Plan.add_node("c", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
    |> Plan.add_node("d", Liminara.TestOps.Upcase, %{
      "text" => {:ref, "b", "result"},
      "other" => {:ref, "c", "result"}
    })
  end

  # Single node
  defp single_node_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "single"}})
  end

  # ── Layer assignment ──────────────────────────────────────────────────

  describe "layer assignment" do
    test "linear A→B→C: a at layer 0, b at layer 1, c at layer 2" do
      layout = Layout.compute(linear_plan())

      assert layout.nodes["a"].layer == 0
      assert layout.nodes["b"].layer == 1
      assert layout.nodes["c"].layer == 2
    end

    test "fan-out A→{B,C,D}: a at layer 0, b/c/d at layer 1" do
      layout = Layout.compute(fanout_plan())

      assert layout.nodes["a"].layer == 0
      assert layout.nodes["b"].layer == 1
      assert layout.nodes["c"].layer == 1
      assert layout.nodes["d"].layer == 1
    end

    test "fan-in {A,B}→C: a and b at layer 0, c at layer 1" do
      layout = Layout.compute(fanin_plan())

      assert layout.nodes["a"].layer == 0
      assert layout.nodes["b"].layer == 0
      assert layout.nodes["c"].layer == 1
    end

    test "diamond A→{B,C}, {B,C}→D: a at layer 0, b/c at layer 1, d at layer 2" do
      layout = Layout.compute(diamond_plan())

      assert layout.nodes["a"].layer == 0
      assert layout.nodes["b"].layer == 1
      assert layout.nodes["c"].layer == 1
      assert layout.nodes["d"].layer == 2
    end

    test "single node: a at layer 0" do
      layout = Layout.compute(single_node_plan())

      assert layout.nodes["a"].layer == 0
    end

    test "empty plan returns empty nodes map" do
      layout = Layout.compute(Plan.new())

      assert layout.nodes == %{}
    end
  end

  # ── Node positioning ─────────────────────────────────────────────────

  describe "node positioning" do
    test "all nodes have numeric x and y coordinates" do
      layout = Layout.compute(linear_plan())

      for {_id, node} <- layout.nodes do
        assert is_number(node.x), "expected x to be a number, got: #{inspect(node.x)}"
        assert is_number(node.y), "expected y to be a number, got: #{inspect(node.y)}"
      end
    end

    test "no two nodes share the same x AND y coordinates (no overlap)" do
      layout = Layout.compute(fanout_plan())

      positions =
        Enum.map(layout.nodes, fn {_id, node} -> {node.x, node.y} end)

      assert length(positions) == length(Enum.uniq(positions)),
             "Two or more nodes share the same (x, y) position: #{inspect(positions)}"
    end

    test "diamond plan: no two nodes share same (x, y)" do
      layout = Layout.compute(diamond_plan())

      positions =
        Enum.map(layout.nodes, fn {_id, node} -> {node.x, node.y} end)

      assert length(positions) == length(Enum.uniq(positions))
    end

    test "LTR: nodes in same layer have the same x coordinate" do
      layout = Layout.compute(fanout_plan(), direction: :ltr)

      # b, c, d are all in layer 1 — same x
      x_b = layout.nodes["b"].x
      x_c = layout.nodes["c"].x
      x_d = layout.nodes["d"].x

      assert x_b == x_c,
             "Expected b and c to share x (layer 1), got x_b=#{x_b}, x_c=#{x_c}"

      assert x_b == x_d,
             "Expected b and d to share x (layer 1), got x_b=#{x_b}, x_d=#{x_d}"
    end

    test "TTB: nodes in same layer have the same y coordinate" do
      layout = Layout.compute(fanout_plan(), direction: :ttb)

      # b, c, d are all in layer 1 — same y
      y_b = layout.nodes["b"].y
      y_c = layout.nodes["c"].y
      y_d = layout.nodes["d"].y

      assert y_b == y_c,
             "Expected b and c to share y (layer 1), got y_b=#{y_b}, y_c=#{y_c}"

      assert y_b == y_d,
             "Expected b and d to share y (layer 1), got y_b=#{y_b}, y_d=#{y_d}"
    end

    test "LTR: nodes in different layers have different x coordinates" do
      layout = Layout.compute(linear_plan(), direction: :ltr)

      x_a = layout.nodes["a"].x
      x_b = layout.nodes["b"].x
      x_c = layout.nodes["c"].x

      assert x_a != x_b, "Layer 0 and layer 1 must have different x in LTR"
      assert x_b != x_c, "Layer 1 and layer 2 must have different x in LTR"
    end

    test "TTB: nodes in different layers have different y coordinates" do
      layout = Layout.compute(linear_plan(), direction: :ttb)

      y_a = layout.nodes["a"].y
      y_b = layout.nodes["b"].y
      y_c = layout.nodes["c"].y

      assert y_a != y_b, "Layer 0 and layer 1 must have different y in TTB"
      assert y_b != y_c, "Layer 1 and layer 2 must have different y in TTB"
    end

    test "each node has a position (integer or 0-based index within its layer)" do
      layout = Layout.compute(fanout_plan())

      for {_id, node} <- layout.nodes do
        assert is_integer(node.position) or is_number(node.position)
        assert node.position >= 0
      end
    end
  end

  # ── Direction ────────────────────────────────────────────────────────

  describe "direction" do
    test "LTR is the default direction" do
      layout = Layout.compute(linear_plan())

      assert layout.direction == :ltr
    end

    test "LTR: x increases as layer increases" do
      layout = Layout.compute(linear_plan(), direction: :ltr)

      x_a = layout.nodes["a"].x
      x_b = layout.nodes["b"].x
      x_c = layout.nodes["c"].x

      assert x_a < x_b, "LTR: layer 0 x must be less than layer 1 x"
      assert x_b < x_c, "LTR: layer 1 x must be less than layer 2 x"
    end

    test "TTB: y increases as layer increases" do
      layout = Layout.compute(linear_plan(), direction: :ttb)

      y_a = layout.nodes["a"].y
      y_b = layout.nodes["b"].y
      y_c = layout.nodes["c"].y

      assert y_a < y_b, "TTB: layer 0 y must be less than layer 1 y"
      assert y_b < y_c, "TTB: layer 1 y must be less than layer 2 y"
    end

    test "TTB direction is recorded in layout struct" do
      layout = Layout.compute(linear_plan(), direction: :ttb)

      assert layout.direction == :ttb
    end

    test "same plan in LTR vs TTB produces different coordinate orientations" do
      ltr = Layout.compute(linear_plan(), direction: :ltr)
      ttb = Layout.compute(linear_plan(), direction: :ttb)

      # In LTR, x should vary across layers; in TTB, y should vary
      # The two orientations must differ — at minimum the overall width/height relationship differs
      refute ltr.nodes["a"].x == ltr.nodes["b"].x,
             "LTR must have varying x across layers"

      refute ttb.nodes["a"].y == ttb.nodes["b"].y,
             "TTB must have varying y across layers"

      # Key invariant: LTR and TTB must differ for a non-trivial plan
      ltr_xs = Enum.map(ltr.nodes, fn {_, n} -> n.x end) |> Enum.sort()
      ttb_xs = Enum.map(ttb.nodes, fn {_, n} -> n.x end) |> Enum.sort()

      assert ltr_xs != ttb_xs or
               Enum.map(ltr.nodes, fn {_, n} -> n.y end) !=
                 Enum.map(ttb.nodes, fn {_, n} -> n.y end)
    end
  end

  # ── Edges ────────────────────────────────────────────────────────────

  describe "edges" do
    test "linear A→B→C: edges are [{a,b}, {b,c}]" do
      layout = Layout.compute(linear_plan())

      edge_pairs =
        Enum.map(layout.edges, fn e -> {e.from, e.to} end) |> MapSet.new()

      assert MapSet.member?(edge_pairs, {"a", "b"}),
             "Expected edge a→b, edges: #{inspect(layout.edges)}"

      assert MapSet.member?(edge_pairs, {"b", "c"}),
             "Expected edge b→c, edges: #{inspect(layout.edges)}"

      assert MapSet.size(edge_pairs) == 2
    end

    test "fan-out A→{B,C,D}: edges are [{a,b}, {a,c}, {a,d}]" do
      layout = Layout.compute(fanout_plan())

      edge_pairs = Enum.map(layout.edges, fn e -> {e.from, e.to} end) |> MapSet.new()

      assert MapSet.member?(edge_pairs, {"a", "b"})
      assert MapSet.member?(edge_pairs, {"a", "c"})
      assert MapSet.member?(edge_pairs, {"a", "d"})
      assert MapSet.size(edge_pairs) == 3
    end

    test "diamond A→{B,C}, {B,C}→D: 4 edges total" do
      layout = Layout.compute(diamond_plan())

      edge_pairs = Enum.map(layout.edges, fn e -> {e.from, e.to} end) |> MapSet.new()

      assert MapSet.member?(edge_pairs, {"a", "b"})
      assert MapSet.member?(edge_pairs, {"a", "c"})
      assert MapSet.member?(edge_pairs, {"b", "d"})
      assert MapSet.member?(edge_pairs, {"c", "d"})
    end

    test "each edge references only nodes that exist in the layout" do
      layout = Layout.compute(diamond_plan())
      node_ids = Map.keys(layout.nodes) |> MapSet.new()

      for edge <- layout.edges do
        assert MapSet.member?(node_ids, edge.from),
               "Edge references unknown 'from' node: #{edge.from}"

        assert MapSet.member?(node_ids, edge.to),
               "Edge references unknown 'to' node: #{edge.to}"
      end
    end

    test "single node plan has no edges" do
      layout = Layout.compute(single_node_plan())

      assert layout.edges == []
    end

    test "empty plan has no edges" do
      layout = Layout.compute(Plan.new())

      assert layout.edges == []
    end

    test "edge count matches total dependency count in plan" do
      # Diamond: a→b, a→c, b→d, c→d = 4 dependencies
      layout = Layout.compute(diamond_plan())

      assert length(layout.edges) == 4
    end
  end

  # ── Dimensions ───────────────────────────────────────────────────────

  describe "dimensions" do
    test "width is a positive number" do
      layout = Layout.compute(linear_plan())

      assert is_number(layout.width)
      assert layout.width > 0
    end

    test "height is a positive number" do
      layout = Layout.compute(linear_plan())

      assert is_number(layout.height)
      assert layout.height > 0
    end

    test "LTR: width > height for a long linear pipeline (wider than tall)" do
      # 3-node pipeline LTR should be wider than tall
      layout = Layout.compute(linear_plan(), direction: :ltr)

      assert layout.width > layout.height,
             "LTR linear pipeline should be wider than tall, got width=#{layout.width}, height=#{layout.height}"
    end

    test "TTB: height > width for a long linear pipeline (taller than wide)" do
      # 3-node pipeline TTB should be taller than wide
      layout = Layout.compute(linear_plan(), direction: :ttb)

      assert layout.height > layout.width,
             "TTB linear pipeline should be taller than wide, got width=#{layout.width}, height=#{layout.height}"
    end

    test "single node has non-zero dimensions" do
      layout = Layout.compute(single_node_plan())

      assert layout.width > 0
      assert layout.height > 0
    end
  end

  # ── Return value structure ────────────────────────────────────────────

  describe "return value structure" do
    test "compute/2 returns a Layout struct" do
      layout = Layout.compute(linear_plan())

      assert is_struct(layout)
      assert layout.__struct__ == Layout
    end

    test "layout has :nodes field" do
      layout = Layout.compute(linear_plan())

      assert Map.has_key?(layout, :nodes)
    end

    test "layout has :edges field" do
      layout = Layout.compute(linear_plan())

      assert Map.has_key?(layout, :edges)
    end

    test "layout has :width field" do
      layout = Layout.compute(linear_plan())

      assert Map.has_key?(layout, :width)
    end

    test "layout has :height field" do
      layout = Layout.compute(linear_plan())

      assert Map.has_key?(layout, :height)
    end

    test "layout has :direction field" do
      layout = Layout.compute(linear_plan())

      assert Map.has_key?(layout, :direction)
    end

    test "each node entry has :x, :y, :layer, :position keys" do
      layout = Layout.compute(linear_plan())

      for {_id, node} <- layout.nodes do
        assert Map.has_key?(node, :x), "node missing :x key"
        assert Map.has_key?(node, :y), "node missing :y key"
        assert Map.has_key?(node, :layer), "node missing :layer key"
        assert Map.has_key?(node, :position), "node missing :position key"
      end
    end

    test "each edge has :from and :to keys" do
      layout = Layout.compute(linear_plan())

      for edge <- layout.edges do
        assert Map.has_key?(edge, :from), "edge missing :from key"
        assert Map.has_key?(edge, :to), "edge missing :to key"
      end
    end

    test "nodes map has one entry per plan node" do
      layout = Layout.compute(fanout_plan())

      assert map_size(layout.nodes) == 4
      assert Map.has_key?(layout.nodes, "a")
      assert Map.has_key?(layout.nodes, "b")
      assert Map.has_key?(layout.nodes, "c")
      assert Map.has_key?(layout.nodes, "d")
    end
  end
end
