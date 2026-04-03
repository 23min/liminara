defmodule Liminara.Radar.Ops.Summarize do
  @behaviour Liminara.Op

  def name, do: "radar_summarize"
  def version, do: "1.0"
  def determinism, do: :recordable
  def executor, do: :port
  def python_op, do: "radar_summarize"

  def env_vars, do: ["ANTHROPIC_API_KEY"]

  def execute(_inputs), do: raise("executed via :port")
end
