defmodule Liminara.Event.StoreTest do
  use ExUnit.Case, async: true

  alias Liminara.Event.Store

  @fixtures_dir Path.expand("../../../../../../test_fixtures/golden_run", __DIR__)

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_event_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    %{runs_root: tmp, run_id: "test-run-001"}
  end

  describe "append/5 and read_all/2" do
    test "append one event, read it back", %{runs_root: root, run_id: run_id} do
      {:ok, event} = Store.append(root, run_id, "run_started", %{"run_id" => run_id}, nil)

      assert {:ok, [read_event]} = Store.read_all(root, run_id)
      assert read_event["event_type"] == "run_started"
      assert read_event["event_hash"] == event.event_hash
    end

    test "event has all required fields", %{runs_root: root, run_id: run_id} do
      {:ok, event} = Store.append(root, run_id, "run_started", %{"run_id" => run_id}, nil)

      assert is_binary(event.event_hash)
      assert event.event_type == "run_started"
      assert event.payload == %{"run_id" => run_id}
      assert event.prev_hash == nil
      assert is_binary(event.timestamp)
    end

    test "payload is preserved exactly", %{runs_root: root, run_id: run_id} do
      payload = %{"node_id" => "fetch", "determinism" => "pinned_env", "input_hashes" => []}
      {:ok, _event} = Store.append(root, run_id, "op_started", payload, nil)

      {:ok, [read_event]} = Store.read_all(root, run_id)
      assert read_event["payload"] == payload
    end

    test "append multiple events, read all in order", %{runs_root: root, run_id: run_id} do
      {:ok, e1} = Store.append(root, run_id, "run_started", %{"run_id" => run_id}, nil)
      {:ok, e2} = Store.append(root, run_id, "op_started", %{"node_id" => "a"}, e1.event_hash)
      {:ok, _e3} = Store.append(root, run_id, "op_completed", %{"node_id" => "a"}, e2.event_hash)

      {:ok, events} = Store.read_all(root, run_id)
      assert length(events) == 3
      assert Enum.map(events, & &1["event_type"]) == ["run_started", "op_started", "op_completed"]
    end
  end

  describe "hash chain" do
    test "first event has prev_hash nil", %{runs_root: root, run_id: run_id} do
      {:ok, event} = Store.append(root, run_id, "run_started", %{}, nil)
      assert event.prev_hash == nil

      {:ok, [read_event]} = Store.read_all(root, run_id)
      assert read_event["prev_hash"] == nil
    end

    test "second event prev_hash equals first event_hash", %{runs_root: root, run_id: run_id} do
      {:ok, e1} = Store.append(root, run_id, "run_started", %{}, nil)
      {:ok, e2} = Store.append(root, run_id, "op_started", %{}, e1.event_hash)

      assert e2.prev_hash == e1.event_hash
    end

    test "chain of 5 events verifies", %{runs_root: root, run_id: run_id} do
      {:ok, e1} = Store.append(root, run_id, "run_started", %{"run_id" => run_id}, nil)
      {:ok, e2} = Store.append(root, run_id, "op_started", %{"node_id" => "a"}, e1.event_hash)

      {:ok, e3} =
        Store.append(root, run_id, "op_completed", %{"node_id" => "a"}, e2.event_hash)

      {:ok, e4} = Store.append(root, run_id, "op_started", %{"node_id" => "b"}, e3.event_hash)

      {:ok, _e5} =
        Store.append(root, run_id, "op_completed", %{"node_id" => "b"}, e4.event_hash)

      assert {:ok, 5} = Store.verify(root, run_id)
    end
  end

  describe "verify/2" do
    test "valid chain passes", %{runs_root: root, run_id: run_id} do
      {:ok, e1} = Store.append(root, run_id, "run_started", %{}, nil)
      {:ok, _e2} = Store.append(root, run_id, "run_completed", %{}, e1.event_hash)

      assert {:ok, 2} = Store.verify(root, run_id)
    end

    test "empty log passes", %{runs_root: root, run_id: run_id} do
      assert {:ok, 0} = Store.verify(root, run_id)
    end

    test "tampered event detected", %{runs_root: root, run_id: run_id} do
      {:ok, e1} = Store.append(root, run_id, "run_started", %{"run_id" => run_id}, nil)
      {:ok, e2} = Store.append(root, run_id, "op_started", %{"node_id" => "a"}, e1.event_hash)
      {:ok, _e3} = Store.append(root, run_id, "op_completed", %{"node_id" => "a"}, e2.event_hash)

      # Tamper with middle event
      events_path = Path.join([root, run_id, "events.jsonl"])
      lines = events_path |> File.read!() |> String.trim() |> String.split("\n")

      tampered_event =
        lines |> Enum.at(1) |> Jason.decode!() |> put_in(["payload", "node_id"], "TAMPERED")

      tampered_line = tampered_event |> Jason.encode!()
      new_lines = List.replace_at(lines, 1, tampered_line)
      File.write!(events_path, Enum.join(new_lines, "\n") <> "\n")

      assert {:error, _index, _reason} = Store.verify(root, run_id)
    end
  end

  describe "write_seal/2" do
    test "writes seal with correct fields", %{runs_root: root, run_id: run_id} do
      {:ok, e1} = Store.append(root, run_id, "run_started", %{"run_id" => run_id}, nil)

      {:ok, _e2} =
        Store.append(
          root,
          run_id,
          "run_completed",
          %{"run_id" => run_id, "outcome" => "success"},
          e1.event_hash
        )

      {:ok, seal} = Store.write_seal(root, run_id)

      assert seal["run_id"] == run_id
      assert seal["run_seal"] =~ ~r/^sha256:[a-f0-9]{64}$/
      assert seal["event_count"] == 2
      assert is_binary(seal["completed_at"])
    end

    test "seal run_seal equals final event hash", %{runs_root: root, run_id: run_id} do
      {:ok, e1} = Store.append(root, run_id, "run_started", %{}, nil)
      {:ok, e2} = Store.append(root, run_id, "run_completed", %{}, e1.event_hash)

      {:ok, seal} = Store.write_seal(root, run_id)
      assert seal["run_seal"] == e2.event_hash
    end

    test "seal file is canonical JSON", %{runs_root: root, run_id: run_id} do
      {:ok, e1} = Store.append(root, run_id, "run_started", %{}, nil)
      {:ok, _e2} = Store.append(root, run_id, "run_completed", %{}, e1.event_hash)

      {:ok, _seal} = Store.write_seal(root, run_id)

      seal_path = Path.join([root, run_id, "seal.json"])
      raw = File.read!(seal_path)
      # Canonical JSON: sorted keys, no whitespace
      decoded = Jason.decode!(raw)
      assert raw == Liminara.Canonical.encode(decoded)
    end
  end

  describe "golden fixtures" do
    test "read_all returns 7 events" do
      # Read golden fixtures using the store's read_all
      # The golden fixtures are at a different path structure, so we read directly
      events_path = Path.join(@fixtures_dir, "events.jsonl")

      events =
        events_path
        |> File.read!()
        |> String.trim()
        |> String.split("\n")
        |> Enum.map(&Jason.decode!/1)

      assert length(events) == 7
    end

    test "verify passes on golden events", %{runs_root: root} do
      # Copy golden events to a temp run directory so verify/2 can read them
      run_id = "golden"
      run_dir = Path.join(root, run_id)
      File.mkdir_p!(run_dir)
      File.cp!(Path.join(@fixtures_dir, "events.jsonl"), Path.join(run_dir, "events.jsonl"))

      assert {:ok, 7} = Store.verify(root, run_id)
    end

    test "verify fails on tampered events", %{runs_root: root} do
      run_id = "tampered"
      run_dir = Path.join(root, run_id)
      File.mkdir_p!(run_dir)

      File.cp!(
        Path.join(@fixtures_dir, "events_tampered.jsonl"),
        Path.join(run_dir, "events.jsonl")
      )

      assert {:error, _index, _reason} = Store.verify(root, run_id)
    end

    test "golden seal matches expected values" do
      seal =
        @fixtures_dir
        |> Path.join("seal.json")
        |> File.read!()
        |> Jason.decode!()

      assert seal["run_id"] == "test_pack-20260315T120000-aabbccdd"
      assert seal["event_count"] == 7

      assert seal["run_seal"] ==
               "sha256:3bdc79afaaba33d74d53f619944c73778f5cbb5cad3720a80749307039080ded"
    end
  end

  describe "timestamp format" do
    test "matches ISO 8601 UTC with milliseconds", %{runs_root: root, run_id: run_id} do
      {:ok, event} = Store.append(root, run_id, "run_started", %{}, nil)
      assert event.timestamp =~ ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/
    end
  end

  describe "edge cases" do
    test "read_all on non-existent run returns empty list", %{runs_root: root} do
      assert {:ok, []} = Store.read_all(root, "nonexistent-run")
    end
  end
end
