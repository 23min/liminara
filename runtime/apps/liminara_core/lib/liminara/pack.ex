defmodule Liminara.Pack do
  @moduledoc """
  Behaviour for Liminara packs.

  A pack provides op definitions and a plan builder. It is the unit
  of composition — each domain (Radar, House Compiler, etc.) is a pack.
  """

  @doc "Pack identifier."
  @callback id() :: atom()

  @doc "Pack version."
  @callback version() :: String.t()

  @doc "List of op modules this pack provides."
  @callback ops() :: [module()]

  @doc "Build a plan from input."
  @callback plan(input :: term()) :: Liminara.Plan.t()
end
