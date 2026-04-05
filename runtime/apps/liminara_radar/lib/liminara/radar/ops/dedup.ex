defmodule Liminara.Radar.Ops.Dedup do
  @behaviour Liminara.Op

  alias Liminara.ExecutionSpec

  def name, do: "radar_dedup"
  def version, do: "1.0"
  def determinism, do: :side_effecting

  def execution_spec do
    ExecutionSpec.new(%{
      identity: %{name: "radar_dedup", version: "1.0"},
      determinism: %{class: :side_effecting, cache_policy: :none, replay_policy: :replay_recorded},
      execution: %{
        executor: :port,
        entrypoint: "radar_dedup",
        requires_execution_context: true
      },
      contracts: %{outputs: %{result: :artifact, dedup_stats: :artifact}}
    })
  end

  def execute(_inputs), do: raise("executed via :port")
end
