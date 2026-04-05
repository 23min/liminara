defmodule Liminara.Run.CrashRecoveryTest do
  use ExUnit.Case, async: false

  alias Liminara.{Event, Plan, Run}

  # M-OTP-04: Crash Recovery and Run Isolation

  # ── Op crash handling ────────────────────────────────────────────

  describe "op crash handling" do
    test "op that raises RuntimeError: node marked failed, run continues other branches" do
      # Fan-out: A → B (crashes), A → C (succeeds)
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "crash"}})
        |> Plan.add_node("b", Liminara.TestOps.Raise, %{"text" => {:ref, "a", "result"}})
        |> Plan.add_node("c", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})

      run_id = "crash-raise-#{:erlang.unique_integer([:positive])}"
      Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id)

      # Run should complete with partial results
      assert result.status in [:partial, :failed]
      # Node C should have completed
      assert Map.has_key?(result.outputs, "c")
      # Node B should have failed
      assert result.node_states["b"] == :failed
    end

    test "op that exits with :kill: node marked failed" do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.ExitKill, %{"text" => {:literal, "die"}})

      run_id = "crash-kill-#{:erlang.unique_integer([:positive])}"
      Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id)

      assert result.status == :failed
    end

    test "linear plan where middle op fails: downstream never executes, run fails" do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "ok"}})
        |> Plan.add_node("b", Liminara.TestOps.Raise, %{"text" => {:ref, "a", "result"}})
        |> Plan.add_node("c", Liminara.TestOps.Reverse, %{"text" => {:ref, "b", "result"}})

      run_id = "crash-linear-#{:erlang.unique_integer([:positive])}"
      Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id)

      assert result.status == :failed
      # A completed, B failed, C never ran
      assert result.node_states["a"] == :completed
      assert result.node_states["b"] == :failed
      assert result.node_states["c"] == :pending

      {:ok, events} = Event.Store.read_all(run_id)
      types = Enum.map(events, & &1["event_type"])
      assert "op_failed" in types
      assert "run_failed" in types
    end

    test "fan-out where one branch fails: other branch completes" do
      # A → B (fails), A → C (succeeds), both independent
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "fan"}})
        |> Plan.add_node("b", Liminara.TestOps.Raise, %{"text" => {:ref, "a", "result"}})
        |> Plan.add_node("c", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})

      run_id = "crash-fanout-#{:erlang.unique_integer([:positive])}"
      Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id)

      # C should have its output
      assert Map.has_key?(result.outputs, "c")
      {:ok, content} = Liminara.Artifact.Store.get(result.outputs["c"]["result"])
      assert content == "NAF"

      # B should be failed
      assert result.node_states["b"] == :failed
    end
  end

  # ── State rebuild from event log ─────────────────────────────────

  describe "state rebuild from event log" do
    test "completed run: restart detects completion, reports result" do
      plan = simple_plan()
      run_id = "rebuild-done-#{:erlang.unique_integer([:positive])}"

      # Run to completion
      Run.Server.start(run_id, plan)
      {:ok, result1} = Run.Server.await(run_id)
      assert result1.status == :success

      # Wait for server to exit
      Process.sleep(50)

      # Start a new server with the same run_id — should detect completion
      {:ok, _pid} = Run.Server.start(run_id, plan)
      {:ok, result2} = Run.Server.await(run_id)

      assert result2.status == :success
      assert result2.run_id == run_id
    end

    test "partial run: restart rebuilds state, dispatches remaining op" do
      # Use a plan where first op completes quickly, second is slow
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "rebuild"}})
        |> Plan.add_node("b", Liminara.TestOps.Slow, %{"text" => {:ref, "a", "result"}})

      run_id = "rebuild-partial-#{:erlang.unique_integer([:positive])}"

      {:ok, pid} = Run.Server.start(run_id, plan)

      # Wait for node A to complete but B to still be running
      Process.sleep(100)

      # Kill the server
      Process.exit(pid, :kill)
      Process.sleep(50)

      # Restart with the same run_id — should rebuild and finish
      {:ok, _pid2} = Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id, 10_000)

      assert result.status == :success
      assert result.node_states["a"] == :completed
      assert result.node_states["b"] == :completed
    end

    test "rebuilt event log has valid hash chain (no duplicates)" do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "chain"}})
        |> Plan.add_node("b", Liminara.TestOps.Slow, %{"text" => {:ref, "a", "result"}})

      run_id = "rebuild-chain-#{:erlang.unique_integer([:positive])}"

      {:ok, pid} = Run.Server.start(run_id, plan)
      Process.sleep(100)
      Process.exit(pid, :kill)
      Process.sleep(50)

      {:ok, _pid2} = Run.Server.start(run_id, plan)
      {:ok, _result} = Run.Server.await(run_id, 10_000)

      # Hash chain must be valid end-to-end
      assert {:ok, _count} = Event.Store.verify(run_id)
    end

    test "restart resumes context-aware nodes successfully" do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Slow, %{"text" => {:literal, "resume"}})
        |> Plan.add_node("b", Liminara.TestOps.WithRuntimeContext, %{
          "text" => {:ref, "a", "result"}
        })

      run_id = "rebuild-context-#{:erlang.unique_integer([:positive])}"

      {:ok, pid} = Run.Server.start(run_id, plan)
      Process.sleep(100)
      Process.exit(pid, :shutdown)
      Process.sleep(50)

      {:ok, _pid2} = Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id, 10_000)

      assert result.status == :success
      assert result.node_states["a"] == :completed
      assert result.node_states["b"] == :completed

      {:ok, started_at_content} =
        Liminara.Artifact.Store.get(result.outputs["b"]["started_at"])

      assert is_binary(started_at_content)
      assert started_at_content != ""
    end

    test "restart succeeds for context-aware nodes even if the execution context file is missing" do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Slow, %{"text" => {:literal, "resume"}})
        |> Plan.add_node("b", Liminara.TestOps.WithRuntimeContext, %{
          "text" => {:ref, "a", "result"}
        })

      run_id = "rebuild-context-from-events-#{:erlang.unique_integer([:positive])}"

      {:ok, pid} = Run.Server.start(run_id, plan)
      Process.sleep(100)

      Process.exit(pid, :shutdown)
      Process.sleep(50)

      File.rm!(
        Path.join([
          :sys.get_state(Liminara.Event.Store).runs_root,
          run_id,
          "execution_context.json"
        ])
      )

      {:ok, _pid2} = Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id, 10_000)

      assert result.status == :success
      assert result.node_states["a"] == :completed
      assert result.node_states["b"] == :completed

      {:ok, started_at_content} =
        Liminara.Artifact.Store.get(result.outputs["b"]["started_at"])

      assert is_binary(started_at_content)
      assert started_at_content != ""
    end

    test "replay restart keeps using the replay run's recorded context after source context loss" do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Slow, %{"text" => {:literal, "resume"}})
        |> Plan.add_node("b", Liminara.TestOps.WithRuntimeContext, %{
          "text" => {:ref, "a", "result"}
        })

      {:ok, discovery} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: :sys.get_state(Liminara.Artifact.Store).store_root,
          runs_root: :sys.get_state(Liminara.Event.Store).runs_root
        )

      run_id = "rebuild-replay-context-#{:erlang.unique_integer([:positive])}"

      {:ok, pid} = Run.Server.start(run_id, plan, replay: discovery.run_id)
      Process.sleep(100)
      Process.exit(pid, :shutdown)
      Process.sleep(50)

      File.rm!(
        Path.join([
          :sys.get_state(Liminara.Event.Store).runs_root,
          discovery.run_id,
          "execution_context.json"
        ])
      )

      {:ok, _pid2} = Run.Server.start(run_id, plan, replay: discovery.run_id)
      {:ok, result} = Run.Server.await(run_id, 10_000)

      assert result.status == :success

      {:ok, run_id_content} = Liminara.Artifact.Store.get(result.outputs["b"]["run_id"])

      {:ok, replay_of_run_id} =
        Liminara.Artifact.Store.get(result.outputs["b"]["replay_of_run_id"])

      assert run_id_content == discovery.run_id
      assert replay_of_run_id == discovery.run_id
    end

    test "await fallback preserves partial status after the server exits" do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "fan"}})
        |> Plan.add_node("b", Liminara.TestOps.Raise, %{"text" => {:ref, "a", "result"}})
        |> Plan.add_node("c", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})

      run_id = "rebuild-partial-status-#{:erlang.unique_integer([:positive])}"

      Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id)
      assert result.status == :partial

      Process.sleep(50)

      assert {:ok, rebuilt_result} = Run.Server.await(run_id)
      assert rebuilt_result.status == :partial
      assert rebuilt_result.node_states["b"] == :failed
      assert rebuilt_result.node_states["c"] == :completed
    end
  end

  # ── Concurrent runs ──────────────────────────────────────────────

  describe "concurrent runs" do
    test "two runs with different plans complete independently" do
      plan_a =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "alpha"}})

      plan_b =
        Plan.new()
        |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:literal, "beta"}})

      run_a = "concurrent-a-#{:erlang.unique_integer([:positive])}"
      run_b = "concurrent-b-#{:erlang.unique_integer([:positive])}"

      Run.Server.start(run_a, plan_a)
      Run.Server.start(run_b, plan_b)

      {:ok, result_a} = Run.Server.await(run_a)
      {:ok, result_b} = Run.Server.await(run_b)

      assert result_a.status == :success
      assert result_b.status == :success

      {:ok, a_content} = Liminara.Artifact.Store.get(result_a.outputs["a"]["result"])
      {:ok, b_content} = Liminara.Artifact.Store.get(result_b.outputs["b"]["result"])
      assert a_content == "ALPHA"
      assert b_content == "ateb"
    end

    test "one run crashing does not affect the other" do
      plan_ok =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Slow, %{"text" => {:literal, "safe"}})

      plan_crash =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Raise, %{"text" => {:literal, "boom"}})

      run_ok = "concurrent-ok-#{:erlang.unique_integer([:positive])}"
      run_crash = "concurrent-crash-#{:erlang.unique_integer([:positive])}"

      Run.Server.start(run_ok, plan_ok)
      Run.Server.start(run_crash, plan_crash)

      {:ok, result_crash} = Run.Server.await(run_crash)
      {:ok, result_ok} = Run.Server.await(run_ok, 10_000)

      assert result_crash.status == :failed
      assert result_ok.status == :success
    end

    test "two runs with same plan produce separate event logs" do
      plan = simple_plan()

      run_a = "concurrent-same-a-#{:erlang.unique_integer([:positive])}"
      run_b = "concurrent-same-b-#{:erlang.unique_integer([:positive])}"

      Run.Server.start(run_a, plan)
      Run.Server.start(run_b, plan)

      {:ok, _ra} = Run.Server.await(run_a)
      {:ok, _rb} = Run.Server.await(run_b)

      {:ok, events_a} = Event.Store.read_all(run_a)
      {:ok, events_b} = Event.Store.read_all(run_b)

      # Both should have events
      assert events_a != []
      assert events_b != []

      # Both should have valid, independent hash chains
      assert {:ok, _} = Event.Store.verify(run_a)
      assert {:ok, _} = Event.Store.verify(run_b)
    end

    test "Registry tracks both runs during execution" do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Slow, %{"text" => {:literal, "reg"}})

      run_a = "concurrent-reg-a-#{:erlang.unique_integer([:positive])}"
      run_b = "concurrent-reg-b-#{:erlang.unique_integer([:positive])}"

      {:ok, pid_a} = Run.Server.start(run_a, plan)
      {:ok, pid_b} = Run.Server.start(run_b, plan)

      # Both should be in the registry
      assert [{^pid_a, _}] = Registry.lookup(Liminara.Run.Registry, run_a)
      assert [{^pid_b, _}] = Registry.lookup(Liminara.Run.Registry, run_b)

      Run.Server.await(run_a, 10_000)
      Run.Server.await(run_b, 10_000)
    end
  end

  # ── Inspection ───────────────────────────────────────────────────

  describe "inspection" do
    test ":sys.get_state returns state with run_id, node_states, event_count" do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Slow, %{"text" => {:literal, "inspect"}})

      run_id = "inspect-state-#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Run.Server.start(run_id, plan)

      Process.sleep(10)
      state = :sys.get_state(pid)

      assert state.run_id == run_id
      assert is_map(state.node_states)
      assert is_integer(state.event_count)

      Run.Server.await(run_id, 10_000)
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp simple_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
  end
end
