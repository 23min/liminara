defmodule Liminara do
  @moduledoc """
  Public API for the Liminara runtime.

  Entry points for running and replaying packs.
  """

  alias Liminara.Run

  @doc """
  Run a pack with the given input.

  Builds the plan from the pack module and executes it.
  """
  @spec run(module(), term(), keyword()) :: {:ok, Run.Result.t()}
  def run(pack_module, input, opts \\ []) do
    plan = pack_module.plan(input)

    Run.execute(plan,
      pack_id: Atom.to_string(pack_module.id()),
      pack_version: pack_module.version(),
      store_root: Keyword.fetch!(opts, :store_root),
      runs_root: Keyword.fetch!(opts, :runs_root),
      cache: Keyword.get(opts, :cache)
    )
  end

  @doc """
  Replay a previous run with stored decisions.

  Recordable ops inject stored decisions instead of executing.
  Side-effecting ops are skipped.
  """
  @spec replay(module(), term(), String.t(), keyword()) :: {:ok, Run.Result.t()}
  def replay(pack_module, input, replay_run_id, opts \\ []) do
    plan = pack_module.plan(input)

    Run.execute(plan,
      pack_id: Atom.to_string(pack_module.id()),
      pack_version: pack_module.version(),
      store_root: Keyword.fetch!(opts, :store_root),
      runs_root: Keyword.fetch!(opts, :runs_root),
      cache: Keyword.get(opts, :cache),
      replay: replay_run_id
    )
  end
end
