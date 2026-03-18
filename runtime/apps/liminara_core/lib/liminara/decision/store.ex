defmodule Liminara.Decision.Store do
  @moduledoc """
  Decision record storage for nondeterministic choices.

  Each recordable op execution produces one decision record stored as
  canonical JSON at `{runs_root}/{run_id}/decisions/{node_id}.json`.

  The `decision_hash` is computed over all fields except itself,
  then included in the stored record.
  """

  alias Liminara.{Canonical, Hash}

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

  defp node_path(runs_root, run_id, node_id) do
    Path.join([runs_root, run_id, "decisions", "#{node_id}.json"])
  end
end
