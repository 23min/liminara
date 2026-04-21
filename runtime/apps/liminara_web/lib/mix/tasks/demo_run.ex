defmodule Mix.Tasks.DemoRun do
  @moduledoc "Create a demo run with a multi-node DAG including a gate for visual testing"
  use Mix.Task

  alias Liminara.{Plan, DemoOps, Run.Server}
  alias Liminara.Run.Cli

  @impl true
  def run(_args) do
    # Start the full application (stores, cache, pg, supervision)
    Application.ensure_all_started(:liminara_core)

    run_id = "demo-#{System.system_time(:millisecond)}"
    IO.puts("Creating demo run: #{run_id}")

    # Build a plan with fan-out, fan-in, and a gate mid-pipeline.
    # The gate pauses after the merge — user must approve in the browser.
    #
    #   input → upper → echo_a ─┐
    #         → reverse → echo_c ┴→ merge → [GATE: approve] → final_upper ─┐
    #                                                         → final_reverse ┴→ output
    plan =
      Plan.new()
      |> Plan.add_node("input", DemoOps.Echo, %{"text" => {:literal, "hello world"}})
      |> Plan.add_node("upper", DemoOps.Upcase, %{"text" => {:ref, "input"}})
      |> Plan.add_node("reverse", DemoOps.Reverse, %{"text" => {:ref, "input"}})
      |> Plan.add_node("echo_a", DemoOps.Echo, %{"text" => {:ref, "upper"}})
      |> Plan.add_node("echo_c", DemoOps.Echo, %{"text" => {:ref, "reverse"}})
      |> Plan.add_node("merge", DemoOps.Concat, %{
        "a" => {:ref, "echo_a"},
        "b" => {:ref, "echo_c"}
      })
      |> Plan.add_node("approve", DemoOps.Approve, %{"text" => {:ref, "merge"}})
      |> Plan.add_node("final_upper", DemoOps.Upcase, %{"text" => {:ref, "approve"}})
      |> Plan.add_node("final_reverse", DemoOps.Reverse, %{"text" => {:ref, "approve"}})
      |> Plan.add_node("output", DemoOps.Concat, %{
        "a" => {:ref, "final_upper"},
        "b" => {:ref, "final_reverse"}
      })

    # Execute the plan through the real Run.Server
    Server.start(run_id, plan, pack_id: "demo_pack", pack_version: "0.1.0")

    # Wait briefly for the run to reach the gate
    Process.sleep(500)

    # Best-effort: if the run already completed (e.g. because the plan has
    # no gate, or the gate was auto-approved), surface a degraded banner
    # when appropriate. Degraded is NOT a failure — the CLI still exits 0.
    case Server.await(run_id, 200) do
      {:ok, result} -> Cli.maybe_print_degraded_banner(result, &IO.puts/1)
      _ -> :ok
    end

    IO.puts("")
    IO.puts("Run started and paused at gate.")
    IO.puts("Open in browser: http://localhost:4000/runs/#{run_id}")
    IO.puts("Click the 'approve' node → click Approve to continue the run.")
  end
end
