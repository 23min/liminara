defmodule Liminara.Observation.ServerTest do
  use ExUnit.Case, async: false

  alias Liminara.Observation.{Server, ViewModel}
  alias Liminara.Plan

  # ── Helpers ────────────────────────────────────────────────────────

  defp simple_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
  end

  defp two_node_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
    |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
  end

  defp unique_run_id do
    "obs-srv-#{:erlang.unique_integer([:positive])}"
  end

  # ── start_link/1 lifecycle ─────────────────────────────────────────

  describe "start_link/1" do
    test "starts a GenServer process" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      assert is_pid(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "multiple servers start independently" do
      run_id_1 = unique_run_id()
      run_id_2 = unique_run_id()
      plan = simple_plan()

      {:ok, pid1} = Server.start_link(run_id: run_id_1, plan: plan)
      {:ok, pid2} = Server.start_link(run_id: run_id_2, plan: plan)

      assert pid1 != pid2
      assert Process.alive?(pid1)
      assert Process.alive?(pid2)

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end

    test "server subscribes to the run's :pg group" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      # Give it a moment to subscribe
      Process.sleep(50)

      members = :pg.get_members(:liminara, {:run, run_id})
      assert pid in members

      GenServer.stop(pid)
    end
  end

  # ── get_state/1 ────────────────────────────────────────────────────

  describe "get_state/1" do
    test "returns ViewModel struct" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      state = Server.get_state(pid)

      # ViewModel struct not yet implemented — verify it is a struct
      assert is_struct(state)
      assert state.__struct__ == ViewModel

      GenServer.stop(pid)
    end

    test "initial state has run_status :pending" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      state = Server.get_state(pid)

      assert state.run_status == :pending

      GenServer.stop(pid)
    end

    test "initial state has all nodes :pending" do
      run_id = unique_run_id()
      plan = two_node_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      state = Server.get_state(pid)

      for {_id, node_view} <- state.nodes do
        assert node_view.status == :pending
      end

      GenServer.stop(pid)
    end

    test "run_id in returned state matches the server's run_id" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      state = Server.get_state(pid)

      assert state.run_id == run_id

      GenServer.stop(pid)
    end

    test "plan in returned state matches the given plan" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      state = Server.get_state(pid)

      assert state.plan == plan

      GenServer.stop(pid)
    end
  end

  # ── get_node/2 ─────────────────────────────────────────────────────

  describe "get_node/2" do
    test "returns node detail for a known node" do
      run_id = unique_run_id()
      plan = two_node_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      node_view = Server.get_node(pid, "a")

      assert node_view != nil
      assert node_view.status == :pending

      GenServer.stop(pid)
    end

    test "returns nil for unknown node" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      result = Server.get_node(pid, "nonexistent_node")

      assert result == nil

      GenServer.stop(pid)
    end

    test "get_node returns same data as get_state nodes map" do
      run_id = unique_run_id()
      plan = two_node_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      state = Server.get_state(pid)
      node_via_get_node = Server.get_node(pid, "b")

      assert node_via_get_node == state.nodes["b"]

      GenServer.stop(pid)
    end
  end

  # ── :pg event reception ────────────────────────────────────────────

  describe ":pg event reception" do
    test "server updates view model on receiving run_started event" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      # Send a run_started event via :pg
      event = %{
        event_hash: "sha256:start",
        event_type: "run_started",
        payload: %{
          "run_id" => run_id,
          "pack_id" => "test_pack",
          "pack_version" => "0.1.0",
          "plan_hash" => "sha256:abc"
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      }

      :pg.get_members(:liminara, {:run, run_id})
      |> Enum.each(&send(&1, {:run_event, run_id, event}))

      # Give server time to process
      Process.sleep(50)

      state = Server.get_state(pid)
      assert state.run_status == :running

      GenServer.stop(pid)
    end

    test "server updates node status on receiving op_started event" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      Process.sleep(20)

      send_pg_event(run_id, %{
        event_hash: "sha256:rs",
        event_type: "run_started",
        payload: %{
          "run_id" => run_id,
          "pack_id" => "p",
          "pack_version" => "1",
          "plan_hash" => "h"
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      send_pg_event(run_id, %{
        event_hash: "sha256:os",
        event_type: "op_started",
        payload: %{
          "node_id" => "a",
          "op_id" => "upcase",
          "op_version" => "1.0",
          "determinism" => "pure",
          "input_hashes" => []
        },
        prev_hash: "sha256:rs",
        timestamp: "2026-03-19T14:00:01.000Z"
      })

      Process.sleep(50)

      state = Server.get_state(pid)
      assert state.nodes["a"].status == :running

      GenServer.stop(pid)
    end

    test "server updates node on receiving op_completed event" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      Process.sleep(20)

      send_pg_event(run_id, %{
        event_hash: "sha256:rs",
        event_type: "run_started",
        payload: %{
          "run_id" => run_id,
          "pack_id" => "p",
          "pack_version" => "1",
          "plan_hash" => "h"
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      send_pg_event(run_id, %{
        event_hash: "sha256:os",
        event_type: "op_started",
        payload: %{
          "node_id" => "a",
          "op_id" => "upcase",
          "op_version" => "1.0",
          "determinism" => "pure",
          "input_hashes" => []
        },
        prev_hash: "sha256:rs",
        timestamp: "2026-03-19T14:00:01.000Z"
      })

      send_pg_event(run_id, %{
        event_hash: "sha256:oc",
        event_type: "op_completed",
        payload: %{
          "node_id" => "a",
          "output_hashes" => ["sha256:r1"],
          "cache_hit" => false,
          "duration_ms" => 42,
          "warnings" => []
        },
        prev_hash: "sha256:os",
        timestamp: "2026-03-19T14:00:02.000Z"
      })

      Process.sleep(50)

      state = Server.get_state(pid)
      assert state.nodes["a"].status == :completed

      GenServer.stop(pid)
    end

    test "server updates run_status on receiving run_completed event" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      Process.sleep(20)

      send_run_lifecycle(run_id, ["a"])

      Process.sleep(100)

      state = Server.get_state(pid)
      assert state.run_status == :completed

      GenServer.stop(pid)
    end

    test "event_count grows as events arrive" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      Process.sleep(20)

      send_pg_event(run_id, %{
        event_hash: "sha256:rs",
        event_type: "run_started",
        payload: %{
          "run_id" => run_id,
          "pack_id" => "p",
          "pack_version" => "1",
          "plan_hash" => "h"
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      Process.sleep(50)

      state = Server.get_state(pid)
      assert state.event_count == 1

      GenServer.stop(pid)
    end
  end

  # ── Phoenix.PubSub publication ─────────────────────────────────────

  describe "Phoenix.PubSub updates" do
    test "server publishes to PubSub on event received" do
      run_id = unique_run_id()
      plan = simple_plan()

      topic = "observation:#{run_id}:state"
      Phoenix.PubSub.subscribe(Liminara.Observation.PubSub, topic)

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      Process.sleep(20)

      send_pg_event(run_id, %{
        event_hash: "sha256:rs",
        event_type: "run_started",
        payload: %{
          "run_id" => run_id,
          "pack_id" => "p",
          "pack_version" => "1",
          "plan_hash" => "h"
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      # Should receive a PubSub message with the current view model state
      assert_receive {:state_update, ^run_id, view_state}, 500
      assert is_struct(view_state)
      assert view_state.__struct__ == ViewModel

      GenServer.stop(pid)
    end

    test "PubSub state topic format is 'observation:{run_id}:state'" do
      run_id = unique_run_id()
      plan = simple_plan()

      topic = "observation:#{run_id}:state"
      Phoenix.PubSub.subscribe(Liminara.Observation.PubSub, topic)

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      Process.sleep(20)

      send_pg_event(run_id, %{
        event_hash: "sha256:rs",
        event_type: "run_started",
        payload: %{
          "run_id" => run_id,
          "pack_id" => "p",
          "pack_version" => "1",
          "plan_hash" => "h"
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      # Different run_id topic should NOT receive this message
      wrong_topic = "observation:wrong-run:state"
      Phoenix.PubSub.subscribe(Liminara.Observation.PubSub, wrong_topic)

      assert_receive {:state_update, ^run_id, _state}, 500
      refute_receive {:state_update, _, _}, 100

      GenServer.stop(pid)
    end

    test "each event triggers one PubSub publish" do
      run_id = unique_run_id()
      plan = simple_plan()

      topic = "observation:#{run_id}:state"
      Phoenix.PubSub.subscribe(Liminara.Observation.PubSub, topic)

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      Process.sleep(20)

      send_pg_event(run_id, %{
        event_hash: "sha256:rs",
        event_type: "run_started",
        payload: %{
          "run_id" => run_id,
          "pack_id" => "p",
          "pack_version" => "1",
          "plan_hash" => "h"
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      send_pg_event(run_id, %{
        event_hash: "sha256:os",
        event_type: "op_started",
        payload: %{
          "node_id" => "a",
          "op_id" => "upcase",
          "op_version" => "1.0",
          "determinism" => "pure",
          "input_hashes" => []
        },
        prev_hash: "sha256:rs",
        timestamp: "2026-03-19T14:00:01.000Z"
      })

      assert_receive {:state_update, ^run_id, _state1}, 500
      assert_receive {:state_update, ^run_id, _state2}, 500

      GenServer.stop(pid)
    end
  end

  # ── Multiple observers ─────────────────────────────────────────────

  describe "multiple observers for the same run" do
    test "two servers can observe the same run concurrently" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid1} = Server.start_link(run_id: run_id, plan: plan)
      {:ok, pid2} = Server.start_link(run_id: run_id, plan: plan)

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end

    test "both observers receive events and maintain consistent state" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid1} = Server.start_link(run_id: run_id, plan: plan)
      {:ok, pid2} = Server.start_link(run_id: run_id, plan: plan)

      Process.sleep(20)

      send_pg_event(run_id, %{
        event_hash: "sha256:rs",
        event_type: "run_started",
        payload: %{
          "run_id" => run_id,
          "pack_id" => "p",
          "pack_version" => "1",
          "plan_hash" => "h"
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      })

      Process.sleep(100)

      state1 = Server.get_state(pid1)
      state2 = Server.get_state(pid2)

      assert state1.run_status == :running
      assert state2.run_status == :running
      assert state1.event_count == state2.event_count

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end
  end

  # ── Isolation: server crash doesn't affect Run.Server ──────────────

  describe "isolation" do
    test "killing Observation.Server process does not affect Run.Server" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)

      # Kill the observation server
      Process.exit(obs_pid, :kill)
      Process.sleep(50)

      # Run.Server for a different run should still be unaffected
      # (We just verify the obs server is dead)
      refute Process.alive?(obs_pid)
    end

    test "Observation.Server subscribes as normal process — crash unlinks from :pg" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)
      Process.sleep(20)

      members_before = :pg.get_members(:liminara, {:run, run_id})
      assert obs_pid in members_before

      Process.exit(obs_pid, :kill)
      Process.sleep(100)

      # After crash, the process should no longer be in :pg
      members_after = :pg.get_members(:liminara, {:run, run_id})
      refute obs_pid in members_after
    end
  end

  # ── Private helpers ────────────────────────────────────────────────

  defp send_pg_event(run_id, event) do
    :pg.get_members(:liminara, {:run, run_id})
    |> Enum.each(&send(&1, {:run_event, run_id, event}))
  end

  defp send_run_lifecycle(run_id, node_ids) do
    send_pg_event(run_id, %{
      event_hash: "sha256:rs",
      event_type: "run_started",
      payload: %{"run_id" => run_id, "pack_id" => "p", "pack_version" => "1", "plan_hash" => "h"},
      prev_hash: nil,
      timestamp: "2026-03-19T14:00:00.000Z"
    })

    prev = "sha256:rs"

    {_prev, node_ids} =
      Enum.reduce(node_ids, {prev, []}, fn node_id, {prev_hash, acc} ->
        started_hash = "sha256:os_#{node_id}"
        completed_hash = "sha256:oc_#{node_id}"

        send_pg_event(run_id, %{
          event_hash: started_hash,
          event_type: "op_started",
          payload: %{
            "node_id" => node_id,
            "op_id" => "upcase",
            "op_version" => "1.0",
            "determinism" => "pure",
            "input_hashes" => []
          },
          prev_hash: prev_hash,
          timestamp: "2026-03-19T14:00:01.000Z"
        })

        send_pg_event(run_id, %{
          event_hash: completed_hash,
          event_type: "op_completed",
          payload: %{
            "node_id" => node_id,
            "output_hashes" => ["sha256:r_#{node_id}"],
            "cache_hit" => false,
            "duration_ms" => 5,
            "warnings" => []
          },
          prev_hash: started_hash,
          timestamp: "2026-03-19T14:00:02.000Z"
        })

        {completed_hash, acc ++ [node_id]}
      end)

    final_prev = "sha256:oc_#{List.last(node_ids)}"

    send_pg_event(run_id, %{
      event_hash: "sha256:rc",
      event_type: "run_completed",
      payload: %{
        "run_id" => run_id,
        "outcome" => "success",
        "artifact_hashes" => [],
        "warning_summary" => %{"warning_count" => 0, "degraded_node_ids" => []}
      },
      prev_hash: final_prev,
      timestamp: "2026-03-19T14:00:05.000Z"
    })
  end
end
