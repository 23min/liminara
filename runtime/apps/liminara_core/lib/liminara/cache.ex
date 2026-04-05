defmodule Liminara.Cache do
  @moduledoc """
  ETS-based memoization cache for op outputs.

  Cache key is computed from canonical op identity and sorted input hashes.
  Canonically `:pure` ops are cached. `:pinned_env` caching stays disabled
  until the runtime includes an environment hash in the cache key.

  Can be used in two modes:
  - **Supervised** (without table arg): uses the named ETS table owned by this GenServer.
  - **Direct** (with explicit table arg): for tests or standalone use.
  """

  use GenServer

  alias Liminara.{Canonical, Hash, Op}

  # ── Supervised API (process-backed) ─────────────────────────────

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Look up cached outputs via the supervised process's ETS table."
  @spec lookup(module(), [String.t()]) :: {:hit, map()} | :miss
  def lookup(op_module, input_hashes) when is_atom(op_module) and is_list(input_hashes) do
    lookup(__MODULE__, op_module, input_hashes)
  end

  @doc "Store op outputs via the supervised process's ETS table."
  @spec store(module(), [String.t()], map()) :: :ok
  def store(op_module, input_hashes, output_hashes)
      when is_atom(op_module) and is_list(input_hashes) do
    store(__MODULE__, op_module, input_hashes, output_hashes)
  end

  @doc "Clear all cache entries in the supervised process's ETS table."
  @spec clear() :: :ok
  def clear do
    clear(__MODULE__)
  end

  # ── Direct API (stateless, explicit table) ──────────────────────

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

  Ops that require execution context stay uncached until the runtime includes
  execution context in the cache key.
  """
  @spec cacheable?(module()) :: boolean()
  def cacheable?(op_module) do
    spec = Op.execution_spec(op_module)

    cond do
      spec.execution.requires_execution_context ->
        false

      true ->
        case spec.determinism.cache_policy do
          :content_addressed -> true
          :content_addressed_with_environment -> false
          :none -> false
          nil -> spec.determinism.class == :pure
          _ -> false
        end
    end
  end

  # ── GenServer callbacks ─────────────────────────────────────────

  @impl true
  def init(_opts) do
    table = :ets.new(__MODULE__, [:set, :public, :named_table])
    {:ok, %{table: table}}
  end

  # ── Private ─────────────────────────────────────────────────────

  defp cache_key(op_module, input_hashes) do
    spec = Op.execution_spec(op_module)
    sorted_hashes = Enum.sort(input_hashes)

    %{
      "input_hashes" => sorted_hashes,
      "op_name" => spec.identity.name || op_module.name(),
      "op_version" => spec.identity.version || op_module.version()
    }
    |> Canonical.encode_to_iodata()
    |> Hash.hash_bytes()
  end
end
