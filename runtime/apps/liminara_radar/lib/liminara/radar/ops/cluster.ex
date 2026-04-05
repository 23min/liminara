defmodule Liminara.Radar.Ops.Cluster do
  @behaviour Liminara.Op

  alias Liminara.Radar.Ops.Specs

  def name, do: "radar_cluster"
  def version, do: "1.0"
  def determinism, do: :pure

  def execution_spec do
    Specs.port(name(), version(), :pure, "radar_cluster", outputs: %{clusters: :artifact})
  end

  def execute(_inputs), do: raise("executed via :port")
end
