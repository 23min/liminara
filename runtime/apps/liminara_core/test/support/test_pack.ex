defmodule Liminara.TestPack do
  @moduledoc "Test pack exercising pure, recordable, and side-effecting ops."
  @behaviour Liminara.Pack

  @impl true
  def id, do: :test_pack

  @impl true
  def version, do: "0.1.0"

  @impl true
  def ops do
    [
      Liminara.TestOps.Upcase,
      Liminara.TestOps.Recordable,
      Liminara.TestOps.SideEffect
    ]
  end

  @impl true
  def plan(input) do
    Liminara.Plan.new()
    |> Liminara.Plan.add_node("load", Liminara.TestOps.Upcase, %{
      "text" => {:literal, input}
    })
    |> Liminara.Plan.add_node("transform", Liminara.TestOps.Recordable, %{
      "prompt" => {:ref, "load", "result"}
    })
    |> Liminara.Plan.add_node("save", Liminara.TestOps.SideEffect, %{
      "data" => {:ref, "transform", "result"}
    })
  end
end
