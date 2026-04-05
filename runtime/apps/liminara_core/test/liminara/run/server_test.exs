defmodule Liminara.Run.ServerTest do
  use ExUnit.Case

  alias Liminara.{Artifact, Event, Plan, Run}

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_run_test_#{:erlang.unique_integer([:positive])}"
      )

    store_root = Path.join(tmp, "artifacts")
    runs_root = Path.join(tmp, "runs")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{store_root: store_root, runs_root: runs_root}
  end

  describe "linear plan" do
    test "3-node linear plan runs to completion", ctx do
      # Plan: upcase → reverse → identity
      # Input: "hello" → "HELLO" → "OLLEH" → "OLLEH"
      plan =
        Plan.new()
        |> Plan.add_node("upcase", Liminara.TestOps.Upcase, %{
          "text" => {:literal, "hello"}
        })
        |> Plan.add_node("reverse", Liminara.TestOps.Reverse, %{
          "text" => {:ref, "upcase", "result"}
        })
        |> Plan.add_node("identity", Liminara.TestOps.Identity, %{
          "result" => {:ref, "reverse", "result"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :success
      assert is_binary(result.run_id)

      # Verify final output is accessible
      assert Map.has_key?(result.outputs, "identity")
      identity_outputs = result.outputs["identity"]
      {:ok, content} = Artifact.Store.get(ctx.store_root, identity_outputs["result"])
      assert content == "OLLEH"
    end

    test "all events emitted in correct order", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hi"}})
        |> Plan.add_node("b", Liminara.TestOps.Reverse, %{
          "text" => {:ref, "a", "result"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      {:ok, events} = Event.Store.read_all(ctx.runs_root, result.run_id)

      event_types = Enum.map(events, & &1["event_type"])

      assert event_types == [
               "run_started",
               "op_started",
               "op_completed",
               "op_started",
               "op_completed",
               "run_completed"
             ]
    end

    test "hash chain is valid after run", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "test"}})

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert {:ok, _count} = Event.Store.verify(ctx.runs_root, result.run_id)
    end

    test "seal is written and matches final event", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "seal"}})

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      seal_path = Path.join([ctx.runs_root, result.run_id, "seal.json"])
      assert File.exists?(seal_path)

      seal = seal_path |> File.read!() |> Jason.decode!()
      {:ok, events} = Event.Store.read_all(ctx.runs_root, result.run_id)
      final_event = List.last(events)

      assert seal["run_seal"] == final_event["event_hash"]
      assert seal["event_count"] == length(events)
    end

    test "output artifacts are stored and retrievable", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "stored"}})

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      output_hash = result.outputs["a"]["result"]
      assert output_hash =~ ~r/^sha256:/
      {:ok, content} = Artifact.Store.get(ctx.store_root, output_hash)
      assert content == "STORED"
    end

    test "task-backed canonical execution specs run successfully in synchronous mode", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("task", Liminara.TestOps.WithTaskExecutionSpec, %{
          "text" => {:literal, "hello"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :success
      {:ok, content} = Artifact.Store.get(ctx.store_root, result.outputs["task"]["result"])
      assert content == "HELLO"
    end

    test "gate ops fail explicitly instead of crashing the synchronous runner", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("gate", Liminara.DemoOps.Approve, %{
          "text" => {:literal, "approve me"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :failed
      assert result.failed_nodes == ["gate"]

      {:ok, events} = Event.Store.read_all(ctx.runs_root, result.run_id)

      assert ["run_started", "op_started", "gate_requested", "op_failed", "run_failed"] ==
               Enum.map(events, & &1["event_type"])

      gate_requested = Enum.find(events, &(&1["event_type"] == "gate_requested"))
      op_failed = Enum.find(events, &(&1["event_type"] == "op_failed"))

      assert gate_requested["payload"]["prompt"] == "Please approve: approve me"
      assert op_failed["payload"]["error_type"] == "gate_requires_run_server"
    end
  end

  describe "fan-out" do
    test "A → B, A → C both complete", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "fan"}})
        |> Plan.add_node("b", Liminara.TestOps.Reverse, %{
          "text" => {:ref, "a", "result"}
        })
        |> Plan.add_node("c", Liminara.TestOps.Identity, %{
          "result" => {:ref, "a", "result"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :success
      assert Map.has_key?(result.outputs, "b")
      assert Map.has_key?(result.outputs, "c")

      {:ok, b_content} = Artifact.Store.get(ctx.store_root, result.outputs["b"]["result"])
      {:ok, c_content} = Artifact.Store.get(ctx.store_root, result.outputs["c"]["result"])
      assert b_content == "NAF"
      assert c_content == "FAN"
    end
  end

  describe "fan-in" do
    test "A → C, B → C runs correctly", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
        |> Plan.add_node("b", Liminara.TestOps.Upcase, %{"text" => {:literal, "world"}})
        |> Plan.add_node("c", Liminara.TestOps.Concat, %{
          "a" => {:ref, "a", "result"},
          "b" => {:ref, "b", "result"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :success
      {:ok, c_content} = Artifact.Store.get(ctx.store_root, result.outputs["c"]["result"])
      assert c_content == "HELLOWORLD"
    end
  end

  describe "failure handling" do
    test "failing op emits op_failed and run_failed", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "ok"}})
        |> Plan.add_node("b", Liminara.TestOps.Fail, %{
          "data" => {:ref, "a", "result"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :failed

      {:ok, events} = Event.Store.read_all(ctx.runs_root, result.run_id)
      event_types = Enum.map(events, & &1["event_type"])

      assert "op_failed" in event_types
      assert "run_failed" in event_types
      refute "run_completed" in event_types
    end

    test "completed ops before failure still have artifacts", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "saved"}})
        |> Plan.add_node("b", Liminara.TestOps.Fail, %{
          "data" => {:ref, "a", "result"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :failed
      # Node "a" completed before "b" failed — its artifacts should exist
      assert Map.has_key?(result.outputs, "a")
      {:ok, content} = Artifact.Store.get(ctx.store_root, result.outputs["a"]["result"])
      assert content == "SAVED"
    end
  end

  describe "recordable ops" do
    test "recordable op stores a decision and emits event", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("gen", Liminara.TestOps.Recordable, %{
          "prompt" => {:literal, "summarize this"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :success

      {:ok, events} = Event.Store.read_all(ctx.runs_root, result.run_id)
      event_types = Enum.map(events, & &1["event_type"])
      assert "decision_recorded" in event_types

      # Decision file should exist
      {:ok, [decision | _]} =
        Liminara.Decision.Store.get(ctx.runs_root, result.run_id, "gen")

      assert decision["decision_type"] == "llm_response"
      assert is_binary(decision["decision_hash"])
    end
  end

  describe "event integrity" do
    test "event log has valid hash chain", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "chain"}})
        |> Plan.add_node("b", Liminara.TestOps.Reverse, %{
          "text" => {:ref, "a", "result"}
        })

      {:ok, result} =
        Run.execute(plan,
          pack_id: "test_pack",
          pack_version: "0.1.0",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert {:ok, event_count} = Event.Store.verify(ctx.runs_root, result.run_id)
      assert event_count > 0
    end
  end
end
