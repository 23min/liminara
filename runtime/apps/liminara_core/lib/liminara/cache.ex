defmodule Liminara.Cache do
  @moduledoc """
  ETS-based memoization cache for op outputs.

  Cache key is computed from op name, version, and sorted input hashes.
  Only `:pure` and `:pinned_env` ops are cached; `:recordable` and
  `:side_effecting` ops are never cached.
  """

  alias Liminara.{Canonical, Hash}

  @doc """
  Look up cached outputs for an op with given input hashes.

  Returns `{:hit, output_hashes}` or `:miss`.
  """
  @spec lookup(:ets.table(), module(), [String.t()]) :: {:hit, map()} | :miss
  def lookup(table, op_module, input_hashes) do
    key = cache_key(op_module, input_hashes)

    case :ets.lookup(table, key) do
      [{^key, output_hashes}] -> {:hit, output_hashes}
      [] -> :miss
    end
  end

  @doc """
  Store op outputs in the cache.
  """
  @spec store(:ets.table(), module(), [String.t()], map()) :: :ok
  def store(table, op_module, input_hashes, output_hashes) do
    key = cache_key(op_module, input_hashes)
    :ets.insert(table, {key, output_hashes})
    :ok
  end

  @doc """
  Clear all cache entries.
  """
  @spec clear(:ets.table()) :: :ok
  def clear(table) do
    :ets.delete_all_objects(table)
    :ok
  end

  @doc """
  Returns true if the op's determinism class allows caching.
  """
  @spec cacheable?(module()) :: boolean()
  def cacheable?(op_module) do
    op_module.determinism() in [:pure, :pinned_env]
  end

  defp cache_key(op_module, input_hashes) do
    sorted_hashes = Enum.sort(input_hashes)

    %{
      "input_hashes" => sorted_hashes,
      "op_name" => op_module.name(),
      "op_version" => op_module.version()
    }
    |> Canonical.encode_to_iodata()
    |> Hash.hash_bytes()
  end
end
