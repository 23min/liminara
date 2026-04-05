defmodule Liminara.ExecutionContext do
  @moduledoc """
  Runtime-owned execution metadata injected into eligible ops.
  """

  @type t :: %__MODULE__{
          run_id: String.t() | nil,
          started_at: String.t() | nil,
          pack_id: String.t() | nil,
          pack_version: String.t() | nil,
          replay_of_run_id: String.t() | nil,
          topic_id: String.t() | nil
        }

  defstruct [:run_id, :started_at, :pack_id, :pack_version, :replay_of_run_id, :topic_id]
end
