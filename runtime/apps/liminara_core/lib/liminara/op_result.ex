defmodule Liminara.OpResult do
  @moduledoc """
  Canonical successful completion shape for op execution.
  """

  defstruct outputs: %{}, decisions: [], warnings: []
end
