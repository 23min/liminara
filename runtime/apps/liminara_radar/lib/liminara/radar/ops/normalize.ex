defmodule Liminara.Radar.Ops.Normalize do
  @behaviour Liminara.Op

  def name, do: "radar_normalize"
  def version, do: "1.0"
  def determinism, do: :pure
  def executor, do: :port
  def python_op, do: "radar_normalize"

  def execute(_inputs), do: raise("executed via :port")
end
