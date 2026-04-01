defmodule Liminara.Radar.Ops.FetchWeb do
  @behaviour Liminara.Op

  def name, do: "radar_fetch_web"
  def version, do: "1.0"
  def determinism, do: :side_effecting
  def executor, do: :port
  def python_op, do: "radar_fetch_web"

  def execute(_inputs), do: raise("executed via :port")
end
