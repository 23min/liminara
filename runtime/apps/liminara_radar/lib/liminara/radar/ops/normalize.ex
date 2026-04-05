defmodule Liminara.Radar.Ops.Normalize do
  @behaviour Liminara.Op

  alias Liminara.Radar.Ops.Specs

  def name, do: "radar_normalize"
  def version, do: "1.0"
  def determinism, do: :pure

  def execution_spec do
    Specs.port(name(), version(), :pure, "radar_normalize", outputs: %{items: :artifact})
  end

  def execute(_inputs), do: raise("executed via :port")
end
