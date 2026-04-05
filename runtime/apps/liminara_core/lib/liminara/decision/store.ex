defmodule Liminara.Decision.Store do
  @moduledoc """
  Decision record storage for nondeterministic choices.

  Stores a list of decision records per node as canonical JSON at
  `{runs_root}/{run_id}/decisions/{node_id}.json`.

    File format:
      {"decisions": [...], "output_hashes": {...} | null, "warnings": [...] | null}

  Each `put/3` call appends one decision to the list. `get/3` always
  returns a list (single-decision nodes return a one-element list).

  Backward compatible: files written in the old single-object format
  are loaded as a one-element list.
  """

  use GenServer

  alias Liminara.{Canonical, Hash}

  # ── Supervised API (process-backed) ─────────────────────────────

  def start_link(opts) do
    runs_root = Keyword.fetch!(opts, :runs_root)
    GenServer.start_link(__MODULE__, runs_root, name: __MODULE__)
  end

  @doc "Write a decision record via the supervised process."
  @spec put(String.t(), map()) :: {:ok, String.t()}
  def put(run_id, record) when is_binary(run_id) and is_map(record) do
    GenServer.call(__MODULE__, {:put, run_id, record})
  end

  @doc "Read decision records via the supervised process. Always returns a list."
  @spec get(String.t(), String.t()) :: {:ok, [map()]} | {:error, :not_found}
  def get(run_id, node_id) when is_binary(run_id) and is_binary(node_id) do
    GenServer.call(__MODULE__, {:get, run_id, node_id})
  end

  @doc "Verify decision records via the supervised process."
  @spec verify(String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, :hash_mismatch} | {:error, :not_found}
  def verify(run_id, node_id) when is_binary(run_id) and is_binary(node_id) do
    GenServer.call(__MODULE__, {:verify, run_id, node_id})
  end

  @doc "Store output hashes for a node via the supervised process."
  @spec put_outputs(String.t(), String.t(), map()) :: :ok
  def put_outputs(run_id, node_id, output_hashes)
      when is_binary(run_id) and is_binary(node_id) and is_map(output_hashes) do
    GenServer.call(__MODULE__, {:put_outputs, run_id, node_id, output_hashes})
  end

  @doc "Read output hashes for a node via the supervised process."
  @spec get_outputs(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_outputs(run_id, node_id) when is_binary(run_id) and is_binary(node_id) do
    GenServer.call(__MODULE__, {:get_outputs, run_id, node_id})
  end

  @doc "Store warnings for a node via the supervised process."
  @spec put_warnings(String.t(), String.t(), [map()]) :: :ok
  def put_warnings(run_id, node_id, warnings)
      when is_binary(run_id) and is_binary(node_id) and is_list(warnings) do
    GenServer.call(__MODULE__, {:put_warnings, run_id, node_id, warnings})
  end

  @doc "Read warnings for a node via the supervised process."
  @spec get_warnings(String.t(), String.t()) :: {:ok, [map()]} | {:error, :not_found}
  def get_warnings(run_id, node_id) when is_binary(run_id) and is_binary(node_id) do
    GenServer.call(__MODULE__, {:get_warnings, run_id, node_id})
  end

  # ── Direct API (stateless, explicit runs_root) ──────────────────

  @doc """
  Append a decision record and return its hash.

  Computes `decision_hash` over all fields except `decision_hash` itself.
  Appends to the decisions list in `{node_id}.json`.
  """
  @spec put(Path.t(), String.t(), map()) :: {:ok, String.t()}
  def put(runs_root, run_id, record) do
    decision_hash = Hash.hash_decision(record)
    full_record = Map.put(record, "decision_hash", decision_hash)
    node_id = record["node_id"]

    path = node_path(runs_root, run_id, node_id)
    File.mkdir_p!(Path.dirname(path))

    wrapper = read_wrapper(path)
    updated = Map.put(wrapper, "decisions", wrapper["decisions"] ++ [full_record])
    File.write!(path, Canonical.encode(updated))

    {:ok, decision_hash}
  end

  @doc """
  Read all decision records for a node_id. Always returns a list.
  """
  @spec get(Path.t(), String.t(), String.t()) :: {:ok, [map()]} | {:error, :not_found}
  def get(runs_root, run_id, node_id) do
    path = node_path(runs_root, run_id, node_id)

    if File.exists?(path) do
      content = path |> File.read!() |> Jason.decode!()

      case content do
        %{"decisions" => decisions} -> {:ok, decisions}
        %{} -> {:ok, [content]}
      end
    else
      {:error, :not_found}
    end
  end

  @doc """
  Verify all decision records' hash integrity.

  Returns `{:ok, [hash, ...]}` if all valid, `{:error, :hash_mismatch}` if any corrupted.
  """
  @spec verify(Path.t(), String.t(), String.t()) ::
          {:ok, [String.t()]} | {:error, :hash_mismatch} | {:error, :not_found}
  def verify(runs_root, run_id, node_id) do
    case get(runs_root, run_id, node_id) do
      {:ok, decisions} ->
        verify_decisions(decisions)

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp verify_decisions(decisions) do
    decisions
    |> Enum.reduce_while({:ok, []}, fn record, {:ok, hashes} ->
      case verify_decision(record) do
        {:ok, hash} -> {:cont, {:ok, [hash | hashes]}}
        :mismatch -> {:halt, {:error, :hash_mismatch}}
      end
    end)
    |> case do
      {:ok, hashes} -> {:ok, Enum.reverse(hashes)}
      {:error, :hash_mismatch} = error -> error
    end
  end

  defp verify_decision(record) do
    expected = Hash.hash_decision(record)

    if record["decision_hash"] == expected do
      {:ok, expected}
    else
      :mismatch
    end
  end

  @doc """
  Store output hashes for a node. Used during discovery so replay
  can restore the correct output map without re-executing.
  """
  @spec put_outputs(Path.t(), String.t(), String.t(), map()) :: :ok
  def put_outputs(runs_root, run_id, node_id, output_hashes) do
    path = node_path(runs_root, run_id, node_id)
    File.mkdir_p!(Path.dirname(path))

    wrapper = read_wrapper(path)
    updated = Map.put(wrapper, "output_hashes", output_hashes)
    File.write!(path, Canonical.encode(updated))

    :ok
  end

  @doc """
  Read stored output hashes for a node.
  """
  @spec get_outputs(Path.t(), String.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_outputs(runs_root, run_id, node_id) do
    path = node_path(runs_root, run_id, node_id)

    if File.exists?(path) do
      content = path |> File.read!() |> Jason.decode!()

      case content do
        %{"output_hashes" => hashes} when is_map(hashes) -> {:ok, hashes}
        _ -> {:error, :not_found}
      end
    else
      {:error, :not_found}
    end
  end

  @doc "Store warnings for a node so replay can preserve discovery warnings."
  @spec put_warnings(Path.t(), String.t(), String.t(), [map()]) :: :ok
  def put_warnings(runs_root, run_id, node_id, warnings) do
    path = node_path(runs_root, run_id, node_id)
    File.mkdir_p!(Path.dirname(path))

    wrapper = read_wrapper(path)
    updated = Map.put(wrapper, "warnings", warnings)
    File.write!(path, Canonical.encode(updated))

    :ok
  end

  @doc "Read stored warnings for a node."
  @spec get_warnings(Path.t(), String.t(), String.t()) :: {:ok, [map()]} | {:error, :not_found}
  def get_warnings(runs_root, run_id, node_id) do
    path = node_path(runs_root, run_id, node_id)

    if File.exists?(path) do
      content = path |> File.read!() |> Jason.decode!()

      case content do
        %{"warnings" => warnings} when is_list(warnings) -> {:ok, warnings}
        _ -> {:error, :not_found}
      end
    else
      {:error, :not_found}
    end
  end

  # ── GenServer callbacks ─────────────────────────────────────────

  @impl true
  def init(runs_root) do
    File.mkdir_p!(runs_root)
    {:ok, %{runs_root: runs_root}}
  end

  @impl true
  def handle_call({:put, run_id, record}, _from, %{runs_root: root} = state) do
    {:reply, put(root, run_id, record), state}
  end

  def handle_call({:get, run_id, node_id}, _from, %{runs_root: root} = state) do
    {:reply, get(root, run_id, node_id), state}
  end

  def handle_call({:verify, run_id, node_id}, _from, %{runs_root: root} = state) do
    {:reply, verify(root, run_id, node_id), state}
  end

  def handle_call(
        {:put_outputs, run_id, node_id, output_hashes},
        _from,
        %{runs_root: root} = state
      ) do
    {:reply, put_outputs(root, run_id, node_id, output_hashes), state}
  end

  def handle_call({:get_outputs, run_id, node_id}, _from, %{runs_root: root} = state) do
    {:reply, get_outputs(root, run_id, node_id), state}
  end

  def handle_call({:put_warnings, run_id, node_id, warnings}, _from, %{runs_root: root} = state) do
    {:reply, put_warnings(root, run_id, node_id, warnings), state}
  end

  def handle_call({:get_warnings, run_id, node_id}, _from, %{runs_root: root} = state) do
    {:reply, get_warnings(root, run_id, node_id), state}
  end

  # ── Private ─────────────────────────────────────────────────────

  defp node_path(runs_root, run_id, node_id) do
    Path.join([runs_root, run_id, "decisions", "#{node_id}.json"])
  end

  defp read_wrapper(path) do
    if File.exists?(path) do
      content = path |> File.read!() |> Jason.decode!()

      case content do
        %{"decisions" => _} = wrapper ->
          wrapper
          |> Map.put_new("output_hashes", nil)
          |> Map.put_new("warnings", nil)

        %{} ->
          %{"decisions" => [content], "output_hashes" => nil, "warnings" => nil}
      end
    else
      %{"decisions" => [], "output_hashes" => nil, "warnings" => nil}
    end
  end
end
