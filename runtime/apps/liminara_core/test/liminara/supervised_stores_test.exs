defmodule Liminara.SupervisedStoresTest do
  use ExUnit.Case, async: false

  # Tests for the supervised store API — stores accessed through their
  # named processes rather than with explicit root directories.
  #
  # The supervised API:
  #   Liminara.Artifact.Store.put(content) -> {:ok, hash}
  #   Liminara.Artifact.Store.get(hash) -> {:ok, binary} | {:error, :not_found}
  #   Liminara.Artifact.Store.exists?(hash) -> boolean
  #
  #   Liminara.Event.Store.append(run_id, event_type, payload, prev_hash) -> {:ok, event}
  #   Liminara.Event.Store.read_all(run_id) -> {:ok, [event]}
  #   Liminara.Event.Store.verify(run_id) -> {:ok, count} | {:error, ...}
  #   Liminara.Event.Store.write_seal(run_id) -> {:ok, seal}
  #
  #   Liminara.Decision.Store.put(run_id, record) -> {:ok, hash}
  #   Liminara.Decision.Store.get(run_id, node_id) -> {:ok, record} | {:error, :not_found}
  #   Liminara.Decision.Store.verify(run_id, node_id) -> {:ok, hash} | {:error, ...}
  #
  #   Liminara.Cache.lookup(op_module, input_hashes) -> {:hit, outputs} | :miss
  #   Liminara.Cache.store(op_module, input_hashes, output_hashes) -> :ok
  #   Liminara.Cache.clear() -> :ok

  describe "Artifact.Store supervised API" do
    test "put and get round-trip" do
      {:ok, hash} = Liminara.Artifact.Store.put("supervised content")
      assert hash =~ ~r/^sha256:[a-f0-9]{64}$/
      assert {:ok, "supervised content"} = Liminara.Artifact.Store.get(hash)
    end

    test "exists? works through supervised process" do
      {:ok, hash} = Liminara.Artifact.Store.put("exists test")
      assert Liminara.Artifact.Store.exists?(hash)
      refute Liminara.Artifact.Store.exists?("sha256:" <> String.duplicate("0", 64))
    end

    test "binary content round-trips" do
      binary = <<0, 1, 2, 255, 128, 64>>
      {:ok, hash} = Liminara.Artifact.Store.put(binary)
      assert {:ok, ^binary} = Liminara.Artifact.Store.get(hash)
    end

    test "idempotent writes" do
      {:ok, hash1} = Liminara.Artifact.Store.put("same content")
      {:ok, hash2} = Liminara.Artifact.Store.put("same content")
      assert hash1 == hash2
    end
  end

  describe "Event.Store supervised API" do
    test "append and read_all round-trip" do
      run_id = "supervised-event-test-#{:erlang.unique_integer([:positive])}"

      {:ok, event} =
        Liminara.Event.Store.append(run_id, "test_event", %{"key" => "value"}, nil)

      assert event.event_hash =~ ~r/^sha256:/
      assert event.event_type == "test_event"

      {:ok, events} = Liminara.Event.Store.read_all(run_id)
      assert length(events) == 1
      assert hd(events)["event_type"] == "test_event"
    end

    test "hash chain verification" do
      run_id = "supervised-verify-test-#{:erlang.unique_integer([:positive])}"

      {:ok, e1} = Liminara.Event.Store.append(run_id, "first", %{}, nil)
      {:ok, _e2} = Liminara.Event.Store.append(run_id, "second", %{}, e1.event_hash)

      assert {:ok, 2} = Liminara.Event.Store.verify(run_id)
    end

    test "write_seal after events" do
      run_id = "supervised-seal-test-#{:erlang.unique_integer([:positive])}"

      {:ok, e1} = Liminara.Event.Store.append(run_id, "only_event", %{}, nil)
      {:ok, seal} = Liminara.Event.Store.write_seal(run_id)

      assert seal["run_id"] == run_id
      assert seal["run_seal"] == e1.event_hash
      assert seal["event_count"] == 1
    end
  end

  describe "Decision.Store supervised API" do
    test "put and get round-trip" do
      run_id = "supervised-decision-test-#{:erlang.unique_integer([:positive])}"

      record = %{
        "node_id" => "test_node",
        "decision_type" => "test",
        "output" => %{"response" => "hello"}
      }

      {:ok, hash} = Liminara.Decision.Store.put(run_id, record)
      assert hash =~ ~r/^sha256:/

      {:ok, [retrieved]} = Liminara.Decision.Store.get(run_id, "test_node")
      assert retrieved["node_id"] == "test_node"
      assert retrieved["decision_hash"] == hash
    end

    test "verify decision integrity" do
      run_id = "supervised-decision-verify-#{:erlang.unique_integer([:positive])}"

      record = %{
        "node_id" => "verify_node",
        "decision_type" => "test",
        "output" => %{"response" => "world"}
      }

      {:ok, hash} = Liminara.Decision.Store.put(run_id, record)
      assert {:ok, [^hash]} = Liminara.Decision.Store.verify(run_id, "verify_node")
    end
  end

  describe "Cache supervised API" do
    test "lookup and store without explicit ETS table" do
      # Cache should use its own internal ETS table
      assert :miss = Liminara.Cache.lookup(Liminara.TestOps.Upcase, ["sha256:supervised_test"])

      :ok =
        Liminara.Cache.store(Liminara.TestOps.Upcase, ["sha256:supervised_test"], %{
          "r" => "sha256:out"
        })

      assert {:hit, %{"r" => "sha256:out"}} =
               Liminara.Cache.lookup(Liminara.TestOps.Upcase, ["sha256:supervised_test"])
    end

    test "clear without explicit ETS table" do
      :ok =
        Liminara.Cache.store(Liminara.TestOps.Upcase, ["sha256:clear_test"], %{
          "r" => "sha256:x"
        })

      :ok = Liminara.Cache.clear()
      assert :miss = Liminara.Cache.lookup(Liminara.TestOps.Upcase, ["sha256:clear_test"])
    end
  end
end
