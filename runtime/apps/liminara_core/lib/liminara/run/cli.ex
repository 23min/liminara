defmodule Liminara.Run.Cli do
  @moduledoc """
  CLI output helpers shared by mix tasks that run a pipeline and want to
  surface warnings/degraded-outcome information in the terminal.

  Consumed by `mix radar.run` and `mix demo_run`. The functions are
  side-effect free unless they explicitly print.
  """

  alias Liminara.Run.Result

  @doc """
  Return a single-line degraded banner for a `Result`, or `nil` when the
  run should not surface one.

  Rules (M-WARN-02):
  - Failed runs take precedence: no degraded banner even if warnings are
    present. The failure is already surfaced by the task's failure output.
  - Plain-success runs (zero warnings) return `nil` — the CLI output is
    unchanged from the pre-M-WARN-02 behavior.
  - Degraded-success runs return a single-line banner containing the
    warning count and comma-separated degraded node ids.
  """
  @spec degraded_banner(Result.t()) :: String.t() | nil
  def degraded_banner(%Result{status: :failed}), do: nil
  def degraded_banner(%Result{degraded: false}), do: nil

  def degraded_banner(%Result{degraded: true} = result) do
    "DEGRADED: #{result.warning_count} warning(s) in #{Enum.join(result.degraded_nodes, ", ")}"
  end

  @doc """
  Print the degraded banner using the supplied printer (default
  `Mix.shell().info/1`). Returns `:ok` in both the printed and skipped
  cases; caller may ignore the return value.
  """
  @spec maybe_print_degraded_banner(Result.t(), (String.t() -> any())) :: :ok
  def maybe_print_degraded_banner(%Result{} = result, printer \\ &Mix.shell().info/1)
      when is_function(printer, 1) do
    case degraded_banner(result) do
      nil -> :ok
      line -> printer.(line)
    end

    :ok
  end
end
