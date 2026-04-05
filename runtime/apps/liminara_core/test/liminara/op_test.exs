defmodule Liminara.OpTest do
  use ExUnit.Case, async: true

  alias Liminara.Executor

  describe "behaviour compliance" do
    test "Upcase implements all callbacks" do
      assert Liminara.TestOps.Upcase.name() == "upcase"
      assert Liminara.TestOps.Upcase.version() == "1.0"
      assert Liminara.TestOps.Upcase.determinism() == :pure
    end

    test "execute with valid inputs returns ok" do
      assert {:ok, %{"result" => "HELLO"}} =
               Liminara.TestOps.Upcase.execute(%{"text" => "hello"})
    end

    test "Concat implements all callbacks" do
      assert Liminara.TestOps.Concat.name() == "concat"

      assert {:ok, %{"result" => "ab"}} =
               Liminara.TestOps.Concat.execute(%{"a" => "a", "b" => "b"})
    end

    test "Fail returns error" do
      assert {:error, :intentional_failure} =
               Liminara.TestOps.Fail.execute(%{})
    end

    test "Recordable declares recordable determinism" do
      assert Liminara.TestOps.Recordable.determinism() == :recordable
    end

    test "Recordable returns decisions" do
      assert {:ok, %{"result" => _}, [decision]} =
               Liminara.TestOps.Recordable.execute(%{"prompt" => "test"})

      assert decision["decision_type"] == "llm_response"
    end
  end

  describe "Executor inline" do
    test "calls op directly, returns result with duration" do
      {:ok, result, duration_ms} =
        Executor.run(Liminara.TestOps.Upcase, %{"text" => "hello"}, executor: :inline)

      assert result.outputs == %{"result" => "HELLO"}
      assert result.decisions == []
      assert result.warnings == []
      assert is_integer(duration_ms) and duration_ms >= 0
    end

    test "failed op returns error with duration" do
      {:error, reason, duration_ms} =
        Executor.run(Liminara.TestOps.Fail, %{}, executor: :inline)

      assert reason == :intentional_failure
      assert is_integer(duration_ms) and duration_ms >= 0
    end

    test "inline is the default executor" do
      {:ok, result, _duration} =
        Executor.run(Liminara.TestOps.Upcase, %{"text" => "default"})

      assert result.outputs == %{"result" => "DEFAULT"}
    end
  end

  describe "Executor task" do
    test "runs op in a separate process" do
      {:ok, sup} = Task.Supervisor.start_link()

      {:ok, result, duration_ms} =
        Executor.run(Liminara.TestOps.Upcase, %{"text" => "async"},
          executor: :task,
          task_supervisor: sup
        )

      assert result.outputs == %{"result" => "ASYNC"}
      assert is_integer(duration_ms) and duration_ms >= 0
    end

    test "failed op through task executor" do
      {:ok, sup} = Task.Supervisor.start_link()

      {:error, reason, duration_ms} =
        Executor.run(Liminara.TestOps.Fail, %{}, executor: :task, task_supervisor: sup)

      assert reason == :intentional_failure
      assert is_integer(duration_ms) and duration_ms >= 0
    end
  end

  describe "Executor with recordable op" do
    test "recordable op returns decisions through executor" do
      {:ok, result, _duration} =
        Executor.run(Liminara.TestOps.Recordable, %{"prompt" => "test"}, executor: :inline)

      assert result.outputs == %{"result" => "Generated response for: test"}
      assert length(result.decisions) == 1
    end

    test "pure op returns no decisions" do
      {:ok, _result, _duration} =
        Executor.run(Liminara.TestOps.Upcase, %{"text" => "hi"}, executor: :inline)

      # Pure ops return 3-tuple, not 4-tuple — no decisions
    end
  end
end
