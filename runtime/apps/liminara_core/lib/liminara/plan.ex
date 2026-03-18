defmodule Liminara.Plan do
  @moduledoc """
  A computation plan — a DAG of nodes where each node names an op
  and declares its inputs as literals or references to other nodes.

  The plan is a pure data structure. Execution is handled by `Run.Server`.
  """

  alias Liminara.{Canonical, Hash}

  defstruct nodes: %{}, insert_order: []

  defmodule Node do
    @moduledoc false
    defstruct [:node_id, :op_module, :inputs]
  end

  @doc """
  Create an empty plan.
  """
  @spec new() :: %__MODULE__{}
  def new, do: %__MODULE__{}

  @doc """
  Add a node to the plan. Inputs is a map of `%{name => {:literal, value} | {:ref, node_id}}`.
  """
  @spec add_node(%__MODULE__{}, String.t(), module(), map()) :: %__MODULE__{}
  def add_node(%__MODULE__{} = plan, node_id, op_module, inputs \\ %{}) do
    node = %Node{node_id: node_id, op_module: op_module, inputs: inputs}

    %{
      plan
      | nodes: Map.put(plan.nodes, node_id, node),
        insert_order: plan.insert_order ++ [node_id]
    }
  end

  @doc """
  Return all node definitions as a map of `%{node_id => node}`.
  """
  @spec nodes(%__MODULE__{}) :: map()
  def nodes(%__MODULE__{nodes: nodes}), do: nodes

  @doc """
  Return a single node definition.
  """
  @spec get_node(%__MODULE__{}, String.t()) :: Node.t() | nil
  def get_node(%__MODULE__{nodes: nodes}, node_id), do: Map.get(nodes, node_id)

  @doc """
  Return node_ids that are ready to execute: all ref inputs are in the completed set,
  and the node itself is not yet completed.
  """
  @spec ready_nodes(%__MODULE__{}, MapSet.t()) :: [String.t()]
  def ready_nodes(%__MODULE__{nodes: nodes, insert_order: order}, completed) do
    order
    |> Enum.filter(fn node_id ->
      node_id not in completed and
        node_ready?(Map.fetch!(nodes, node_id), completed)
    end)
  end

  @doc """
  True when every node in the plan is in the completed set.
  """
  @spec all_complete?(%__MODULE__{}, MapSet.t()) :: boolean()
  def all_complete?(%__MODULE__{nodes: nodes}, completed) do
    nodes |> Map.keys() |> Enum.all?(&(&1 in completed))
  end

  @doc """
  Validate the plan: no duplicate node_ids (detected via insert_order),
  no dangling refs, no cycles.
  """
  @spec validate(%__MODULE__{}) :: :ok | {:error, term()}
  def validate(%__MODULE__{} = plan) do
    with :ok <- check_duplicates(plan),
         :ok <- check_dangling_refs(plan),
         :ok <- check_cycles(plan) do
      :ok
    end
  end

  @doc """
  Compute a deterministic hash of the plan structure.
  """
  @spec hash(%__MODULE__{}) :: String.t()
  def hash(%__MODULE__{insert_order: order} = plan) do
    serialized =
      Enum.map(order, fn node_id ->
        node = Map.fetch!(plan.nodes, node_id)

        %{
          "inputs" => serialize_inputs(node.inputs),
          "node_id" => node_id,
          "op_module" => Atom.to_string(node.op_module)
        }
      end)

    serialized
    |> Canonical.encode_to_iodata()
    |> Hash.hash_bytes()
  end

  # ── Private ──────────────────────────────────────────────────────

  defp node_ready?(%Node{inputs: inputs}, completed) do
    inputs
    |> Map.values()
    |> Enum.all?(fn
      {:literal, _} -> true
      {:ref, ref_id} -> ref_id in completed
      {:ref, ref_id, _output_key} -> ref_id in completed
    end)
  end

  defp check_duplicates(%__MODULE__{insert_order: order}) do
    case order -- Enum.uniq(order) do
      [] -> :ok
      [dup | _] -> {:error, {:duplicate_node, dup}}
    end
  end

  defp check_dangling_refs(%__MODULE__{nodes: nodes}) do
    node_ids = Map.keys(nodes) |> MapSet.new()

    Enum.reduce_while(nodes, :ok, fn {node_id, node}, :ok ->
      dangling =
        node.inputs
        |> Map.values()
        |> Enum.find(fn
          {:ref, ref_id} -> ref_id not in node_ids
          {:ref, ref_id, _key} -> ref_id not in node_ids
          _ -> false
        end)

      case dangling do
        {:ref, ref_id} -> {:halt, {:error, {:dangling_ref, node_id, ref_id}}}
        {:ref, ref_id, _key} -> {:halt, {:error, {:dangling_ref, node_id, ref_id}}}
        _ -> {:cont, :ok}
      end
    end)
  end

  defp check_cycles(%__MODULE__{nodes: nodes}) do
    # Kahn's algorithm for topological sort — if we can't sort all nodes, there's a cycle
    graph =
      Map.new(nodes, fn {node_id, node} ->
        deps =
          node.inputs
          |> Map.values()
          |> Enum.flat_map(fn
            {:ref, ref_id} -> [ref_id]
            {:ref, ref_id, _key} -> [ref_id]
            _ -> []
          end)

        {node_id, deps}
      end)

    # In-degree = number of dependencies each node has
    in_degree = Map.new(graph, fn {node_id, deps} -> {node_id, length(deps)} end)

    queue = for {node_id, 0} <- in_degree, do: node_id
    topo_sort(graph, in_degree, queue, 0, map_size(nodes))
  end

  defp topo_sort(_graph, _in_degree, [], sorted_count, total) do
    if sorted_count == total do
      :ok
    else
      {:error, {:cycle, "plan contains a cycle"}}
    end
  end

  defp topo_sort(graph, in_degree, [node_id | rest], sorted_count, total) do
    # Find nodes that depend on this node (nodes whose deps list includes node_id)
    dependents =
      graph
      |> Enum.filter(fn {_nid, deps} -> node_id in deps end)
      |> Enum.map(fn {nid, _} -> nid end)

    {new_in_degree, new_ready} =
      Enum.reduce(dependents, {in_degree, []}, fn dep, {deg, ready} ->
        new_deg = Map.update!(deg, dep, &(&1 - 1))

        if new_deg[dep] == 0 do
          {new_deg, [dep | ready]}
        else
          {new_deg, ready}
        end
      end)

    topo_sort(graph, new_in_degree, rest ++ new_ready, sorted_count + 1, total)
  end

  defp serialize_inputs(inputs) do
    Map.new(inputs, fn
      {name, {:literal, value}} -> {name, %{"type" => "literal", "value" => inspect(value)}}
      {name, {:ref, ref_id}} -> {name, %{"ref" => ref_id, "type" => "ref"}}
      {name, {:ref, ref_id, key}} -> {name, %{"key" => key, "ref" => ref_id, "type" => "ref"}}
    end)
  end
end
