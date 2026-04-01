defmodule Liminara.Observation.Layout do
  @moduledoc false

  alias Liminara.Plan

  @spacing_primary 150
  @spacing_secondary 80
  @padding 40

  defstruct [:nodes, :edges, :width, :height, :direction]

  @doc """
  Compute a layout for the given plan.

  Options:
  - `:direction` — `:ltr` (left-to-right, default) or `:ttb` (top-to-bottom)
  """
  def compute(%Plan{} = plan, opts \\ []) do
    direction = Keyword.get(opts, :direction, :ltr)

    if map_size(plan.nodes) == 0 do
      %__MODULE__{
        nodes: %{},
        edges: [],
        width: @padding * 2,
        height: @padding * 2,
        direction: direction
      }
    else
      layers = assign_layers(plan)
      positioned_nodes = position_nodes(layers, direction, plan)
      edges = extract_edges(plan)
      {w, h} = compute_dimensions(positioned_nodes, direction)

      %__MODULE__{
        nodes: positioned_nodes,
        edges: edges,
        width: w,
        height: h,
        direction: direction
      }
    end
  end

  # ── Layer assignment (longest-path layering) ──────────────────────

  defp assign_layers(%Plan{nodes: nodes, insert_order: order}) do
    deps_map = build_deps_map(nodes)

    Enum.reduce(order, %{}, fn node_id, layers ->
      layer = compute_layer(Map.get(deps_map, node_id, []), layers)
      Map.put(layers, node_id, layer)
    end)
  end

  defp compute_layer([], _layers), do: 0

  defp compute_layer(deps, layers) do
    deps |> Enum.map(&Map.get(layers, &1, 0)) |> Enum.max() |> Kernel.+(1)
  end

  defp build_deps_map(nodes) do
    Map.new(nodes, fn {node_id, node} ->
      deps =
        node.inputs
        |> Map.values()
        |> Enum.flat_map(fn
          {:ref, ref_id} -> [ref_id]
          {:ref, ref_id, _key} -> [ref_id]
          {:literal, _} -> []
        end)
        |> Enum.uniq()

      {node_id, deps}
    end)
  end

  # ── Node positioning ──────────────────────────────────────────────

  defp position_nodes(layers, direction, plan) do
    by_layer = group_by_layer(layers)

    Map.new(layers, fn {node_id, layer} ->
      nodes_in_layer = Map.get(by_layer, layer, [])
      position = Enum.find_index(nodes_in_layer, fn id -> id == node_id end)

      {x, y} = compute_coords(layer, position, direction)

      op_name = get_op_name(node_id, plan)

      entry = %{x: x, y: y, layer: layer, position: position, op_name: op_name}
      {node_id, entry}
    end)
  end

  defp group_by_layer(layers) do
    Enum.reduce(layers, %{}, fn {node_id, layer}, acc ->
      Map.update(acc, layer, [node_id], fn existing -> existing ++ [node_id] end)
    end)
  end

  defp compute_coords(layer, position, :ltr) do
    x = @padding + layer * @spacing_primary
    y = @padding + position * @spacing_secondary
    {x, y}
  end

  defp compute_coords(layer, position, :ttb) do
    x = @padding + position * @spacing_secondary
    y = @padding + layer * @spacing_primary
    {x, y}
  end

  defp get_op_name(node_id, plan) do
    case Map.get(plan.nodes, node_id) do
      %{op_module: mod} when not is_nil(mod) ->
        try do
          mod.name()
        rescue
          _ -> node_id
        end

      _ ->
        node_id
    end
  end

  # ── Edge extraction ──────────────────────────────────────────────

  defp extract_edges(%Plan{nodes: nodes}) do
    nodes
    |> Enum.flat_map(fn {node_id, node} ->
      node.inputs
      |> Map.values()
      |> Enum.flat_map(fn
        {:ref, ref_id} -> [%{from: ref_id, to: node_id}]
        {:ref, ref_id, _key} -> [%{from: ref_id, to: node_id}]
        {:literal, _} -> []
      end)
    end)
    |> Enum.uniq()
  end

  # ── Dimensions ───────────────────────────────────────────────────

  defp compute_dimensions(nodes, _direction) when map_size(nodes) == 0 do
    {@padding * 2, @padding * 2}
  end

  defp compute_dimensions(nodes, :ltr) do
    max_layer = nodes |> Map.values() |> Enum.map(& &1.layer) |> Enum.max()
    max_position = nodes |> Map.values() |> Enum.map(& &1.position) |> Enum.max()

    width = @padding + (max_layer + 1) * @spacing_primary + @padding
    height = @padding + (max_position + 1) * @spacing_secondary + @padding
    {width, height}
  end

  defp compute_dimensions(nodes, :ttb) do
    max_layer = nodes |> Map.values() |> Enum.map(& &1.layer) |> Enum.max()
    max_position = nodes |> Map.values() |> Enum.map(& &1.position) |> Enum.max()

    width = @padding + (max_position + 1) * @spacing_secondary + @padding
    height = @padding + (max_layer + 1) * @spacing_primary + @padding
    {width, height}
  end
end
