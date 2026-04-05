defmodule Liminara.Radar.Ops.LlmDedupCheck do
  @behaviour Liminara.Op

  @env_vars ["ANTHROPIC_API_KEY"]

  alias Liminara.Radar.Ops.Specs

  def name, do: "radar_llm_dedup"
  def version, do: "1.0"
  def determinism, do: :recordable

  def execution_spec do
    Specs.port(name(), version(), :recordable, "radar_llm_dedup",
      env_vars: @env_vars,
      decisions: true,
      warnings: true
    )
  end

  def execute(_inputs), do: raise("executed via :port")
end
