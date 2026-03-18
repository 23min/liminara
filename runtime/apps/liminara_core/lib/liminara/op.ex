defmodule Liminara.Op do
  @moduledoc """
  Behaviour for Liminara operations.

  An op is a typed function (inputs → outputs) with a determinism class
  that controls caching and replay behaviour.
  """

  @type determinism :: :pure | :pinned_env | :recordable | :side_effecting

  @doc "Op identifier."
  @callback name() :: String.t()

  @doc "Op version (used in cache key computation)."
  @callback version() :: String.t()

  @doc "Determinism class — controls caching and replay."
  @callback determinism() :: determinism()

  @doc """
  Execute the op with the given inputs.

  Returns `{:ok, outputs}` for deterministic ops, or
  `{:ok, outputs, decisions}` for recordable ops that produce decisions.
  """
  @callback execute(inputs :: map()) ::
              {:ok, map()} | {:ok, map(), list()} | {:error, term()}
end
