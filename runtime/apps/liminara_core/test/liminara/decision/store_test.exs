defmodule Liminara.Decision.StoreTest do
  use ExUnit.Case, async: true

  alias Liminara.Decision.Store
  alias Liminara.Hash

  @fixtures_dir Path.expand("../../../../../../test_fixtures/golden_run", __DIR__)

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_decision_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    %{runs_root: tmp, run_id: "test-run-001"}
  end

  describe "put/3 and get/3 round-trip" do
    test "put returns a sha256 hash", %{runs_root: root, run_id: run_id} do
      record = %{
        "node_id" => "summarize",
        "decision_type" => "llm_response",
        "recorded_at" => "2026-03-15T12:00:00.000Z"
      }

      {:ok, hash} = Store.put(root, run_id, record)
      assert hash =~ ~r/^sha256:[a-f0-9]{64}$/
    end

    test "get returns record with decision_hash included", %{runs_root: root, run_id: run_id} do
      record = %{
        "node_id" => "summarize",
        "decision_type" => "llm_response",
        "recorded_at" => "2026-03-15T12:00:00.000Z"
      }

      {:ok, hash} = Store.put(root, run_id, record)
      {:ok, read_record} = Store.get(root, run_id, "summarize")

      assert read_record["decision_hash"] == hash
      assert read_record["node_id"] == "summarize"
      assert read_record["decision_type"] == "llm_response"
    end

    test "all original fields preserved", %{runs_root: root, run_id: run_id} do
      record = %{
        "node_id" => "summarize",
        "op_id" => "summarize_text",
        "op_version" => "1.0",
        "decision_type" => "llm_response",
        "inputs" => %{"model_id" => "claude-sonnet-4-6", "temperature" => 0.7},
        "output" => %{
          "response_hash" => "sha256:abc123",
          "token_usage" => %{"input" => 100, "output" => 50}
        },
        "recorded_at" => "2026-03-15T12:00:00.000Z"
      }

      {:ok, _hash} = Store.put(root, run_id, record)
      {:ok, read_record} = Store.get(root, run_id, "summarize")

      for {key, value} <- record do
        assert read_record[key] == value, "Field #{key} mismatch"
      end
    end
  end

  describe "hash computation" do
    test "hash is computed over all fields except decision_hash", %{
      runs_root: root,
      run_id: run_id
    } do
      record = %{
        "node_id" => "test_node",
        "decision_type" => "llm_response",
        "recorded_at" => "2026-03-15T12:00:00.000Z"
      }

      {:ok, hash} = Store.put(root, run_id, record)
      assert hash == Hash.hash_decision(record)
    end

    test "same record produces same hash on repeated puts", %{runs_root: root, run_id: run_id} do
      record = %{
        "node_id" => "deterministic",
        "decision_type" => "llm_response",
        "recorded_at" => "2026-03-15T12:00:00.000Z"
      }

      {:ok, hash1} = Store.put(root, run_id, record)
      {:ok, hash2} = Store.put(root, run_id, record)
      assert hash1 == hash2
    end

    test "different records produce different hashes", %{runs_root: root, run_id: run_id} do
      record1 = %{
        "node_id" => "node_a",
        "decision_type" => "llm_response",
        "recorded_at" => "2026-03-15T12:00:00.000Z"
      }

      record2 = %{
        "node_id" => "node_b",
        "decision_type" => "llm_response",
        "recorded_at" => "2026-03-15T12:00:00.000Z"
      }

      {:ok, hash1} = Store.put(root, run_id, record1)
      {:ok, hash2} = Store.put(root, run_id, record2)
      assert hash1 != hash2
    end

    test "existing decision_hash in record is replaced with computed one", %{
      runs_root: root,
      run_id: run_id
    } do
      record = %{
        "node_id" => "with_hash",
        "decision_type" => "llm_response",
        "decision_hash" => "sha256:bogus",
        "recorded_at" => "2026-03-15T12:00:00.000Z"
      }

      {:ok, hash} = Store.put(root, run_id, record)
      assert hash != "sha256:bogus"
      assert hash == Hash.hash_decision(record)

      {:ok, read_record} = Store.get(root, run_id, "with_hash")
      assert read_record["decision_hash"] == hash
    end
  end

  describe "verify/3" do
    test "verify on correctly written record passes", %{runs_root: root, run_id: run_id} do
      record = %{
        "node_id" => "verified",
        "decision_type" => "llm_response",
        "recorded_at" => "2026-03-15T12:00:00.000Z"
      }

      {:ok, hash} = Store.put(root, run_id, record)
      assert {:ok, ^hash} = Store.verify(root, run_id, "verified")
    end

    test "verify on corrupted file returns error", %{runs_root: root, run_id: run_id} do
      record = %{
        "node_id" => "corrupted",
        "decision_type" => "llm_response",
        "recorded_at" => "2026-03-15T12:00:00.000Z"
      }

      {:ok, _hash} = Store.put(root, run_id, record)

      # Corrupt the file
      path = Path.join([root, run_id, "decisions", "corrupted.json"])
      corrupted = path |> File.read!() |> Jason.decode!() |> Map.put("decision_type", "TAMPERED")
      File.write!(path, Jason.encode!(corrupted))

      assert {:error, :hash_mismatch} = Store.verify(root, run_id, "corrupted")
    end
  end

  describe "golden fixtures" do
    test "read golden decision, fields match expected values" do
      decision =
        @fixtures_dir
        |> Path.join("decisions/summarize.json")
        |> File.read!()
        |> Jason.decode!()

      assert decision["node_id"] == "summarize"
      assert decision["decision_type"] == "llm_response"
      assert decision["op_id"] == "summarize_text"
      assert is_binary(decision["decision_hash"])
    end

    test "verify on golden decision passes" do
      decision =
        @fixtures_dir
        |> Path.join("decisions/summarize.json")
        |> File.read!()
        |> Jason.decode!()

      expected_hash = Hash.hash_decision(decision)
      assert decision["decision_hash"] == expected_hash
    end

    test "golden decision hash matches event reference" do
      decision =
        @fixtures_dir
        |> Path.join("decisions/summarize.json")
        |> File.read!()
        |> Jason.decode!()

      events =
        @fixtures_dir
        |> Path.join("events.jsonl")
        |> File.read!()
        |> String.trim()
        |> String.split("\n")
        |> Enum.map(&Jason.decode!/1)

      decision_event = Enum.find(events, &(&1["event_type"] == "decision_recorded"))
      assert decision_event["payload"]["decision_hash"] == decision["decision_hash"]
    end

    test "round-trip golden decision through store", %{runs_root: root, run_id: run_id} do
      original =
        @fixtures_dir
        |> Path.join("decisions/summarize.json")
        |> File.read!()
        |> Jason.decode!()

      # Remove decision_hash so put computes it fresh
      record = Map.delete(original, "decision_hash")
      {:ok, hash} = Store.put(root, run_id, record)

      assert hash == original["decision_hash"]

      {:ok, read_back} = Store.get(root, run_id, "summarize")
      assert read_back["decision_hash"] == original["decision_hash"]
    end
  end

  describe "edge cases" do
    test "get non-existent node_id returns error", %{runs_root: root, run_id: run_id} do
      assert {:error, :not_found} = Store.get(root, run_id, "nonexistent")
    end

    test "nested maps and arrays round-trip correctly", %{runs_root: root, run_id: run_id} do
      record = %{
        "node_id" => "nested",
        "decision_type" => "llm_response",
        "inputs" => %{
          "model_id" => "claude-sonnet-4-6",
          "tags" => ["a", "b", "c"],
          "config" => %{"nested" => %{"deep" => true}}
        },
        "recorded_at" => "2026-03-15T12:00:00.000Z"
      }

      {:ok, _hash} = Store.put(root, run_id, record)
      {:ok, read_back} = Store.get(root, run_id, "nested")

      assert read_back["inputs"] == record["inputs"]
    end

    test "floats serialize correctly", %{runs_root: root, run_id: run_id} do
      record = %{
        "node_id" => "floaty",
        "decision_type" => "llm_response",
        "inputs" => %{"temperature" => 0.7},
        "recorded_at" => "2026-03-15T12:00:00.000Z"
      }

      {:ok, _hash} = Store.put(root, run_id, record)
      {:ok, read_back} = Store.get(root, run_id, "floaty")

      assert read_back["inputs"]["temperature"] == 0.7
    end
  end
end
