defmodule Liminara.Radar.Ops.FetchRss do
  @behaviour Liminara.Op

  alias Liminara.Radar.Ops.Specs

  def name, do: "radar_fetch_rss"
  def version, do: "1.0"
  def determinism, do: :side_effecting

  def execution_spec do
    Specs.port(name(), version(), :side_effecting, "radar_fetch_rss", warnings: true)
  end

  def execute(_inputs), do: raise("executed via :port")
end
