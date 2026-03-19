defmodule Liminara.Decision.Store do
  @moduledoc """
  Decision record storage for nondeterministic choices.

  Each recordable op execution produces one decision record stored as
  canonical JSON at `{runs_root}/{run_id}/decisions/{node_id}.json`.

  The `decision_hash` is computed over all fields except itself,
  then included in the stored record.

  Can be used in two modes:
  - **Supervised** (without runs_root): calls go through the named GenServer.
  - **Direct** (with explicit runs_root): stateless, for tests or standalone use.
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

  @doc "Read a decision record via the supervised process."
  @spec get(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(run_id, node_id) when is_binary(run_id) and is_binary(node_id) do
    GenServer.call(__MODULE__, {:get, run_id, node_id})
  end

  @doc "Verify a decision record via the supervised process."
  @spec verify(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :hash_mismatch} | {:error, :not_found}
  def verify(run_id, node_id) when is_binary(run_id) and is_binary(node_id) do
    GenServer.call(__MODULE__, {:verify, run_id, node_id})
  end

  # ── Direct API (stateless, explicit runs_root) ──────────────────

  @doc """
  Write a decision record and return its hash.

  Computes `decision_hash` over all fields except `decision_hash` itself.
  If the record already contains a `decision_hash`, it is replaced.
  """
  @spec put(Path.t(), String.t(), map()) :: {:ok, String.t()}
  def put(runs_root, run_id, record) do
    decision_hash = Hash.hash_decision(record)

    full_record = Map.put(record, "decision_hash", decision_hash)
    node_id = record["node_id"]

    path = node_path(runs_root, run_id, node_id)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Canonical.encode(full_record))

    {:ok, decision_hash}
  end

  @doc """
  Read a decision record by node_id.

  Returns `{:ok, record_with_hash}` or `{:error, :not_found}`.
  """
  @spec get(Path.t(), String.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(runs_root, run_id, node_id) do
    path = node_path(runs_root, run_id, node_id)

    if File.exists?(path) do
      {:ok, path |> File.read!() |> Jason.decode!()}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Verify a decision record's hash integrity.

  Returns `{:ok, decision_hash}` if valid, `{:error, :hash_mismatch}` if corrupted.
  """
  @spec verify(Path.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :hash_mismatch} | {:error, :not_found}
  def verify(runs_root, run_id, node_id) do
    case get(runs_root, run_id, node_id) do
      {:ok, record} ->
        expected = Hash.hash_decision(record)

        if record["decision_hash"] == expected do
          {:ok, expected}
        else
          {:error, :hash_mismatch}
        end

      {:error, :not_found} ->
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

  # ── Private ─────────────────────────────────────────────────────

  defp node_path(runs_root, run_id, node_id) do
    Path.join([runs_root, run_id, "decisions", "#{node_id}.json"])
  end
end
