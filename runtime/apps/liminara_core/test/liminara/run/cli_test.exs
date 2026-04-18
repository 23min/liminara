defmodule Liminara.Run.CliTest do
  use ExUnit.Case, async: true

  alias Liminara.Run.{Cli, Result}

  defp build_result(attrs) do
    Result.new(Map.merge(%{run_id: "run-1", outputs: %{}, event_count: 0}, Map.new(attrs)))
  end

  describe "degraded_banner/1" do
    test "returns nil for a plain-success run (no warnings)" do
      result = build_result(status: :success, warning_count: 0, degraded_nodes: [])
      assert Cli.degraded_banner(result) == nil
    end

    test "returns a single-line banner for a degraded-success run" do
      result =
        build_result(status: :success, warning_count: 2, degraded_nodes: ["summarize", "dedup"])

      line = Cli.degraded_banner(result)
      assert is_binary(line)
      # Single line — no newlines in the banner body
      refute String.contains?(line, "\n")
      # Banner mentions the warning count and each node id
      assert line =~ "2"
      assert line =~ "summarize"
      assert line =~ "dedup"
      # Word "degraded" appears somewhere (case-insensitive) to keep wording
      # unambiguous for the operator
      assert line =~ ~r/degraded/i
    end

    test "returns nil for a failed run even when warnings are present" do
      result = build_result(status: :failed, warning_count: 3, degraded_nodes: ["a"])
      assert Cli.degraded_banner(result) == nil
    end

    test "returns nil for a :partial run with no warnings" do
      result = build_result(status: :partial, warning_count: 0, degraded_nodes: [])
      assert Cli.degraded_banner(result) == nil
    end
  end

  describe "maybe_print_degraded_banner/2" do
    test "prints the banner through the supplied printer on a degraded run" do
      pid = self()
      printer = fn line -> send(pid, {:printed, line}) end

      result = build_result(status: :success, warning_count: 1, degraded_nodes: ["summarize"])

      assert :ok = Cli.maybe_print_degraded_banner(result, printer)
      assert_received {:printed, line}
      assert line =~ "summarize"
      assert line =~ "1"
    end

    test "does not print anything on a plain-success run" do
      pid = self()
      printer = fn line -> send(pid, {:printed, line}) end

      result = build_result(status: :success, warning_count: 0, degraded_nodes: [])

      assert :ok = Cli.maybe_print_degraded_banner(result, printer)
      refute_received {:printed, _}
    end

    test "does not print anything on a failed run (failure takes precedence)" do
      pid = self()
      printer = fn line -> send(pid, {:printed, line}) end

      result = build_result(status: :failed, warning_count: 3, degraded_nodes: ["a", "b"])

      assert :ok = Cli.maybe_print_degraded_banner(result, printer)
      refute_received {:printed, _}
    end
  end
end
