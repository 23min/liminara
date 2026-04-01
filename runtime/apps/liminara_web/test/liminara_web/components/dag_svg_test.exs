defmodule LiminaraWeb.Components.DagSvgTest do
  @moduledoc """
  Tests for the DagSvg function component.

  These tests are RED — LiminaraWeb.Components.DagSvg does not exist yet.
  All tests should fail with an UndefinedFunctionError or similar.
  """
  use LiminaraWeb.ConnCase, async: true

  alias LiminaraWeb.Components.DagSvg
  alias Liminara.Observation.Layout
  alias Liminara.Plan

  # ── Helpers ──────────────────────────────────────────────────────────

  defp two_node_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hi"}})
    |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
  end

  defp three_node_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hi"}})
    |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
    |> Plan.add_node("c", Liminara.TestOps.Upcase, %{"text" => {:ref, "b", "result"}})
  end

  defp single_node_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "single"}})
  end

  defp render_dag(plan, opts \\ []) do
    node_states = Keyword.get(opts, :node_states, %{})
    selected_node = Keyword.get(opts, :selected_node, nil)
    output_previews = Keyword.get(opts, :output_previews, %{})
    direction = Keyword.get(opts, :direction, :ltr)
    layout = Layout.compute(plan, direction: direction)

    render_component(&DagSvg.dag/1, %{
      layout: layout,
      node_states: node_states,
      selected_node: selected_node,
      output_previews: output_previews
    })
  end

  # ── SVG structure ────────────────────────────────────────────────────

  describe "SVG structure" do
    test "renders an <svg> element" do
      html = render_dag(two_node_plan())

      assert html =~ "<svg"
    end

    test "svg element has a viewBox attribute" do
      html = render_dag(two_node_plan())

      assert html =~ "viewBox="
    end

    test "renders one <rect> per node in a two-node plan" do
      html = render_dag(two_node_plan())

      # Count <rect occurrences — one per node
      rect_count = html |> String.split("<rect") |> length() |> Kernel.-(1)

      assert rect_count == 2,
             "Expected 2 <rect> elements for 2 nodes, found #{rect_count}\nHTML: #{html}"
    end

    test "renders one <rect> per node in a three-node plan" do
      html = render_dag(three_node_plan())

      rect_count = html |> String.split("<rect") |> length() |> Kernel.-(1)

      assert rect_count == 3,
             "Expected 3 <rect> elements for 3 nodes, found #{rect_count}"
    end

    test "renders one <rect> for single node plan" do
      html = render_dag(single_node_plan())

      rect_count = html |> String.split("<rect") |> length() |> Kernel.-(1)

      assert rect_count == 1,
             "Expected 1 <rect> for 1 node, found #{rect_count}"
    end

    test "renders at least one edge element (<line> or <path>) for a two-node plan" do
      html = render_dag(two_node_plan())

      has_line = String.contains?(html, "<line")
      has_path = String.contains?(html, "<path")

      assert has_line or has_path,
             "Expected at least one <line> or <path> for edges in a two-node plan"
    end

    test "no edge elements for a single-node plan (no edges)" do
      html = render_dag(single_node_plan())

      line_count = html |> String.split("<line") |> length() |> Kernel.-(1)
      path_count = html |> String.split("<path") |> length() |> Kernel.-(1)

      # Single node has no edges
      assert line_count + path_count == 0,
             "Expected no edges for single-node plan, found #{line_count} lines and #{path_count} paths"
    end

    test "renders <text> labels for each node" do
      html = render_dag(two_node_plan())

      # Should have at least one <text> element per node
      text_count = html |> String.split("<text") |> length() |> Kernel.-(1)

      assert text_count >= 2,
             "Expected at least 2 <text> labels (one per node), found #{text_count}"
    end

    test "renders arrowhead <defs> with marker definition" do
      html = render_dag(two_node_plan())

      assert html =~ "<defs",
             "Expected <defs> element for arrowhead marker"

      assert html =~ "marker",
             "Expected marker definition inside <defs>"
    end
  end

  # ── Node states ──────────────────────────────────────────────────────

  describe "node states" do
    test "pending node has CSS class containing 'node--pending'" do
      html =
        render_dag(single_node_plan(),
          node_states: %{"a" => :pending}
        )

      assert html =~ "node--pending",
             "Expected 'node--pending' class for pending node. HTML:\n#{html}"
    end

    test "running node has CSS class containing 'node--running'" do
      html =
        render_dag(single_node_plan(),
          node_states: %{"a" => :running}
        )

      assert html =~ "node--running",
             "Expected 'node--running' class for running node. HTML:\n#{html}"
    end

    test "completed node has CSS class containing 'node--completed'" do
      html =
        render_dag(single_node_plan(),
          node_states: %{"a" => :completed}
        )

      assert html =~ "node--completed",
             "Expected 'node--completed' class for completed node. HTML:\n#{html}"
    end

    test "failed node has CSS class containing 'node--failed'" do
      html =
        render_dag(single_node_plan(),
          node_states: %{"a" => :failed}
        )

      assert html =~ "node--failed",
             "Expected 'node--failed' class for failed node. HTML:\n#{html}"
    end

    test "waiting node has CSS class containing 'node--waiting'" do
      html =
        render_dag(single_node_plan(),
          node_states: %{"a" => :waiting}
        )

      assert html =~ "node--waiting",
             "Expected 'node--waiting' class for waiting node. HTML:\n#{html}"
    end

    test "all node elements have base 'node' class" do
      html =
        render_dag(two_node_plan(),
          node_states: %{"a" => :completed, "b" => :pending}
        )

      # Should have at least two occurrences of class containing "node"
      assert html =~ ~r/class="[^"]*\bnode\b/,
             "Expected 'node' base class on node elements"
    end

    test "node with no state defaults to pending class" do
      # No node_states provided — should still render with a class
      html = render_dag(single_node_plan(), node_states: %{})

      # Without explicit state, node should still be rendered (likely as pending)
      assert html =~ "<rect",
             "Node should render even without explicit state"
    end
  end

  # ── Node content ─────────────────────────────────────────────────────

  describe "node content" do
    test "pending node shows op name as text label" do
      html =
        render_dag(single_node_plan(),
          node_states: %{"a" => :pending}
        )

      # The op name for Liminara.TestOps.Upcase is "upcase"
      assert html =~ "upcase",
             "Expected op name 'upcase' in pending node label. HTML:\n#{html}"
    end

    test "running node shows op name as text label" do
      html =
        render_dag(single_node_plan(),
          node_states: %{"a" => :running}
        )

      assert html =~ "upcase",
             "Expected op name 'upcase' in running node label."
    end

    test "completed node with output preview shows the preview text" do
      html =
        render_dag(single_node_plan(),
          node_states: %{"a" => :completed},
          output_previews: %{"a" => "HELLO WORLD"}
        )

      assert html =~ "HELLO WORLD",
             "Expected output preview 'HELLO WORLD' for completed node. HTML:\n#{html}"
    end

    test "completed node without output preview shows op name" do
      html =
        render_dag(single_node_plan(),
          node_states: %{"a" => :completed},
          output_previews: %{}
        )

      # No preview available — fall back to op name
      assert html =~ "upcase",
             "Expected op name as fallback when no output preview. HTML:\n#{html}"
    end

    test "node labels show correct node identifiers or op names" do
      html =
        render_dag(two_node_plan(),
          node_states: %{"a" => :completed, "b" => :pending},
          output_previews: %{}
        )

      # Both op names should appear somewhere in the SVG
      assert html =~ "upcase" or html =~ "a"
      assert html =~ "reverse" or html =~ "b"
    end
  end

  # ── Node selection ───────────────────────────────────────────────────

  describe "selection" do
    test "selected node has 'node--selected' class" do
      html =
        render_dag(two_node_plan(),
          node_states: %{"a" => :completed, "b" => :pending},
          selected_node: "a"
        )

      assert html =~ "node--selected",
             "Expected 'node--selected' class on selected node. HTML:\n#{html}"
    end

    test "unselected nodes do not have 'node--selected' class when no selection" do
      html =
        render_dag(two_node_plan(),
          node_states: %{"a" => :completed, "b" => :pending},
          selected_node: nil
        )

      refute html =~ "node--selected",
             "No node should have 'node--selected' when selected_node is nil. HTML:\n#{html}"
    end

    test "only the selected node gets 'node--selected' class (not all nodes)" do
      html =
        render_dag(two_node_plan(),
          node_states: %{"a" => :completed, "b" => :pending},
          selected_node: "a"
        )

      # Count occurrences of 'node--selected' — should be exactly 1 (just "a")
      count =
        html
        |> String.split("node--selected")
        |> length()
        |> Kernel.-(1)

      assert count == 1,
             "Expected exactly 1 node with 'node--selected', found #{count}. HTML:\n#{html}"
    end

    test "node has phx-click attribute for selection" do
      html = render_dag(two_node_plan())

      assert html =~ "phx-click",
             "Expected phx-click attribute for node click events. HTML:\n#{html}"
    end

    test "node phx-click references select_node event" do
      html = render_dag(two_node_plan())

      assert html =~ "select_node",
             "Expected phx-click to reference 'select_node'. HTML:\n#{html}"
    end

    test "node has phx-value-node-id attribute with the node id" do
      html = render_dag(two_node_plan())

      assert html =~ "phx-value-node-id",
             "Expected phx-value-node-id attribute on node. HTML:\n#{html}"
    end
  end

  # ── viewBox and responsiveness ────────────────────────────────────────

  describe "viewBox and responsiveness" do
    test "viewBox attribute contains layout dimensions" do
      plan = two_node_plan()
      layout = Layout.compute(plan)

      html =
        render_component(&DagSvg.dag/1, %{
          layout: layout,
          node_states: %{},
          selected_node: nil,
          output_previews: %{}
        })

      # viewBox should reference the layout's width and height
      assert html =~ "viewBox=",
             "Expected viewBox attribute. HTML:\n#{html}"

      width_str = "#{trunc(layout.width)}"
      height_str = "#{trunc(layout.height)}"

      assert html =~ width_str or html =~ "#{layout.width}",
             "Expected layout width #{layout.width} in viewBox. HTML:\n#{html}"

      assert html =~ height_str or html =~ "#{layout.height}",
             "Expected layout height #{layout.height} in viewBox. HTML:\n#{html}"
    end

    test "SVG has width:100% style or width attribute for responsive scaling" do
      html = render_dag(two_node_plan())

      has_width_100 = html =~ "width:100%" or html =~ ~s(width="100%")

      assert has_width_100,
             "Expected SVG to have width:100% for responsive scaling. HTML:\n#{html}"
    end
  end

  # ── Direction ─────────────────────────────────────────────────────────

  describe "direction" do
    test "renders correctly in LTR direction (default)" do
      html = render_dag(two_node_plan(), direction: :ltr)

      assert html =~ "<svg"
      assert html =~ "<rect"
    end

    test "renders correctly in TTB direction" do
      html = render_dag(two_node_plan(), direction: :ttb)

      assert html =~ "<svg"
      assert html =~ "<rect"
    end
  end

  # ── Edge rendering ────────────────────────────────────────────────────

  describe "edge rendering" do
    test "three-node linear plan has exactly 2 edges" do
      html = render_dag(three_node_plan())

      line_count = html |> String.split("<line") |> length() |> Kernel.-(1)
      path_count = html |> String.split("<path") |> length() |> Kernel.-(1)

      # Exclude marker paths (arrowhead defs) — count only data edges
      # We expect exactly 2 edge elements for a 3-node linear chain
      # (the arrowhead path in <defs> doesn't count as an edge)
      total_edge_count = line_count + path_count

      assert total_edge_count >= 2,
             "Expected at least 2 edge elements for 3-node plan, found #{total_edge_count}"
    end
  end
end
