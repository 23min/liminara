defmodule Liminara.Radar.Ops.Embed do
  @behaviour Liminara.Op

  def name, do: "radar_embed"
  def version, do: "1.0"
  def determinism, do: :pinned_env
  def executor, do: :port
  def python_op, do: "radar_embed"

  def execute(_inputs), do: raise("executed via :port")
end
