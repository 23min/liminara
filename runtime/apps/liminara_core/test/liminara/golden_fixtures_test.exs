defmodule Liminara.GoldenFixturesTest do
  use ExUnit.Case, async: true

  alias Liminara.{Canonical, Hash}

  @fixtures_dir Path.expand("../../../../../test_fixtures/golden_run", __DIR__)

  describe "event hash chain" do
    test "events.jsonl has valid hash chain" do
      events = read_events("events.jsonl")
      assert length(events) == 7

      Enum.reduce(events, nil, fn event, prev_hash ->
        assert event["prev_hash"] == prev_hash,
               "Event #{event["event_type"]}: prev_hash mismatch"

        expected_hash =
          Hash.hash_event(
            event["event_type"],
            event["payload"],
            event["prev_hash"],
            event["timestamp"]
          )

        assert event["event_hash"] == expected_hash,
               "Event #{event["event_type"]}: event_hash mismatch"

        event["event_hash"]
      end)
    end

    test "events_tampered.jsonl fails hash chain verification" do
      events = read_events("events_tampered.jsonl")

      result =
        Enum.reduce_while(events, {nil, :ok}, fn event, {prev_hash, :ok} ->
          expected_hash =
            Hash.hash_event(
              event["event_type"],
              event["payload"],
              event["prev_hash"],
              event["timestamp"]
            )

          cond do
            event["prev_hash"] != prev_hash ->
              {:halt, {:error, "prev_hash mismatch"}}

            event["event_hash"] != expected_hash ->
              {:halt, {:error, "event_hash mismatch"}}

            true ->
              {:cont, {event["event_hash"], :ok}}
          end
        end)

      assert match?({:error, _}, result), "Tampered log should fail verification"
    end
  end

  describe "run seal" do
    test "seal matches final event hash" do
      events = read_events("events.jsonl")
      final_event = List.last(events)

      seal = read_json("seal.json")

      assert seal["run_seal"] == final_event["event_hash"]
      assert seal["event_count"] == length(events)
      assert seal["run_id"] == "test_pack-20260315T120000-aabbccdd"
      assert seal["completed_at"] == final_event["timestamp"]
    end
  end

  describe "decision record" do
    test "decision_hash is valid" do
      decision = read_json("decisions/summarize.json")

      # Recompute hash over all fields except decision_hash
      assert Hash.hash_decision(decision) == decision["decision_hash"]
    end

    test "decision_hash matches event reference" do
      decision = read_json("decisions/summarize.json")
      events = read_events("events.jsonl")

      decision_event =
        Enum.find(events, &(&1["event_type"] == "decision_recorded"))

      assert decision_event["payload"]["decision_hash"] == decision["decision_hash"]
    end
  end

  describe "artifact blobs" do
    test "artifact content hashes match paths" do
      events = read_events("events.jsonl")

      artifact_hashes =
        events
        |> Enum.filter(&(&1["event_type"] == "op_completed"))
        |> Enum.flat_map(& &1["payload"]["output_hashes"])

      assert length(artifact_hashes) == 2

      for hash <- artifact_hashes do
        hex = String.replace_prefix(hash, "sha256:", "")

        path =
          Path.join([
            @fixtures_dir,
            "artifacts",
            String.slice(hex, 0, 2),
            String.slice(hex, 2, 2),
            hex
          ])

        assert File.exists?(path), "Artifact file missing: #{path}"

        content = File.read!(path)
        assert Hash.hash_bytes(content) == hash, "Artifact content hash mismatch for #{hex}"
      end
    end
  end

  describe "canary" do
    test "canonical JSON and hash match expected values" do
      canary = %{"z" => 1, "a" => [true, nil, "hello"], "m" => %{"nested" => 42}}

      canonical = Canonical.encode(canary)
      hash = Hash.hash_bytes(canonical)

      assert canonical == ~s({"a":[true,null,"hello"],"m":{"nested":42},"z":1})
      assert hash == "sha256:0fa7f2a293c29e7a21ddaa8cf24c99d6740a85353793a6bc92abdc9ab538637e"
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp read_events(filename) do
    Path.join(@fixtures_dir, filename)
    |> File.read!()
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(&Jason.decode!/1)
  end

  defp read_json(filename) do
    Path.join(@fixtures_dir, filename)
    |> File.read!()
    |> Jason.decode!()
  end
end
