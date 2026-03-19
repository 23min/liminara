defmodule Liminara do
  @moduledoc """
  Public API for the Liminara runtime.

  Entry points for running and replaying packs.

  Two modes:
  - **Supervised** (no store_root/runs_root opts): routes through Run.Server GenServer
    and supervised stores. Requires the OTP application to be running.
  - **Direct** (with explicit store_root/runs_root): uses the synchronous Run.execute/2
    path. For standalone scripts or tests that manage their own directories.
  """

  alias Liminara.Run

  @doc """
  Run a pack with the given input.

  When called without `:store_root` / `:runs_root`, uses the supervised
  Run.Server GenServer path. When called with those options, falls back
  to the synchronous `Run.execute/2`.
  """
  @spec run(module(), term(), keyword()) :: {:ok, Run.Result.t()}
  def run(pack_module, input, opts \\ []) do
    plan = pack_module.plan(input)
    pack_id = Atom.to_string(pack_module.id())
    pack_version = pack_module.version()

    if Keyword.has_key?(opts, :store_root) do
      # Direct / synchronous path
      Run.execute(plan,
        pack_id: pack_id,
        pack_version: pack_version,
        store_root: Keyword.fetch!(opts, :store_root),
        runs_root: Keyword.fetch!(opts, :runs_root),
        cache: Keyword.get(opts, :cache)
      )
    else
      # Supervised GenServer path
      run_id = generate_run_id(pack_id)

      {:ok, _pid} =
        Run.Server.start(run_id, plan,
          pack_id: pack_id,
          pack_version: pack_version
        )

      Run.Server.await(run_id)
    end
  end

  @doc """
  Replay a previous run with stored decisions.

  Recordable ops inject stored decisions instead of executing.
  Side-effecting ops are skipped.
  """
  @spec replay(module(), term(), String.t(), keyword()) :: {:ok, Run.Result.t()}
  def replay(pack_module, input, replay_run_id, opts \\ []) do
    plan = pack_module.plan(input)
    pack_id = Atom.to_string(pack_module.id())
    pack_version = pack_module.version()

    if Keyword.has_key?(opts, :store_root) do
      # Direct / synchronous path
      Run.execute(plan,
        pack_id: pack_id,
        pack_version: pack_version,
        store_root: Keyword.fetch!(opts, :store_root),
        runs_root: Keyword.fetch!(opts, :runs_root),
        cache: Keyword.get(opts, :cache),
        replay: replay_run_id
      )
    else
      # Supervised GenServer path
      run_id = generate_run_id(pack_id)

      {:ok, _pid} =
        Run.Server.start(run_id, plan,
          pack_id: pack_id,
          pack_version: pack_version,
          replay: replay_run_id
        )

      Run.Server.await(run_id)
    end
  end

  defp generate_run_id(pack_id) do
    now = DateTime.utc_now()
    ts = Calendar.strftime(now, "%Y%m%dT%H%M%S")
    rand = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{pack_id}-#{ts}-#{rand}"
  end
end
