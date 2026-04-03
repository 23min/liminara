defmodule Liminara.ReplayGapOps.EmitLiteral do
  @behaviour Liminara.Op

  @impl true
  def name, do: "emit_literal"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(%{"value" => value}) do
    {:ok, %{"result" => value}}
  end
end

defmodule Liminara.ReplayGapOps.MultiRecordable do
  @behaviour Liminara.Op

  @impl true
  def name, do: "multi_recordable"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :recordable

  @impl true
  def execute(%{"items" => items}) do
    responses = Enum.map(items, &("picked:" <> &1))

    decisions =
      Enum.map(items, fn item ->
        %{
          "decision_type" => "pick",
          "inputs" => %{"item" => item},
          "output" => %{"response" => "picked:" <> item}
        }
      end)

    {:ok, %{"count" => length(responses), "result" => responses}, decisions}
  end
end

defmodule Liminara.StoredPlanReplayPack do
  @behaviour Liminara.Pack

  @impl true
  def id, do: :stored_plan_replay_pack

  @impl true
  def version, do: "0.1.0"

  @impl true
  def ops do
    [Liminara.ReplayGapOps.EmitLiteral]
  end

  @impl true
  def plan(_input) do
    stamp = :erlang.unique_integer([:positive, :monotonic]) |> Integer.to_string()

    Liminara.Plan.new()
    |> Liminara.Plan.add_node("stamp", Liminara.ReplayGapOps.EmitLiteral, %{
      "value" => {:literal, stamp}
    })
  end
end

defmodule Liminara.MultiDecisionReplayPack do
  @behaviour Liminara.Pack

  @impl true
  def id, do: :multi_decision_replay_pack

  @impl true
  def version, do: "0.1.0"

  @impl true
  def ops do
    [Liminara.ReplayGapOps.MultiRecordable]
  end

  @impl true
  def plan(items) do
    Liminara.Plan.new()
    |> Liminara.Plan.add_node("multi", Liminara.ReplayGapOps.MultiRecordable, %{
      "items" => {:literal, items}
    })
  end
end
