defmodule LiminaraCore do
  @moduledoc """
  Liminara runtime kernel — the core runtime for reproducible nondeterministic computation.
  """

  @doc """
  Returns the current version of LiminaraCore.
  """
  @spec version() :: String.t()
  def version do
    Application.spec(:liminara_core, :vsn) |> to_string()
  end
end
