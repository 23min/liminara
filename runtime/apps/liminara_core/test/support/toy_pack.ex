defmodule Liminara.ToyPack do
  @moduledoc """
  Toy pack exercising all four determinism classes + gates + binary artifacts.

  Plan: parse → enrich → gate → render → deliver
  """
  @behaviour Liminara.Pack

  @impl true
  def id, do: :toy_pack

  @impl true
  def version, do: "0.1.0"

  @impl true
  def ops do
    [
      Liminara.ToyOps.Parse,
      Liminara.ToyOps.Enrich,
      Liminara.ToyOps.Gate,
      Liminara.ToyOps.Render,
      Liminara.ToyOps.Deliver
    ]
  end

  @impl true
  def plan(input) do
    Liminara.Plan.new()
    |> Liminara.Plan.add_node("parse", Liminara.ToyOps.Parse, %{
      "text" => {:literal, input}
    })
    |> Liminara.Plan.add_node("enrich", Liminara.ToyOps.Enrich, %{
      "data" => {:ref, "parse", "result"}
    })
    |> Liminara.Plan.add_node("gate", Liminara.ToyOps.Gate, %{
      "data" => {:ref, "enrich", "result"}
    })
    |> Liminara.Plan.add_node("render", Liminara.ToyOps.Render, %{
      "data" => {:ref, "gate", "result"}
    })
    |> Liminara.Plan.add_node("deliver", Liminara.ToyOps.Deliver, %{
      "data" => {:ref, "render", "result"}
    })
  end
end

defmodule Liminara.ToyOps.Parse do
  @moduledoc "Pure op: parse input text into structured data."
  @behaviour Liminara.Op

  @impl true
  def name, do: "parse"
  @impl true
  def version, do: "1.0"
  @impl true
  def determinism, do: :pure

  @impl true
  def execute(%{"text" => text}) do
    result = Jason.encode!(%{"parsed" => true, "content" => String.upcase(text)})
    {:ok, %{"result" => result}}
  end
end

defmodule Liminara.ToyOps.Enrich do
  @moduledoc "Recordable op: simulates LLM enrichment."
  @behaviour Liminara.Op

  @impl true
  def name, do: "enrich"
  @impl true
  def version, do: "1.0"
  @impl true
  def determinism, do: :recordable

  @impl true
  def execute(%{"data" => data}) do
    enriched = "enriched:#{data}"

    decision = %{
      "decision_type" => "llm_response",
      "inputs" => %{"data_hash" => Liminara.Hash.hash_bytes(data)},
      "output" => %{"response" => enriched}
    }

    {:ok, %{"result" => enriched}, [decision]}
  end
end

defmodule Liminara.ToyOps.Gate do
  @moduledoc """
  Gate op: recordable op with gate semantics.

  Returns `{:gate, prompt}` to signal the Run.Server should pause
  and wait for external resolution.
  """
  @behaviour Liminara.Op

  @impl true
  def name, do: "gate"
  @impl true
  def version, do: "1.0"
  @impl true
  def determinism, do: :recordable

  @impl true
  def execute(%{"data" => data}) do
    {:gate, %{"prompt" => "Approve enriched data?", "data_preview" => String.slice(data, 0, 100)}}
  end
end

defmodule Liminara.ToyOps.Render do
  @moduledoc "Pinned-env op: produces a binary artifact (simulated PDF)."
  @behaviour Liminara.Op

  @impl true
  def name, do: "render"
  @impl true
  def version, do: "1.0"
  @impl true
  def determinism, do: :pinned_env

  @impl true
  def execute(%{"data" => data}) do
    # Simulated PDF: binary blob with a header
    pdf = "%PDF-SIMULATED\n#{data}\n%%EOF"
    {:ok, %{"result" => pdf}}
  end
end

defmodule Liminara.ToyOps.Deliver do
  @moduledoc "Side-effecting op: simulates delivery."
  @behaviour Liminara.Op

  @impl true
  def name, do: "deliver"
  @impl true
  def version, do: "1.0"
  @impl true
  def determinism, do: :side_effecting

  @impl true
  def execute(%{"data" => data}) do
    {:ok, %{"result" => "delivered:#{String.slice(data, 0, 50)}"}}
  end
end
