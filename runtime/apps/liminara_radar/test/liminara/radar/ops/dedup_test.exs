defmodule Liminara.Radar.Ops.DedupTest do
  use ExUnit.Case, async: true

  alias Liminara.Op
  alias Liminara.Radar.Ops.Dedup

  describe "Op behaviour" do
    test "name" do
      assert Dedup.name() == "radar_dedup"
    end

    test "exposes a truthful explicit execution spec" do
      spec = Op.execution_spec(Dedup)

      assert spec.identity.name == "radar_dedup"
      assert spec.identity.version == "1.0"
      assert spec.determinism.class == :side_effecting
      assert spec.determinism.cache_policy == :none
      assert spec.determinism.replay_policy == :replay_recorded
      assert spec.execution.executor == :port
      assert spec.execution.entrypoint == "radar_dedup"
      assert spec.execution.requires_execution_context == true
    end
  end
end