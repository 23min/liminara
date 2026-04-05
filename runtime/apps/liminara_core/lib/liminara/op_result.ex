defmodule Liminara.OpResult do
  @moduledoc """
  Canonical successful completion shape for op execution.
  """

  @type t :: %__MODULE__{
          outputs: map(),
          decisions: [map()],
          warnings: [map() | struct()]
        }

  defstruct outputs: %{}, decisions: [], warnings: []
end
