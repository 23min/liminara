defmodule Liminara.Radar.Ops.Rank do
  @behaviour Liminara.Op

  alias Liminara.Radar.Ops.Specs

  def name, do: "radar_rank"
  def version, do: "1.0"
  def determinism, do: :pure

  def execution_spec do
    Specs.port(name(), version(), :pure, "radar_rank", outputs: %{ranked_clusters: :artifact})
  end

  def execute(_inputs), do: raise("executed via :port")
end
