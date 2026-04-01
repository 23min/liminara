defmodule Liminara.DemoOps do
  @moduledoc """
  Simple ops for demos and interactive exploration.
  Not for production use.
  """

  defmodule Echo do
    @behaviour Liminara.Op
    def name, do: "echo"
    def version, do: "1.0"
    def determinism, do: :pure
    def execute(inputs), do: {:ok, inputs}
  end

  defmodule Upcase do
    @behaviour Liminara.Op
    def name, do: "upcase"
    def version, do: "1.0"
    def determinism, do: :pure

    def execute(%{"text" => text}) when is_binary(text) do
      {:ok, %{"result" => String.upcase(text)}}
    end
  end

  defmodule Reverse do
    @behaviour Liminara.Op
    def name, do: "reverse"
    def version, do: "1.0"
    def determinism, do: :pure

    def execute(%{"text" => text}) when is_binary(text) do
      {:ok, %{"result" => String.reverse(text)}}
    end
  end

  defmodule Concat do
    @behaviour Liminara.Op
    def name, do: "concat"
    def version, do: "1.0"
    def determinism, do: :pure

    def execute(%{"a" => a, "b" => b}) when is_binary(a) and is_binary(b) do
      {:ok, %{"result" => a <> b}}
    end
  end

  defmodule Approve do
    @behaviour Liminara.Op
    def name, do: "approve"
    def version, do: "1.0"
    def determinism, do: :side_effecting

    def execute(%{"text" => text}) do
      {:gate, "Please approve: #{text}"}
    end
  end
end
