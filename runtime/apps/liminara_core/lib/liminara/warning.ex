defmodule Liminara.Warning do
  @moduledoc """
  Structured warning payload for warning-bearing success.
  """

  defstruct [:code, :severity, :summary, :cause, :remediation, affected_outputs: []]
end
