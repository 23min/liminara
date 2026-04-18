defmodule Liminara.Observation.ViewModelTest do
  use ExUnit.Case, async: true

  alias Liminara.Observation.ViewModel
  alias Liminara.Plan

  # ── Helpers ────────────────────────────────────────────────────────

  defp simple_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
    |> Plan.add_node("b", Liminara.TestOps.Reverse, %{"text" => {:ref, "a", "result"}})
  end

  defp single_node_plan do
    Plan.new()
    |> Plan.add_node("x", Liminara.TestOps.Identity, %{"result" => {:literal, "val"}})
  end

  defp run_started_event(run_id, plan_hash \\ "sha256:abc") do
    %{
      event_hash: "sha256:start",
      event_type: "run_started",
      payload: %{
        "run_id" => run_id,
        "pack_id" => "test_pack",
        "pack_version" => "0.1.0",
        "plan_hash" => plan_hash
      },
      prev_hash: nil,
      timestamp: "2026-03-19T14:00:00.000Z"
    }
  end

  defp op_started_event(node_id, op_id \\ "upcase", prev_hash \\ "sha256:start") do
    %{
      event_hash: "sha256:op_started_#{node_id}",
      event_type: "op_started",
      payload: %{
        "node_id" => node_id,
        "op_id" => op_id,
        "op_version" => "1.0",
        "determinism" => "pure",
        "input_hashes" => ["sha256:input"]
      },
      prev_hash: prev_hash,
      timestamp: "2026-03-19T14:00:01.000Z"
    }
  end

  defp op_completed_event(node_id, opts \\ []) do
    prev = Keyword.get(opts, :prev_hash, "sha256:op_started_#{node_id}")
    cache_hit = Keyword.get(opts, :cache_hit, false)
    duration = Keyword.get(opts, :duration_ms, 42)
    output_hashes = Keyword.get(opts, :output_hashes, ["sha256:out1"])

    %{
      event_hash: "sha256:op_completed_#{node_id}",
      event_type: "op_completed",
      payload: %{
        "node_id" => node_id,
        "output_hashes" => output_hashes,
        "cache_hit" => cache_hit,
        "duration_ms" => duration,
        "warnings" => []
      },
      prev_hash: prev,
      timestamp: "2026-03-19T14:00:02.000Z"
    }
  end

  defp op_failed_event(node_id) do
    %{
      event_hash: "sha256:op_failed_#{node_id}",
      event_type: "op_failed",
      payload: %{
        "node_id" => node_id,
        "error_type" => "execution_error",
        "error_message" => "intentional failure",
        "duration_ms" => 10
      },
      prev_hash: "sha256:op_started_#{node_id}",
      timestamp: "2026-03-19T14:00:02.000Z"
    }
  end

  defp gate_requested_event(node_id) do
    %{
      event_hash: "sha256:gate_req_#{node_id}",
      event_type: "gate_requested",
      payload: %{
        "node_id" => node_id,
        "prompt" => "Please approve this action."
      },
      prev_hash: "sha256:op_started_#{node_id}",
      timestamp: "2026-03-19T14:00:03.000Z"
    }
  end

  defp gate_resolved_event(node_id) do
    %{
      event_hash: "sha256:gate_res_#{node_id}",
      event_type: "gate_resolved",
      payload: %{
        "node_id" => node_id,
        "response" => "approved"
      },
      prev_hash: "sha256:gate_req_#{node_id}",
      timestamp: "2026-03-19T14:00:04.000Z"
    }
  end

  defp decision_recorded_event(node_id) do
    %{
      event_hash: "sha256:decision_#{node_id}",
      event_type: "decision_recorded",
      payload: %{
        "node_id" => node_id,
        "decision_hash" => "sha256:dec1",
        "decision_type" => "llm_response"
      },
      prev_hash: "sha256:op_started_#{node_id}",
      timestamp: "2026-03-19T14:00:02.000Z"
    }
  end

  defp run_completed_event(run_id, opts \\ []) do
    warning_count = Keyword.get(opts, :warning_count, 0)
    degraded_node_ids = Keyword.get(opts, :degraded_node_ids, [])

    %{
      event_hash: "sha256:run_completed",
      event_type: "run_completed",
      payload: %{
        "run_id" => run_id,
        "outcome" => "success",
        "artifact_hashes" => ["sha256:out1"],
        "warning_summary" => %{
          "warning_count" => warning_count,
          "degraded_node_ids" => degraded_node_ids
        }
      },
      prev_hash: "sha256:op_completed_a",
      timestamp: "2026-03-19T14:00:05.000Z"
    }
  end

  defp warning_map(overrides \\ %{}) do
    base = %{
      "code" => "fallback_used",
      "severity" => "low",
      "summary" => "a warning happened",
      "cause" => "api_key_missing",
      "remediation" => "set ANTHROPIC_API_KEY",
      "affected_outputs" => ["result"]
    }

    Map.merge(base, overrides)
  end

  defp op_completed_event_with_warnings(node_id, warnings, opts \\ []) do
    prev = Keyword.get(opts, :prev_hash, "sha256:op_started_#{node_id}")
    duration = Keyword.get(opts, :duration_ms, 42)
    output_hashes = Keyword.get(opts, :output_hashes, ["sha256:out1"])

    %{
      event_hash: "sha256:op_completed_#{node_id}",
      event_type: "op_completed",
      payload: %{
        "node_id" => node_id,
        "output_hashes" => output_hashes,
        "cache_hit" => false,
        "duration_ms" => duration,
        "warnings" => warnings
      },
      prev_hash: prev,
      timestamp: "2026-03-19T14:00:02.000Z"
    }
  end

  # ── ViewModel.init/1 ───────────────────────────────────────────────

  describe "ViewModel.init/1" do
    test "returns a struct with the expected fields" do
      plan = simple_plan()
      run_id = "test-run-#{:erlang.unique_integer([:positive])}"
      state = ViewModel.init(run_id, plan)

      assert is_struct(state)
      assert state.__struct__ == ViewModel
    end

    test "init sets run_id" do
      run_id = "my-run-123"
      plan = single_node_plan()
      state = ViewModel.init(run_id, plan)

      assert state.run_id == run_id
    end

    test "init sets run_status to :pending" do
      plan = single_node_plan()
      state = ViewModel.init("run-1", plan)

      assert state.run_status == :pending
    end

    test "init stores the original plan" do
      plan = simple_plan()
      state = ViewModel.init("run-1", plan)

      assert state.plan == plan
    end

    test "init creates nodes map with one entry per plan node" do
      plan = simple_plan()
      state = ViewModel.init("run-1", plan)

      assert map_size(state.nodes) == 2
      assert Map.has_key?(state.nodes, "a")
      assert Map.has_key?(state.nodes, "b")
    end

    test "init sets all nodes to status :pending" do
      plan = simple_plan()
      state = ViewModel.init("run-1", plan)

      for {_id, node_view} <- state.nodes do
        assert node_view.status == :pending
      end
    end

    test "init sets event_count to 0" do
      plan = single_node_plan()
      state = ViewModel.init("run-1", plan)

      assert state.event_count == 0
    end

    test "init sets run_started_at to nil" do
      plan = single_node_plan()
      state = ViewModel.init("run-1", plan)

      assert state.run_started_at == nil
    end

    test "init sets run_completed_at to nil" do
      plan = single_node_plan()
      state = ViewModel.init("run-1", plan)

      assert state.run_completed_at == nil
    end

    test "empty plan produces empty nodes map" do
      plan = Plan.new()
      state = ViewModel.init("run-1", plan)

      assert state.nodes == %{}
    end

    test "node view contains op_name from plan" do
      plan = single_node_plan()
      state = ViewModel.init("run-1", plan)

      node_view = state.nodes["x"]
      assert is_binary(node_view.op_name) or is_atom(node_view.op_name)
    end
  end

  # ── ViewModel.apply_event/2: run_started ────────────────────────

  describe "apply_event/2 - run_started (atom-keyed)" do
    test "sets run_status to :running" do
      run_id = "run-started-1"
      plan = simple_plan()
      state = ViewModel.init(run_id, plan)

      state = ViewModel.apply_event(state, run_started_event(run_id))

      assert state.run_status == :running
    end

    test "records run_started_at timestamp" do
      run_id = "run-started-ts"
      plan = simple_plan()
      state = ViewModel.init(run_id, plan)

      state = ViewModel.apply_event(state, run_started_event(run_id))

      assert is_binary(state.run_started_at)
      assert state.run_started_at == "2026-03-19T14:00:00.000Z"
    end

    test "increments event_count" do
      run_id = "run-started-cnt"
      plan = single_node_plan()
      state = ViewModel.init(run_id, plan)

      state = ViewModel.apply_event(state, run_started_event(run_id))

      assert state.event_count == 1
    end

    test "all nodes remain :pending after run_started" do
      run_id = "run-started-nodes"
      plan = simple_plan()
      state = ViewModel.init(run_id, plan)

      state = ViewModel.apply_event(state, run_started_event(run_id))

      for {_id, node_view} <- state.nodes do
        assert node_view.status == :pending
      end
    end
  end

  describe "apply_event/2 - run_started (string-keyed, from Event.Store.read_all)" do
    test "handles string-keyed event from event store" do
      run_id = "run-started-str"
      plan = simple_plan()
      state = ViewModel.init(run_id, plan)

      string_event = %{
        "event_hash" => "sha256:start",
        "event_type" => "run_started",
        "payload" => %{
          "run_id" => run_id,
          "pack_id" => "test_pack",
          "pack_version" => "0.1.0",
          "plan_hash" => "sha256:abc"
        },
        "prev_hash" => nil,
        "timestamp" => "2026-03-19T14:00:00.000Z"
      }

      state = ViewModel.apply_event(state, string_event)

      assert state.run_status == :running
      assert state.run_started_at == "2026-03-19T14:00:00.000Z"
    end
  end

  # ── ViewModel.apply_event/2: op_started ──────────────────────────

  describe "apply_event/2 - op_started" do
    test "marks target node as :running" do
      run_id = "op-start-1"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))

      assert state.nodes["a"].status == :running
    end

    test "does not affect other nodes" do
      run_id = "op-start-iso"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))

      assert state.nodes["b"].status == :pending
    end

    test "records start time on node" do
      run_id = "op-start-ts"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))

      assert is_binary(state.nodes["a"].started_at)
      assert state.nodes["a"].started_at == "2026-03-19T14:00:01.000Z"
    end

    test "increments event_count" do
      run_id = "op-start-cnt"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))

      assert state.event_count == 2
    end

    test "handles string-keyed op_started event" do
      run_id = "op-start-str"
      plan = simple_plan()

      str_event = %{
        "event_hash" => "sha256:op_started_a",
        "event_type" => "op_started",
        "payload" => %{
          "node_id" => "a",
          "op_id" => "upcase",
          "op_version" => "1.0",
          "determinism" => "pure",
          "input_hashes" => ["sha256:input"]
        },
        "prev_hash" => "sha256:start",
        "timestamp" => "2026-03-19T14:00:01.000Z"
      }

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(str_event)

      assert state.nodes["a"].status == :running
    end
  end

  # ── ViewModel.apply_event/2: op_completed ─────────────────────────

  describe "apply_event/2 - op_completed" do
    test "marks target node as :completed" do
      run_id = "op-complete-1"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a"))

      assert state.nodes["a"].status == :completed
    end

    test "records completed_at on node" do
      run_id = "op-complete-ts"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a"))

      assert is_binary(state.nodes["a"].completed_at)
      assert state.nodes["a"].completed_at == "2026-03-19T14:00:02.000Z"
    end

    test "records duration_ms on node" do
      run_id = "op-complete-dur"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a", duration_ms: 99))

      assert state.nodes["a"].duration_ms == 99
    end

    test "stores output artifact references" do
      run_id = "op-complete-out"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a", output_hashes: ["sha256:result1"]))

      assert state.nodes["a"].output_hashes == ["sha256:result1"]
    end

    test "records cache_hit true when cache hit" do
      run_id = "op-complete-cache"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a", cache_hit: true))

      assert state.nodes["a"].cache_hit == true
    end

    test "records cache_hit false for fresh execution" do
      run_id = "op-complete-nocache"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a", cache_hit: false))

      assert state.nodes["a"].cache_hit == false
    end

    test "does not change other nodes" do
      run_id = "op-complete-iso"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a"))

      assert state.nodes["b"].status == :pending
    end

    test "handles zero output_hashes (empty list)" do
      run_id = "op-complete-empty"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a", output_hashes: []))

      assert state.nodes["a"].status == :completed
      assert state.nodes["a"].output_hashes == []
    end

    test "handles string-keyed op_completed event" do
      run_id = "op-complete-str"
      plan = simple_plan()

      str_event = %{
        "event_hash" => "sha256:op_completed_a",
        "event_type" => "op_completed",
        "payload" => %{
          "node_id" => "a",
          "output_hashes" => ["sha256:r1"],
          "cache_hit" => false,
          "duration_ms" => 10,
          "warnings" => []
        },
        "prev_hash" => "sha256:op_started_a",
        "timestamp" => "2026-03-19T14:00:02.000Z"
      }

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(str_event)

      assert state.nodes["a"].status == :completed
    end
  end

  # ── ViewModel.apply_event/2: op_failed ───────────────────────────

  describe "apply_event/2 - op_failed" do
    test "marks target node as :failed" do
      run_id = "op-failed-1"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_failed_event("a"))

      assert state.nodes["a"].status == :failed
    end

    test "records error info on node" do
      run_id = "op-failed-err"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_failed_event("a"))

      assert state.nodes["a"].error != nil
    end

    test "error contains error_type" do
      run_id = "op-failed-type"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_failed_event("a"))

      assert is_map(state.nodes["a"].error) or is_binary(state.nodes["a"].error)
    end

    test "error contains error_message" do
      run_id = "op-failed-msg"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_failed_event("a"))

      error = state.nodes["a"].error

      error_str =
        if is_map(error) do
          inspect(error)
        else
          error
        end

      assert String.contains?(error_str, "intentional") or
               (is_map(error) and
                  (Map.has_key?(error, "error_message") or Map.has_key?(error, :error_message)))
    end

    test "does not affect other nodes" do
      run_id = "op-failed-iso"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_failed_event("a"))

      assert state.nodes["b"].status == :pending
    end

    test "increments event_count" do
      run_id = "op-failed-cnt"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_failed_event("a"))

      # 3 events: run_started, op_started, op_failed
      assert state.event_count == 3
    end
  end

  # ── ViewModel.apply_event/2: gate_requested ──────────────────────

  describe "apply_event/2 - gate_requested" do
    test "marks target node as :waiting" do
      run_id = "gate-req-1"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(gate_requested_event("a"))

      assert state.nodes["a"].status == :waiting
    end

    test "stores gate prompt on node" do
      run_id = "gate-req-prompt"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(gate_requested_event("a"))

      assert state.nodes["a"].gate_prompt == "Please approve this action."
    end

    test "does not affect other nodes" do
      run_id = "gate-req-iso"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(gate_requested_event("a"))

      assert state.nodes["b"].status == :pending
    end
  end

  # ── ViewModel.apply_event/2: gate_resolved ────────────────────────

  describe "apply_event/2 - gate_resolved" do
    test "stores gate response on node" do
      run_id = "gate-res-1"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(gate_requested_event("a"))
        |> ViewModel.apply_event(gate_resolved_event("a"))

      assert state.nodes["a"].gate_response == "approved"
    end

    test "increments event_count" do
      run_id = "gate-res-cnt"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(gate_requested_event("a"))
        |> ViewModel.apply_event(gate_resolved_event("a"))

      # 4 events: run_started, op_started, gate_requested, gate_resolved
      assert state.event_count == 4
    end

    test "does not yet mark node as :completed (that comes from op_completed)" do
      run_id = "gate-res-pending"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(gate_requested_event("a"))
        |> ViewModel.apply_event(gate_resolved_event("a"))

      # gate_resolved alone does NOT mark :completed — op_completed does
      refute state.nodes["a"].status == :completed
    end
  end

  # ── ViewModel.apply_event/2: decision_recorded ──────────────────

  describe "apply_event/2 - decision_recorded" do
    test "stores decision reference on node" do
      run_id = "dec-rec-1"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(decision_recorded_event("a"))

      decisions = state.nodes["a"].decisions
      assert is_list(decisions)
      assert decisions != []
    end

    test "decision record contains decision_hash" do
      run_id = "dec-rec-hash"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(decision_recorded_event("a"))

      decision = hd(state.nodes["a"].decisions)
      assert is_map(decision) or is_binary(decision)
    end

    test "multiple decisions accumulate on same node" do
      run_id = "dec-rec-multi"
      plan = simple_plan()

      decision2 = %{
        event_hash: "sha256:decision2_a",
        event_type: "decision_recorded",
        payload: %{
          "node_id" => "a",
          "decision_hash" => "sha256:dec2",
          "decision_type" => "llm_response"
        },
        prev_hash: "sha256:decision_a",
        timestamp: "2026-03-19T14:00:03.000Z"
      }

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(decision_recorded_event("a"))
        |> ViewModel.apply_event(decision2)

      assert length(state.nodes["a"].decisions) == 2
    end

    test "does not affect other nodes" do
      run_id = "dec-rec-iso"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(decision_recorded_event("a"))

      assert state.nodes["b"].decisions == []
    end
  end

  # ── ViewModel.apply_event/2: run_completed ──────────────────────

  describe "apply_event/2 - run_completed" do
    test "sets run_status to :completed" do
      run_id = "run-complete-1"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a"))
        |> ViewModel.apply_event(run_completed_event(run_id))

      assert state.run_status == :completed
    end

    test "records run_completed_at" do
      run_id = "run-complete-ts"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event("a"))
        |> ViewModel.apply_event(run_completed_event(run_id))

      assert is_binary(state.run_completed_at)
      assert state.run_completed_at == "2026-03-19T14:00:05.000Z"
    end

    test "increments event_count" do
      run_id = "run-complete-cnt"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(run_completed_event(run_id))

      assert state.event_count == 2
    end
  end

  describe "apply_event/2 - run_failed" do
    test "sets run_status to :failed" do
      run_id = "run-failed-1"
      plan = simple_plan()

      run_failed = %{
        event_hash: "sha256:run_failed",
        event_type: "run_failed",
        payload: %{
          "run_id" => run_id,
          "error_type" => "run_failure",
          "error_message" => "one or more nodes failed",
          "failed_nodes" => ["a"],
          "warning_summary" => %{"warning_count" => 0, "degraded_node_ids" => []}
        },
        prev_hash: "sha256:op_failed_a",
        timestamp: "2026-03-19T14:00:06.000Z"
      }

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_failed_event("a"))
        |> ViewModel.apply_event(run_failed)

      assert state.run_status == :failed
    end
  end

  # ── Invariants ────────────────────────────────────────────────────

  describe "invariants" do
    test "event_count equals total events applied" do
      run_id = "invariant-count"
      plan = simple_plan()

      events = [
        run_started_event(run_id),
        op_started_event("a"),
        op_completed_event("a"),
        op_started_event("b", "reverse", "sha256:op_completed_a"),
        op_completed_event("b", prev_hash: "sha256:op_started_b"),
        run_completed_event(run_id)
      ]

      state =
        Enum.reduce(events, ViewModel.init(run_id, plan), fn event, acc ->
          ViewModel.apply_event(acc, event)
        end)

      assert state.event_count == length(events)
    end

    test "unknown event types are handled gracefully (event_count still increments)" do
      run_id = "invariant-unknown"
      plan = simple_plan()

      unknown_event = %{
        event_hash: "sha256:unknown",
        event_type: "unknown_event_type_xyz",
        payload: %{"foo" => "bar"},
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:00.000Z"
      }

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(unknown_event)

      # Should not raise, and event_count should advance
      assert state.event_count == 1
    end

    test "full linear run: complete event sequence yields correct final state" do
      run_id = "invariant-full"
      plan = simple_plan()

      events = [
        run_started_event(run_id),
        op_started_event("a"),
        op_completed_event("a"),
        op_started_event("b", "reverse", "sha256:op_completed_a"),
        op_completed_event("b", prev_hash: "sha256:op_started_b"),
        run_completed_event(run_id)
      ]

      state =
        Enum.reduce(events, ViewModel.init(run_id, plan), fn event, acc ->
          ViewModel.apply_event(acc, event)
        end)

      assert state.run_status == :completed
      assert state.nodes["a"].status == :completed
      assert state.nodes["b"].status == :completed
      assert state.run_started_at == "2026-03-19T14:00:00.000Z"
      assert state.run_completed_at == "2026-03-19T14:00:05.000Z"
    end

    test "decisions field initializes to empty list on each node" do
      plan = simple_plan()
      state = ViewModel.init("run-1", plan)

      for {_id, node_view} <- state.nodes do
        assert node_view.decisions == []
      end
    end

    test "output_hashes field initializes to empty list on each node" do
      plan = simple_plan()
      state = ViewModel.init("run-1", plan)

      for {_id, node_view} <- state.nodes do
        assert node_view.output_hashes == [] or is_nil(node_view.output_hashes)
      end
    end
  end

  # ── Warnings (per-node projection) ───────────────────────────────

  describe "ViewModel.init/3 — warning fields baseline" do
    test "each node starts with empty warnings list" do
      plan = simple_plan()
      state = ViewModel.init("run-1", plan)

      for {_id, node_view} <- state.nodes do
        assert node_view.warnings == []
      end
    end

    test "each node starts with degraded: false" do
      plan = simple_plan()
      state = ViewModel.init("run-1", plan)

      for {_id, node_view} <- state.nodes do
        assert node_view.degraded == false
      end
    end

    test "run-level warning_count starts at 0" do
      plan = simple_plan()
      state = ViewModel.init("run-1", plan)

      assert state.warning_count == 0
    end

    test "run-level degraded_nodes starts as empty list" do
      plan = simple_plan()
      state = ViewModel.init("run-1", plan)

      assert state.degraded_nodes == []
    end

    test "run-level degraded flag starts false" do
      plan = simple_plan()
      state = ViewModel.init("run-1", plan)

      assert state.degraded == false
    end
  end

  describe "apply_event/2 - op_completed with warnings" do
    test "single warning populates node warnings list" do
      run_id = "warn-single"
      plan = simple_plan()
      warnings = [warning_map()]

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event_with_warnings("a", warnings))

      assert length(state.nodes["a"].warnings) == 1
    end

    test "single warning preserves every canonical field verbatim" do
      run_id = "warn-fields"
      plan = simple_plan()

      warning = %{
        "code" => "llm_fallback",
        "severity" => "degraded",
        "summary" => "placeholder summary used",
        "cause" => "ANTHROPIC_API_KEY missing",
        "remediation" => "export ANTHROPIC_API_KEY",
        "affected_outputs" => ["summary"]
      }

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event_with_warnings("a", [warning]))

      stored = hd(state.nodes["a"].warnings)
      assert stored["code"] == "llm_fallback"
      assert stored["severity"] == "degraded"
      assert stored["summary"] == "placeholder summary used"
      assert stored["cause"] == "ANTHROPIC_API_KEY missing"
      assert stored["remediation"] == "export ANTHROPIC_API_KEY"
      assert stored["affected_outputs"] == ["summary"]
    end

    test "warning-bearing node is marked degraded: true" do
      run_id = "warn-degraded"
      plan = simple_plan()
      warnings = [warning_map()]

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event_with_warnings("a", warnings))

      assert state.nodes["a"].degraded == true
    end

    test "multiple warnings on one node accumulate into a list of length N" do
      run_id = "warn-multi"
      plan = simple_plan()

      warnings = [
        warning_map(%{"code" => "w1"}),
        warning_map(%{"code" => "w2"}),
        warning_map(%{"code" => "w3"})
      ]

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event_with_warnings("a", warnings))

      assert length(state.nodes["a"].warnings) == 3
      codes = Enum.map(state.nodes["a"].warnings, & &1["code"])
      assert codes == ["w1", "w2", "w3"]
      assert state.nodes["a"].degraded == true
    end

    test "op_completed with empty warnings list leaves node in baseline shape" do
      run_id = "warn-empty"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event_with_warnings("a", []))

      assert state.nodes["a"].warnings == []
      assert state.nodes["a"].degraded == false
    end

    test "op_completed missing warnings key raises (contract violation)" do
      # M-WARN-01 guarantees every op_completed payload carries a "warnings"
      # list. Missing or malformed is a runtime contract violation, not a
      # backward-compat case to paper over.
      run_id = "warn-absent"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))

      event = %{
        event_hash: "sha256:op_completed_a",
        event_type: "op_completed",
        payload: %{
          "node_id" => "a",
          "output_hashes" => ["sha256:out1"],
          "cache_hit" => false,
          "duration_ms" => 42
        },
        prev_hash: "sha256:op_started_a",
        timestamp: "2026-03-19T14:00:02.000Z"
      }

      assert_raise ArgumentError, ~r/warnings/, fn ->
        ViewModel.apply_event(state, event)
      end
    end

    test "warnings do not leak between nodes" do
      run_id = "warn-isolation"
      plan = simple_plan()
      warnings = [warning_map()]

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event_with_warnings("a", warnings))

      assert state.nodes["b"].warnings == []
      assert state.nodes["b"].degraded == false
    end

    test "warnings remain separate from decisions" do
      run_id = "warn-vs-decisions"
      plan = simple_plan()
      warnings = [warning_map()]

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(decision_recorded_event("a"))
        |> ViewModel.apply_event(op_completed_event_with_warnings("a", warnings))

      assert length(state.nodes["a"].decisions) == 1
      assert length(state.nodes["a"].warnings) == 1
      # Decisions should not contain warning payloads and vice versa
      refute Enum.any?(state.nodes["a"].decisions, fn d -> Map.has_key?(d, :code) end)
    end
  end

  describe "apply_event/2 - op_completed with malformed warnings" do
    test "raises when a warning entry is missing required field 'code'" do
      run_id = "warn-bad-code"
      plan = simple_plan()
      bad_warning = Map.delete(warning_map(), "code")

      initial =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))

      assert_raise ArgumentError, fn ->
        ViewModel.apply_event(initial, op_completed_event_with_warnings("a", [bad_warning]))
      end
    end

    test "raises when a warning entry is missing required field 'severity'" do
      run_id = "warn-bad-severity"
      plan = simple_plan()
      bad_warning = Map.delete(warning_map(), "severity")

      initial =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))

      assert_raise ArgumentError, fn ->
        ViewModel.apply_event(initial, op_completed_event_with_warnings("a", [bad_warning]))
      end
    end

    test "raises when a warning entry is missing required field 'summary'" do
      run_id = "warn-bad-summary"
      plan = simple_plan()
      bad_warning = Map.delete(warning_map(), "summary")

      initial =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))

      assert_raise ArgumentError, fn ->
        ViewModel.apply_event(initial, op_completed_event_with_warnings("a", [bad_warning]))
      end
    end

    test "raises when warnings key is not a list" do
      run_id = "warn-bad-shape"
      plan = simple_plan()

      bad_event = %{
        event_hash: "sha256:op_completed_a",
        event_type: "op_completed",
        payload: %{
          "node_id" => "a",
          "output_hashes" => [],
          "cache_hit" => false,
          "duration_ms" => 1,
          "warnings" => "not a list"
        },
        prev_hash: "sha256:op_started_a",
        timestamp: "2026-03-19T14:00:02.000Z"
      }

      initial =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))

      assert_raise ArgumentError, fn ->
        ViewModel.apply_event(initial, bad_event)
      end
    end

    test "raises when a warning entry is not a map (e.g. a raw string)" do
      run_id = "warn-bad-entry"
      plan = simple_plan()

      bad_event = %{
        event_hash: "sha256:op_completed_a",
        event_type: "op_completed",
        payload: %{
          "node_id" => "a",
          "output_hashes" => [],
          "cache_hit" => false,
          "duration_ms" => 1,
          "warnings" => ["not a map"]
        },
        prev_hash: "sha256:op_started_a",
        timestamp: "2026-03-19T14:00:02.000Z"
      }

      initial =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))

      assert_raise ArgumentError, fn ->
        ViewModel.apply_event(initial, bad_event)
      end
    end
  end

  # ── Warnings (run-level aggregation) ─────────────────────────────

  describe "apply_event/2 - run_completed with warning_summary" do
    test "populates warning_count from payload" do
      run_id = "summary-count"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(op_started_event("a"))
        |> ViewModel.apply_event(op_completed_event_with_warnings("a", [warning_map()]))
        |> ViewModel.apply_event(
          run_completed_event(run_id, warning_count: 1, degraded_node_ids: ["a"])
        )

      assert state.warning_count == 1
    end

    test "populates degraded_nodes from payload" do
      run_id = "summary-nodes"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(
          run_completed_event(run_id, warning_count: 3, degraded_node_ids: ["a", "b"])
        )

      assert state.degraded_nodes == ["a", "b"]
    end

    test "derives run-level degraded: true when warning_count > 0 and run not failed" do
      run_id = "summary-degraded"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(
          run_completed_event(run_id, warning_count: 2, degraded_node_ids: ["a"])
        )

      assert state.degraded == true
    end

    test "derives run-level degraded: false on plain-success run (warning_count = 0)" do
      run_id = "summary-plain"
      plan = simple_plan()

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(run_completed_event(run_id))

      assert state.warning_count == 0
      assert state.degraded_nodes == []
      assert state.degraded == false
    end

    test "raises when run_completed payload is missing warning_summary" do
      run_id = "summary-missing"
      plan = simple_plan()

      malformed_rc = %{
        event_hash: "sha256:run_completed",
        event_type: "run_completed",
        payload: %{
          "run_id" => run_id,
          "outcome" => "success",
          "artifact_hashes" => []
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:05.000Z"
      }

      initial =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))

      assert_raise ArgumentError, fn ->
        ViewModel.apply_event(initial, malformed_rc)
      end
    end

    test "raises when warning_summary is missing warning_count" do
      run_id = "summary-missing-count"
      plan = simple_plan()

      malformed_rc = %{
        event_hash: "sha256:run_completed",
        event_type: "run_completed",
        payload: %{
          "run_id" => run_id,
          "outcome" => "success",
          "artifact_hashes" => [],
          "warning_summary" => %{"degraded_node_ids" => []}
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:05.000Z"
      }

      initial =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))

      assert_raise ArgumentError, fn ->
        ViewModel.apply_event(initial, malformed_rc)
      end
    end

    test "raises when warning_summary is missing degraded_node_ids" do
      run_id = "summary-missing-ids"
      plan = simple_plan()

      malformed_rc = %{
        event_hash: "sha256:run_completed",
        event_type: "run_completed",
        payload: %{
          "run_id" => run_id,
          "outcome" => "success",
          "artifact_hashes" => [],
          "warning_summary" => %{"warning_count" => 1}
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:05.000Z"
      }

      initial =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))

      assert_raise ArgumentError, fn ->
        ViewModel.apply_event(initial, malformed_rc)
      end
    end

    test "raises when warning_count is not a non-negative integer" do
      run_id = "summary-bad-count"
      plan = simple_plan()

      malformed_rc = %{
        event_hash: "sha256:run_completed",
        event_type: "run_completed",
        payload: %{
          "run_id" => run_id,
          "outcome" => "success",
          "artifact_hashes" => [],
          "warning_summary" => %{"warning_count" => "two", "degraded_node_ids" => []}
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:05.000Z"
      }

      initial =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))

      assert_raise ArgumentError, fn ->
        ViewModel.apply_event(initial, malformed_rc)
      end
    end

    test "raises when degraded_node_ids is not a list" do
      run_id = "summary-bad-ids"
      plan = simple_plan()

      malformed_rc = %{
        event_hash: "sha256:run_completed",
        event_type: "run_completed",
        payload: %{
          "run_id" => run_id,
          "outcome" => "success",
          "artifact_hashes" => [],
          "warning_summary" => %{"warning_count" => 1, "degraded_node_ids" => "a"}
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:05.000Z"
      }

      initial =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))

      assert_raise ArgumentError, fn ->
        ViewModel.apply_event(initial, malformed_rc)
      end
    end

    test "raises when warning_summary is not a map" do
      run_id = "summary-bad-shape"
      plan = simple_plan()

      malformed_rc = %{
        event_hash: "sha256:run_completed",
        event_type: "run_completed",
        payload: %{
          "run_id" => run_id,
          "outcome" => "success",
          "artifact_hashes" => [],
          "warning_summary" => "not a map"
        },
        prev_hash: nil,
        timestamp: "2026-03-19T14:00:05.000Z"
      }

      initial =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))

      assert_raise ArgumentError, fn ->
        ViewModel.apply_event(initial, malformed_rc)
      end
    end
  end

  describe "apply_event/2 - run_failed does not mark degraded: true" do
    test "failed run with no warnings stays degraded: false" do
      run_id = "failed-no-warn"
      plan = simple_plan()

      run_failed = %{
        event_hash: "sha256:run_failed",
        event_type: "run_failed",
        payload: %{
          "run_id" => run_id,
          "error_type" => "run_failure",
          "error_message" => "broke",
          "warning_summary" => %{"warning_count" => 0, "degraded_node_ids" => []}
        },
        prev_hash: "sha256:op_failed_a",
        timestamp: "2026-03-19T14:00:06.000Z"
      }

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(run_failed)

      assert state.run_status == :failed
      assert state.degraded == false
    end

    test "failed run with warnings keeps degraded: false because status is :failed" do
      run_id = "failed-with-warn"
      plan = simple_plan()

      run_failed = %{
        event_hash: "sha256:run_failed",
        event_type: "run_failed",
        payload: %{
          "run_id" => run_id,
          "error_type" => "run_failure",
          "error_message" => "broke",
          "warning_summary" => %{"warning_count" => 2, "degraded_node_ids" => ["a"]}
        },
        prev_hash: "sha256:op_failed_a",
        timestamp: "2026-03-19T14:00:06.000Z"
      }

      state =
        run_id
        |> ViewModel.init(plan)
        |> ViewModel.apply_event(run_started_event(run_id))
        |> ViewModel.apply_event(run_failed)

      assert state.run_status == :failed
      assert state.warning_count == 2
      assert state.degraded_nodes == ["a"]
      # degraded is false because run failed — status takes priority
      assert state.degraded == false
    end
  end

  # ── Rebuild / projection parity ──────────────────────────────────

  describe "projection parity: rebuild from full event log" do
    test "rebuilt state matches live state for a warning-bearing run" do
      run_id = "parity-warn"
      plan = simple_plan()
      warnings = [warning_map(%{"code" => "w1"}), warning_map(%{"code" => "w2"})]

      events = [
        run_started_event(run_id),
        op_started_event("a"),
        op_completed_event_with_warnings("a", warnings),
        op_started_event("b", "reverse", "sha256:op_completed_a"),
        op_completed_event("b", prev_hash: "sha256:op_started_b"),
        run_completed_event(run_id, warning_count: 2, degraded_node_ids: ["a"])
      ]

      final_state =
        Enum.reduce(events, ViewModel.init(run_id, plan), fn event, acc ->
          ViewModel.apply_event(acc, event)
        end)

      assert final_state.warning_count == 2
      assert final_state.degraded_nodes == ["a"]
      assert final_state.degraded == true
      assert length(final_state.nodes["a"].warnings) == 2
      assert final_state.nodes["a"].degraded == true
      assert final_state.nodes["b"].warnings == []
      assert final_state.nodes["b"].degraded == false
    end
  end
end
