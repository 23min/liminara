defmodule Liminara.Radar.Ops.Embed do
  @behaviour Liminara.Op

  alias Liminara.Radar.Ops.Specs

  def name, do: "radar_embed"
  def version, do: "1.0"
  def determinism, do: :pinned_env

  def execution_spec do
    Specs.port(name(), version(), :pinned_env, "radar_embed", outputs: %{items: :artifact})
  end

  def execute(_inputs), do: raise("executed via :port")
end
