defmodule Liminara.Radar.Ops.Rank do
  @behaviour Liminara.Op

  def name, do: "radar_rank"
  def version, do: "1.0"
  def determinism, do: :pure
  def executor, do: :port
  def python_op, do: "radar_rank"

  def execute(_inputs), do: raise("executed via :port")
end
