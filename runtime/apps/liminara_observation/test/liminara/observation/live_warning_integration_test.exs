defmodule Liminara.Observation.LiveWarningIntegrationTest do
  @moduledoc """
  M-WARN-04 bug_005 regression: verify that a real `%Liminara.Warning{}`
  routed through `Run.Server → :pg → Observation.Server → ViewModel` does
  not crash the observer on the live-broadcast path.

  Before the fix, `Run.Server.warning_payload/1` emitted atom-keyed maps
  (via `Map.from_struct/1`) while `ViewModel.validate_warning_entry!/1`
  required string keys. Replay worked because the JSON event log round-trip
  normalised keys, but the live broadcast (which goes through `:pg` with
  no JSON round-trip) crashed `Observation.Server` on the first
  `op_completed` event carrying a warning.

  This test pins the wire shape: live `:pg` broadcasts must present
  string-keyed warning payloads that match the JSON-roundtripped replay
  shape — enforced at the emission boundary, not normalised downstream.
  """

  use ExUnit.Case, async: false

  alias Liminara.Observation.{Server, ViewModel}
  alias Liminara.{Plan, Run}

  # ── Helpers ────────────────────────────────────────────────────────

  defp unique_run_id(prefix) do
    rand = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{prefix}-#{rand}"
  end

  defp await_observation(obs_pid, condition_fn, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    do_await_observation(obs_pid, condition_fn, deadline)
  end

  defp do_await_observation(obs_pid, condition_fn, deadline) do
    state = Server.get_state(obs_pid)

    if condition_fn.(state) do
      state
    else
      if System.monotonic_time(:millisecond) > deadline do
        flunk(
          "await_observation timed out. Last state: #{inspect(state, pretty: true, limit: 5)}"
        )
      else
        Process.sleep(20)
        do_await_observation(obs_pid, condition_fn, deadline)
      end
    end
  end

  # ── Live warning propagation ──────────────────────────────────────

  describe "bug_005: live warning payload crosses Run.Server → :pg → Observation.Server" do
    test "a single %Warning{} reaches ViewModel.apply_event without raising" do
      run_id = unique_run_id("live-warn-single")

      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithSingleWarningUncachedSpec, %{
          "text" => {:literal, "hello"}
        })

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)
      ref = Process.monitor(obs_pid)

      Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id, 5_000)
      assert result.status == :success

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)

      # The observer must still be alive — pre-fix, it crashed on the
      # first op_completed event carrying a warning.
      refute_receive {:DOWN, ^ref, :process, _pid, _reason}, 100
      assert Process.alive?(obs_pid)

      # Per-node projection must be populated, not silently empty.
      assert state.nodes["warn"].status == :completed
      assert state.nodes["warn"].degraded == true
      assert length(state.nodes["warn"].warnings) == 1

      # Run-level aggregation must agree.
      assert state.warning_count == 1
      assert state.degraded_nodes == ["warn"]
      assert state.degraded == true

      GenServer.stop(obs_pid)
    end

    test "live warning entry is string-keyed with string severity (wire shape)" do
      run_id = unique_run_id("live-warn-shape")

      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithSingleWarningUncachedSpec, %{
          "text" => {:literal, "hello"}
        })

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, _result} = Run.Server.await(run_id, 5_000)

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)

      [entry] = state.nodes["warn"].warnings

      # Wire shape: string keys, string severity.
      assert is_map(entry)
      assert Map.has_key?(entry, "code")
      assert Map.has_key?(entry, "severity")
      assert Map.has_key?(entry, "summary")
      # Must not carry the original atom-keyed struct shape.
      refute Map.has_key?(entry, :code)
      refute Map.has_key?(entry, :severity)

      # Severity must be normalised to a string (matches the replay
      # shape produced by JSON round-trip).
      assert entry["severity"] == "low"
      assert is_binary(entry["severity"])

      assert entry["code"] == "uncached_warning"
      assert entry["summary"] == "warning emitted by an uncached op"

      GenServer.stop(obs_pid)
    end

    test "multiple warnings on one node all propagate as string-keyed entries" do
      run_id = unique_run_id("live-warn-multi")

      plan =
        Plan.new()
        |> Plan.add_node("multi", Liminara.TestOps.WithMultipleWarningsSpec, %{
          "text" => {:literal, "hello"}
        })

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id, 5_000)
      assert result.status == :success
      assert result.warning_count == 3

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)

      warnings = state.nodes["multi"].warnings
      assert length(warnings) == 3
      assert Enum.all?(warnings, &Map.has_key?(&1, "code"))
      assert Enum.all?(warnings, &Map.has_key?(&1, "severity"))
      assert Enum.all?(warnings, fn w -> is_binary(w["severity"]) end)

      codes = Enum.map(warnings, & &1["code"]) |> Enum.sort()
      assert codes == ["w1", "w2", "w3"]

      GenServer.stop(obs_pid)
    end

    test "plain-map-emitting op (string-keyed map input to warning_payload) propagates as string-keyed entry" do
      # Coverage for the second head of `warning_payload/1` in Run.Server:
      # the op returns a plain string-keyed map (not a %Warning{} struct).
      # stringify_warning_map/1 must be idempotent on already-string keys.
      run_id = unique_run_id("live-warn-plain-map")

      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithWarningMap, %{
          "text" => {:literal, "hello"}
        })

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, result} = Run.Server.await(run_id, 5_000)
      assert result.status == :success

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)

      [entry] = state.nodes["warn"].warnings
      assert entry["code"] == "inline_warning"
      assert entry["severity"] == "low"
      assert entry["summary"] == "warning map from inline op"
      # No atom-keyed leakage even when the input was already string-keyed.
      refute Map.has_key?(entry, :code)
      refute Map.has_key?(entry, :severity)

      GenServer.stop(obs_pid)
    end

    test "optional fields: nil cause/remediation and empty affected_outputs still validate" do
      # Bug 005 edge case: a warning built from the struct with nil
      # optional fields must still be accepted by the ViewModel on the
      # live path.
      run_id = unique_run_id("live-warn-optionals")

      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithSingleWarningUncachedSpec, %{
          "text" => {:literal, "hello"}
        })

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)

      Run.Server.start(run_id, plan)
      {:ok, _result} = Run.Server.await(run_id, 5_000)

      state = await_observation(obs_pid, fn s -> s.run_status == :completed end)

      [entry] = state.nodes["warn"].warnings
      # The struct had cause/remediation = nil and affected_outputs = [];
      # those must survive verbatim as string-keyed entries.
      assert Map.has_key?(entry, "cause")
      assert Map.has_key?(entry, "remediation")
      assert Map.has_key?(entry, "affected_outputs")
      assert entry["cause"] == nil
      assert entry["remediation"] == nil
      assert entry["affected_outputs"] == []

      GenServer.stop(obs_pid)
    end
  end

  describe "bug_005: replay path parity (regression guard)" do
    test "replayed run reproduces the same per-node warning shape as live" do
      # Replay already passed pre-fix because the event log JSON
      # round-trip normalised keys. This test ensures the wire-shape fix
      # does not regress the replay path.
      run_id = unique_run_id("live-warn-replay")

      plan =
        Plan.new()
        |> Plan.add_node("warn", Liminara.TestOps.WithSingleWarningUncachedSpec, %{
          "text" => {:literal, "hello"}
        })

      {:ok, obs_pid} = Server.start_link(run_id: run_id, plan: plan)
      Run.Server.start(run_id, plan)
      {:ok, _result} = Run.Server.await(run_id, 5_000)

      live_state = await_observation(obs_pid, fn s -> s.run_status == :completed end)
      GenServer.stop(obs_pid)

      # Start a fresh observer AFTER completion — rebuilds from the
      # persisted event log (JSON round-trip).
      Process.sleep(50)
      {:ok, obs_pid2} = Server.start_link(run_id: run_id, plan: plan)
      replay_state = await_observation(obs_pid2, fn s -> s.run_status == :completed end)

      # Per-node shape parity.
      assert replay_state.nodes["warn"].warnings == live_state.nodes["warn"].warnings
      assert replay_state.nodes["warn"].degraded == live_state.nodes["warn"].degraded

      GenServer.stop(obs_pid2)
    end
  end

  describe "bug_005: contract enforcement preserved" do
    test "malformed warning (missing required field) still raises on the live path" do
      # Error-case regression: the fix is a wire-shape change, not a
      # contract weakening. A warning payload missing required fields
      # must still raise ArgumentError in the ViewModel, even on the
      # live path.
      run_id = unique_run_id("live-warn-bad")

      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hi"}})

      state = ViewModel.init(run_id, plan)

      malformed_event = %{
        event_hash: "sha256:bad",
        event_type: "op_completed",
        payload: %{
          "node_id" => "a",
          "output_hashes" => ["sha256:x"],
          "cache_hit" => false,
          "duration_ms" => 1,
          # Missing required "severity" and "summary"; only "code" present.
          "warnings" => [%{"code" => "missing_fields"}]
        },
        prev_hash: nil,
        timestamp: "2026-04-20T00:00:00.000Z"
      }

      assert_raise ArgumentError, fn ->
        ViewModel.apply_event(state, malformed_event)
      end
    end
  end
end
