defmodule Liminara.ExecutionContext do
  @moduledoc """
  Runtime-owned execution metadata injected into eligible ops.
  """

  defstruct [:run_id, :started_at, :pack_id, :pack_version, :replay_of_run_id, :topic_id]
end
