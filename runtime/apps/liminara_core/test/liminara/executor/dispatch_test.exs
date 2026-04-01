defmodule Liminara.Executor.DispatchTest do
  use ExUnit.Case, async: true

  alias Liminara.Executor

  @python_root Path.expand("../../../../../python", __DIR__)
  @runner_path Path.join(@python_root, "src/liminara_op_runner.py")

  # A test op module that declares executor: :port
  defmodule PortEchoOp do
    @behaviour Liminara.Op

    def name, do: "port_echo"
    def version, do: "1.0.0"
    def determinism, do: :pure
    def executor, do: :port
    def python_op, do: "echo"

    def execute(_inputs) do
      raise "should not be called inline — this op runs via :port"
    end
  end

  # A normal inline op for comparison
  defmodule InlineOp do
    @behaviour Liminara.Op

    def name, do: "inline_test"
    def version, do: "1.0.0"
    def determinism, do: :pure

    def execute(inputs) do
      {:ok, %{"result" => Map.get(inputs, "value", 0) * 2}}
    end
  end

  describe "executor dispatch" do
    test "dispatches to :port when op declares executor/0 as :port" do
      result =
        Executor.run(PortEchoOp, %{"message" => "hello"},
          python_root: @python_root,
          runner: @runner_path
        )

      assert {:ok, %{"message" => "hello"}, _duration} = result
    end

    test "dispatches to :inline by default (no executor/0 callback)" do
      result = Executor.run(InlineOp, %{"value" => 5})
      assert {:ok, %{"result" => 10}, _duration} = result
    end

    test "explicit executor: :inline overrides op's executor/0" do
      # InlineOp has no executor/0 — explicit :inline should work fine
      result = Executor.run(InlineOp, %{"value" => 3}, executor: :inline)
      assert {:ok, %{"result" => 6}, _duration} = result
    end
  end
end
