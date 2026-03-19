defmodule Liminara.TestOps.Upcase do
  @behaviour Liminara.Op

  @impl true
  def name, do: "upcase"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(%{"text" => text}) do
    {:ok, %{"result" => String.upcase(text)}}
  end
end

defmodule Liminara.TestOps.Concat do
  @behaviour Liminara.Op

  @impl true
  def name, do: "concat"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(%{"a" => a, "b" => b}) do
    {:ok, %{"result" => a <> b}}
  end
end

defmodule Liminara.TestOps.Fail do
  @behaviour Liminara.Op

  @impl true
  def name, do: "fail"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(_inputs) do
    {:error, :intentional_failure}
  end
end

defmodule Liminara.TestOps.Identity do
  @moduledoc "Pure op that passes input through unchanged. Good for testing pipelines."
  @behaviour Liminara.Op

  @impl true
  def name, do: "identity"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(inputs) do
    {:ok, inputs}
  end
end

defmodule Liminara.TestOps.Reverse do
  @moduledoc "Pure op that reverses a string."
  @behaviour Liminara.Op

  @impl true
  def name, do: "reverse"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(%{"text" => text}) do
    {:ok, %{"result" => String.reverse(text)}}
  end
end

defmodule Liminara.TestOps.Recordable do
  @behaviour Liminara.Op

  @impl true
  def name, do: "recordable_op"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :recordable

  @impl true
  def execute(%{"prompt" => prompt}) do
    decision = %{
      "decision_type" => "llm_response",
      "inputs" => %{"prompt" => prompt},
      "output" => %{"response" => "Generated response for: #{prompt}"}
    }

    {:ok, %{"result" => "Generated response for: #{prompt}"}, [decision]}
  end
end

defmodule Liminara.TestOps.SideEffect do
  @moduledoc "Side-effecting op that writes to a file (simulated)."
  @behaviour Liminara.Op

  @impl true
  def name, do: "side_effect"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :side_effecting

  @impl true
  def execute(%{"data" => data}) do
    # Simulate a side effect (in real use: send email, write to external DB, etc.)
    {:ok, %{"result" => "side_effect_done:#{data}"}}
  end
end

defmodule Liminara.TestOps.Slow do
  @moduledoc "Pure op that sleeps before returning. For testing timeouts and mid-run inspection."
  @behaviour Liminara.Op

  @impl true
  def name, do: "slow"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(%{"text" => text}) do
    Process.sleep(500)
    {:ok, %{"result" => String.upcase(text)}}
  end
end
