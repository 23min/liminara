defmodule LiminaraWeb.Components.DagSvg do
  @moduledoc false

  use Phoenix.Component

  @node_w 120
  @node_h 36
  @hw div(@node_w, 2)
  @hh div(@node_h, 2)

  attr :layout, :any, required: true
  attr :node_states, :map, default: %{}
  attr :selected_node, :string, default: nil
  attr :output_previews, :map, default: %{}

  def dag(assigns) do
    ~H"""
    <svg viewBox={"0 0 #{@layout.width} #{@layout.height}"} style="width:100%">
      <defs>
        <marker id="arrowhead" markerWidth="10" markerHeight="7" refX="10" refY="3.5" orient="auto">
          <polygon points="0 0, 10 3.5, 0 7" fill="#666" />
        </marker>
      </defs>
      <%= for edge <- @layout.edges do %>
        <line
          x1={edge_x1(@layout, edge)}
          y1={edge_y1(@layout, edge)}
          x2={edge_x2(@layout, edge)}
          y2={edge_y2(@layout, edge)}
          stroke="#666"
          stroke-width="1"
          marker-end="url(#arrowhead)"
        />
      <% end %>
      <%= for {node_id, pos} <- @layout.nodes do %>
        <g
          phx-click="select_node"
          phx-value-node-id={node_id}
          class={"node #{state_class(node_id, @node_states)} #{selected_class(node_id, @selected_node)}"}
        >
          <rect
            x={pos.x - 60}
            y={pos.y - 18}
            width="120"
            height="36"
            rx="4"
            fill={node_fill(node_id, @node_states)}
            stroke={node_stroke(node_id, @node_states, @selected_node)}
            stroke-width={if node_id == @selected_node, do: "3", else: "1.5"}
          />
          <text
            x={pos.x}
            y={pos.y}
            text-anchor="middle"
            dominant-baseline="central"
            font-size="12"
          >
            {node_label(node_id, pos, @node_states, @output_previews)}
          </text>
        </g>
      <% end %>
    </svg>
    """
  end

  defp state_class(node_id, node_states) do
    case Map.get(node_states, node_id, :pending) do
      :pending -> "node--pending"
      :running -> "node--running"
      :completed -> "node--completed"
      :failed -> "node--failed"
      :waiting -> "node--waiting"
      _ -> "node--pending"
    end
  end

  defp selected_class(node_id, selected_node) do
    if node_id == selected_node, do: "node--selected", else: ""
  end

  defp node_label(node_id, pos, node_states, output_previews) do
    state = Map.get(node_states, node_id, :pending)
    op_name = Map.get(pos, :op_name, node_id)

    if state == :completed do
      Map.get(output_previews, node_id, op_name)
    else
      op_name
    end
  end

  defp node_fill(node_id, node_states) do
    case Map.get(node_states, node_id, :pending) do
      :pending -> "#f5f5f5"
      :running -> "#e3f2fd"
      :completed -> "#e8f5e9"
      :failed -> "#ffebee"
      :waiting -> "#fff8e1"
      _ -> "#f5f5f5"
    end
  end

  defp node_stroke(node_id, node_states, selected_node) do
    if node_id == selected_node do
      "#1565c0"
    else
      case Map.get(node_states, node_id, :pending) do
        :pending -> "#bdbdbd"
        :running -> "#1976d2"
        :completed -> "#388e3c"
        :failed -> "#d32f2f"
        :waiting -> "#f9a825"
        _ -> "#bdbdbd"
      end
    end
  end

  defp edge_x1(layout, edge) do
    source = layout.nodes[edge.from]

    case layout.direction do
      :ttb -> source.x
      _ -> source.x + @hw
    end
  end

  defp edge_y1(layout, edge) do
    source = layout.nodes[edge.from]

    case layout.direction do
      :ttb -> source.y + @hh
      _ -> source.y
    end
  end

  defp edge_x2(layout, edge) do
    target = layout.nodes[edge.to]

    case layout.direction do
      :ttb -> target.x
      _ -> target.x - @hw
    end
  end

  defp edge_y2(layout, edge) do
    target = layout.nodes[edge.to]

    case layout.direction do
      :ttb -> target.y - @hh
      _ -> target.y
    end
  end
end
