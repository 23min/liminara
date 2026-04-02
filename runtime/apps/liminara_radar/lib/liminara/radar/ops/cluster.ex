defmodule Liminara.Radar.Ops.Cluster do
  @behaviour Liminara.Op

  def name, do: "radar_cluster"
  def version, do: "1.0"
  def determinism, do: :pure
  def executor, do: :port
  def python_op, do: "radar_cluster"

  def execute(_inputs), do: raise("executed via :port")
end
