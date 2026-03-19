defmodule Liminara.ToyPackTest do
  use ExUnit.Case, async: false

  alias Liminara.{Artifact, Event, Run}

  # M-OTP-05: ToyPack validation — exercises all four determinism classes,
  # gates, binary artifacts, cache, and replay through the async runtime.

  describe "full run" do
    test "parse → enrich → gate (auto) → render → deliver completes" do
      run_id = "toy-full-#{:erlang.unique_integer([:positive])}"

      # Auto-resolve the gate by subscribing and responding
      auto_resolve_gate(run_id)

      plan = Liminara.ToyPack.plan("test input")

      Run.Server.start(run_id, plan,
        pack_id: "toy_pack",
        pack_version: Liminara.ToyPack.version()
      )

      {:ok, result} = Run.Server.await(run_id, 10_000)
      assert result.status == :success
      assert Map.has_key?(result.outputs, "parse")
      assert Map.has_key?(result.outputs, "enrich")
      assert Map.has_key?(result.outputs, "gate")
      assert Map.has_key?(result.outputs, "render")
      assert Map.has_key?(result.outputs, "deliver")
    end

    test "gate pauses the run until resolved" do
      run_id = "toy-gate-pause-#{:erlang.unique_integer([:positive])}"

      # Subscribe but don't auto-resolve — the run should hang at gate
      :ok = Run.subscribe(run_id)

      plan = Liminara.ToyPack.plan("gate test")

      Run.Server.start(run_id, plan,
        pack_id: "toy_pack",
        pack_version: Liminara.ToyPack.version()
      )

      # Wait for gate_requested event
      gate_event = wait_for_event(run_id, "gate_requested", 5000)
      assert gate_event != nil

      # Run should NOT be complete yet
      assert {:error, :timeout} = Run.Server.await(run_id, 200)

      # Now resolve the gate
      Run.Server.resolve_gate(run_id, "gate", %{"approved" => true})

      {:ok, result} = Run.Server.await(run_id, 5000)
      assert result.status == :success
    end
  end

  describe "binary artifact" do
    test "render op produces binary blob stored by hash" do
      run_id = "toy-binary-#{:erlang.unique_integer([:positive])}"
      auto_resolve_gate(run_id)

      plan = Liminara.ToyPack.plan("binary test")

      Run.Server.start(run_id, plan,
        pack_id: "toy_pack",
        pack_version: Liminara.ToyPack.version()
      )

      {:ok, result} = Run.Server.await(run_id, 10_000)
      assert result.status == :success

      render_hash = result.outputs["render"]["result"]
      {:ok, content} = Artifact.Store.get(render_hash)

      # Should be a binary blob (simulated PDF with header)
      assert is_binary(content)
      assert String.starts_with?(content, "%PDF-SIMULATED")
    end
  end

  describe "cache behavior" do
    test "re-run: parse cache-hits, enrich re-executes" do
      # First run
      run_id1 = "toy-cache1-#{:erlang.unique_integer([:positive])}"
      auto_resolve_gate(run_id1)

      plan = Liminara.ToyPack.plan("cache test")

      Run.Server.start(run_id1, plan,
        pack_id: "toy_pack",
        pack_version: Liminara.ToyPack.version()
      )

      {:ok, _r1} = Run.Server.await(run_id1, 10_000)

      # Second run with same input
      run_id2 = "toy-cache2-#{:erlang.unique_integer([:positive])}"
      auto_resolve_gate(run_id2)

      Run.Server.start(run_id2, plan,
        pack_id: "toy_pack",
        pack_version: Liminara.ToyPack.version()
      )

      {:ok, _r2} = Run.Server.await(run_id2, 10_000)

      {:ok, events} = Event.Store.read_all(run_id2)

      parse_completed =
        Enum.find(events, fn e ->
          e["event_type"] == "op_completed" and e["payload"]["node_id"] == "parse"
        end)

      enrich_completed =
        Enum.find(events, fn e ->
          e["event_type"] == "op_completed" and e["payload"]["node_id"] == "enrich"
        end)

      assert parse_completed["payload"]["cache_hit"] == true
      assert enrich_completed["payload"]["cache_hit"] == false
    end
  end

  describe "replay" do
    test "replay injects decisions, skips delivery, output matches" do
      # Discovery run
      run_id1 = "toy-replay1-#{:erlang.unique_integer([:positive])}"
      auto_resolve_gate(run_id1)

      plan = Liminara.ToyPack.plan("replay test")

      Run.Server.start(run_id1, plan,
        pack_id: "toy_pack",
        pack_version: Liminara.ToyPack.version()
      )

      {:ok, discovery} = Run.Server.await(run_id1, 10_000)
      assert discovery.status == :success

      # Replay
      run_id2 = "toy-replay2-#{:erlang.unique_integer([:positive])}"

      Run.Server.start(run_id2, plan,
        pack_id: "toy_pack",
        pack_version: Liminara.ToyPack.version(),
        replay: run_id1
      )

      {:ok, replay} = Run.Server.await(run_id2, 10_000)
      assert replay.status == :success

      # Pure op output matches
      assert discovery.outputs["parse"] == replay.outputs["parse"]

      # Recordable op output matches (decision injected)
      {:ok, disc_enrich} = Artifact.Store.get(discovery.outputs["enrich"]["result"])
      {:ok, replay_enrich} = Artifact.Store.get(replay.outputs["enrich"]["result"])
      assert disc_enrich == replay_enrich

      # Side-effecting op skipped on replay
      {:ok, events} = Event.Store.read_all(run_id2)

      deliver_completed =
        Enum.find(events, fn e ->
          e["event_type"] == "op_completed" and e["payload"]["node_id"] == "deliver"
        end)

      assert deliver_completed["payload"]["cache_hit"] == true
    end
  end

  describe "public API" do
    test "ToyPack via Server API with all ops completes" do
      run_id = "toy-api-#{:erlang.unique_integer([:positive])}"
      auto_resolve_gate(run_id)

      plan = Liminara.ToyPack.plan("api test")

      Run.Server.start(run_id, plan,
        pack_id: "toy_pack",
        pack_version: Liminara.ToyPack.version()
      )

      {:ok, result} = Run.Server.await(run_id, 10_000)
      assert result.status == :success
      assert result.event_count > 0
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp auto_resolve_gate(run_id) do
    parent = self()

    spawn_link(fn ->
      :ok = Run.subscribe(run_id)
      send(parent, :gate_resolver_ready)
      auto_resolve_loop(run_id)
    end)

    receive do
      :gate_resolver_ready -> :ok
    after
      1000 -> raise "gate resolver didn't start"
    end
  end

  defp auto_resolve_loop(run_id) do
    receive do
      {:run_event, ^run_id, %{event_type: "gate_requested", payload: payload}} ->
        node_id = payload["node_id"]
        Run.Server.resolve_gate(run_id, node_id, %{"approved" => true})
        auto_resolve_loop(run_id)

      {:run_event, ^run_id, _event} ->
        auto_resolve_loop(run_id)
    after
      10_000 ->
        :ok
    end
  end

  defp wait_for_event(run_id, event_type, timeout) do
    receive do
      {:run_event, ^run_id, %{event_type: ^event_type} = event} ->
        event

      {:run_event, ^run_id, _other} ->
        wait_for_event(run_id, event_type, timeout)
    after
      timeout ->
        nil
    end
  end
end
