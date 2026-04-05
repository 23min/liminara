defmodule Liminara.DemoOps.GateTest do
  @moduledoc """
  Tests for M-OBS-05a: DemoOps.Approve gate op.

  Covers:
  - DemoOps.Approve implements the Op behaviour (name, version, determinism, execute)
  - Approve.determinism/0 returns :side_effecting
  - Approve.execute/1 returns {:gate, prompt} where prompt is derived from inputs
  - Executor wraps the gate return as {:gate, prompt, duration_ms}

  All tests will fail (red phase) until DemoOps.Approve is implemented.
  """
  use ExUnit.Case, async: true

  alias Liminara.Executor

  # ── Op behaviour compliance ────────────────────────────────────────────────

  describe "DemoOps.Approve — Op behaviour compliance" do
    test "implements name/0 callback" do
      name = Liminara.DemoOps.Approve.name()
      assert is_binary(name), "Expected name/0 to return a binary, got: #{inspect(name)}"
      assert name != "", "Expected name/0 to return a non-empty string"
    end

    test "name/0 identifies the op clearly" do
      name = Liminara.DemoOps.Approve.name()
      assert name == "approve", "Expected name to be 'approve', got: #{inspect(name)}"
    end

    test "implements version/0 callback" do
      version = Liminara.DemoOps.Approve.version()
      assert is_binary(version), "Expected version/0 to return a binary, got: #{inspect(version)}"
      assert version != "", "Expected version/0 to return a non-empty string"
    end

    test "version/0 follows semver format" do
      version = Liminara.DemoOps.Approve.version()

      assert version =~ ~r/^\d+\.\d+/,
             "Expected version to look like semver, got: #{inspect(version)}"
    end

    test "implements determinism/0 callback" do
      det = Liminara.DemoOps.Approve.determinism()

      assert is_atom(det),
             "Expected determinism to be an atom, got: #{inspect(det)}"
    end

    test "determinism/0 returns :side_effecting — gates require human interaction" do
      assert Liminara.DemoOps.Approve.determinism() == :side_effecting,
             "DemoOps.Approve must have :side_effecting determinism (human approval required)"
    end

    test "implements execute/1 callback" do
      # execute/1 must be callable — behaviour requires it
      Code.ensure_loaded(Liminara.DemoOps.Approve)

      assert function_exported?(Liminara.DemoOps.Approve, :execute, 1),
             "Expected DemoOps.Approve to export execute/1"
    end

    test "declares the Op behaviour" do
      behaviours =
        Liminara.DemoOps.Approve.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Liminara.Op in behaviours,
             "Expected DemoOps.Approve to declare @behaviour Liminara.Op, got: #{inspect(behaviours)}"
    end
  end

  # ── execute/1 returns {:gate, prompt} ─────────────────────────────────────

  describe "DemoOps.Approve.execute/1 — gate return" do
    test "returns {:gate, prompt} tuple (not {:ok, ...})" do
      result = Liminara.DemoOps.Approve.execute(%{"text" => "please review this"})

      assert match?({:gate, _}, result),
             "Expected execute/1 to return {:gate, prompt}, got: #{inspect(result)}"
    end

    test "prompt is a binary string" do
      {:gate, prompt} = Liminara.DemoOps.Approve.execute(%{"text" => "sample text"})

      assert is_binary(prompt),
             "Expected gate prompt to be a binary string, got: #{inspect(prompt)}"
    end

    test "prompt is non-empty" do
      {:gate, prompt} = Liminara.DemoOps.Approve.execute(%{"text" => "sample text"})

      assert prompt != "",
             "Expected gate prompt to be non-empty"
    end

    test "prompt is derived from inputs — contains the input text" do
      {:gate, prompt} = Liminara.DemoOps.Approve.execute(%{"text" => "please approve me"})

      assert prompt =~ "please approve me",
             "Expected prompt to contain the input text 'please approve me', got: #{inspect(prompt)}"
    end

    test "different inputs produce different prompts" do
      {:gate, prompt_a} = Liminara.DemoOps.Approve.execute(%{"text" => "input alpha"})
      {:gate, prompt_b} = Liminara.DemoOps.Approve.execute(%{"text" => "input beta"})

      assert prompt_a != prompt_b,
             "Expected different inputs to produce different prompts"
    end

    test "prompt with empty text input still returns {:gate, prompt}" do
      result = Liminara.DemoOps.Approve.execute(%{"text" => ""})

      assert match?({:gate, _}, result),
             "Expected execute/1 with empty text to return {:gate, prompt}, got: #{inspect(result)}"
    end
  end

  # ── Executor integration ───────────────────────────────────────────────────

  describe "Executor — wraps DemoOps.Approve gate return as {:gate, prompt, duration_ms}" do
    test "Executor.run/2 returns {:gate, prompt, duration_ms} tuple" do
      result = Executor.run(Liminara.DemoOps.Approve, %{"text" => "approve this"})

      assert match?({:gate, _, _}, result),
             "Expected Executor.run to return {:gate, prompt, duration_ms}, got: #{inspect(result)}"
    end

    test "Executor wraps gate: prompt is a binary" do
      {:gate, prompt, _duration_ms} =
        Executor.run(Liminara.DemoOps.Approve, %{"text" => "check this"})

      assert is_binary(prompt),
             "Expected Executor-wrapped gate prompt to be a binary, got: #{inspect(prompt)}"
    end

    test "Executor wraps gate: duration_ms is a non-negative integer" do
      {:gate, _prompt, duration_ms} =
        Executor.run(Liminara.DemoOps.Approve, %{"text" => "check this"})

      assert is_integer(duration_ms) and duration_ms >= 0,
             "Expected duration_ms to be a non-negative integer, got: #{inspect(duration_ms)}"
    end

    test "Executor wraps gate: prompt is derived from input" do
      {:gate, prompt, _duration_ms} =
        Executor.run(Liminara.DemoOps.Approve, %{"text" => "unique input text abc"})

      assert prompt =~ "unique input text abc",
             "Expected Executor-wrapped gate prompt to contain input, got: #{inspect(prompt)}"
    end

    test "Executor with :task executor also wraps gate correctly" do
      {:ok, sup} = Task.Supervisor.start_link()

      result =
        Executor.run(Liminara.DemoOps.Approve, %{"text" => "task gate"},
          executor: :task,
          task_supervisor: sup
        )

      assert match?({:gate, _, _}, result),
             "Expected task executor to also return {:gate, prompt, duration_ms}, got: #{inspect(result)}"
    end
  end
end
