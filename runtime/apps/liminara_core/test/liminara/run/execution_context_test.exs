defmodule Liminara.Run.ExecutionContextTest do
  use ExUnit.Case

  alias Liminara.{Artifact, Event, Plan, Run}

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_execution_context_test_#{:erlang.unique_integer([:positive])}"
      )

    store_root = Path.join(tmp, "artifacts")
    runs_root = Path.join(tmp, "runs")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{store_root: store_root, runs_root: runs_root}
  end

  defp context_plan do
    Plan.new()
    |> Plan.add_node("ctx", Liminara.TestOps.WithRuntimeContext, %{
      "text" => {:literal, "hello"}
    })
  end

  defp port_context_plan do
    Plan.new()
    |> Plan.add_node("ctx", Liminara.TestPortOps.WithRuntimeContext, %{
      "text" => {:literal, "hello"}
    })
  end

  defp recordable_context_plan do
    Plan.new()
    |> Plan.add_node("ctx", Liminara.TestOps.RecordableWithRuntimeContextExecutionSpec, %{
      "text" => {:literal, "hello"}
    })
  end

  test "run persists execution context and injects it into eligible ops", ctx do
    {:ok, result} =
      Run.execute(context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    assert {:ok, execution_context} =
             Event.Store.read_execution_context(ctx.runs_root, result.run_id)

    assert execution_context.run_id == result.run_id
    assert execution_context.pack_id == "test_pack"
    assert execution_context.pack_version == "0.1.0"
    assert execution_context.replay_of_run_id == nil

    {:ok, run_id_content} = Artifact.Store.get(ctx.store_root, result.outputs["ctx"]["run_id"])

    {:ok, started_at_content} =
      Artifact.Store.get(ctx.store_root, result.outputs["ctx"]["started_at"])

    {:ok, text_content} = Artifact.Store.get(ctx.store_root, result.outputs["ctx"]["text"])

    assert run_id_content == result.run_id
    assert started_at_content == execution_context.started_at
    assert text_content == "hello"
  end

  test "replay reuses stored execution context while recording replay provenance", ctx do
    {:ok, discovery} =
      Run.execute(context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    {:ok, replay} =
      Run.execute(context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root,
        replay: discovery.run_id
      )

    assert {:ok, discovery_context} =
             Event.Store.read_execution_context(ctx.runs_root, discovery.run_id)

    assert {:ok, replay_context} =
             Event.Store.read_execution_context(ctx.runs_root, replay.run_id)

    assert replay_context.run_id == discovery_context.run_id
    assert replay_context.started_at == discovery_context.started_at
    assert replay_context.pack_id == discovery_context.pack_id
    assert replay_context.pack_version == discovery_context.pack_version
    assert replay_context.replay_of_run_id == discovery.run_id
  end

  test "python port ops receive execution context during run and replay", ctx do
    {:ok, discovery} =
      Run.execute(port_context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    {:ok, discovery_context} = Event.Store.read_execution_context(ctx.runs_root, discovery.run_id)

    {:ok, replay} =
      Run.execute(port_context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root,
        replay: discovery.run_id
      )

    {:ok, discovery_run_id} =
      Artifact.Store.get(ctx.store_root, discovery.outputs["ctx"]["run_id"])

    {:ok, discovery_started_at} =
      Artifact.Store.get(ctx.store_root, discovery.outputs["ctx"]["started_at"])

    {:ok, replay_run_id} = Artifact.Store.get(ctx.store_root, replay.outputs["ctx"]["run_id"])

    {:ok, replay_started_at} =
      Artifact.Store.get(ctx.store_root, replay.outputs["ctx"]["started_at"])

    {:ok, replay_of_run_id} =
      Artifact.Store.get(ctx.store_root, replay.outputs["ctx"]["replay_of_run_id"])

    assert discovery_run_id == discovery_context.run_id
    assert discovery_started_at == discovery_context.started_at
    assert replay_run_id == discovery_context.run_id
    assert replay_started_at == discovery_context.started_at
    assert replay_of_run_id == discovery.run_id
  end

  test "runtime injects execution context only when the spec declares it", ctx do
    plan =
      Plan.new()
      |> Plan.add_node("ctx", Liminara.TestOps.WithOptionalContextHandler, %{
        "text" => {:literal, "hello"}
      })

    {:ok, result} =
      Run.execute(plan,
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    {:ok, mode_content} = Artifact.Store.get(ctx.store_root, result.outputs["ctx"]["mode"])
    {:ok, text_content} = Artifact.Store.get(ctx.store_root, result.outputs["ctx"]["text"])

    assert mode_content == "execute_1"
    assert text_content == "hello"
  end

  test "execution context reader ignores unknown persisted keys", ctx do
    run_id = "context-schema-#{:erlang.unique_integer([:positive])}"
    run_dir = Path.join(ctx.runs_root, run_id)
    File.mkdir_p!(run_dir)

    File.write!(
      Path.join(run_dir, "execution_context.json"),
      Jason.encode!(%{
        "run_id" => run_id,
        "started_at" => "2026-04-04T12:00:00Z",
        "pack_id" => "test_pack",
        "pack_version" => "0.1.0",
        "replay_of_run_id" => nil,
        "future_field" => "ignore me"
      })
    )

    assert {:ok, execution_context} = Event.Store.read_execution_context(ctx.runs_root, run_id)
    assert execution_context.run_id == run_id
    assert execution_context.pack_id == "test_pack"
    assert execution_context.pack_version == "0.1.0"
  end

  test "replay fails explicitly when a context-aware source run is missing execution_context.json",
       ctx do
    {:ok, discovery} =
      Run.execute(context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    File.rm!(Path.join([ctx.runs_root, discovery.run_id, "execution_context.json"]))

    {:ok, replay} =
      Run.execute(context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root,
        replay: discovery.run_id
      )

    assert replay.status == :failed
    assert replay.failed_nodes == ["ctx"]

    {:ok, events} = Event.Store.read_all(ctx.runs_root, replay.run_id)
    run_started = Enum.find(events, &(&1["event_type"] == "run_started"))
    op_failed = Enum.find(events, &(&1["event_type"] == "op_failed"))

    assert run_started["payload"]["execution_context"] == nil
    assert op_failed["payload"]["error_type"] == "missing_replay_execution_context"
    refute File.exists?(Path.join([ctx.runs_root, replay.run_id, "execution_context.json"]))
  end

  test "replay_recorded context-aware ops still replay when the source execution context is missing",
       ctx do
    {:ok, discovery} =
      Run.execute(recordable_context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    File.rm!(Path.join([ctx.runs_root, discovery.run_id, "execution_context.json"]))

    {:ok, replay} =
      Run.execute(recordable_context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root,
        replay: discovery.run_id
      )

    assert replay.status == :success

    assert {:ok, replay_context} =
             Event.Store.read_execution_context(ctx.runs_root, replay.run_id)

    assert replay_context.run_id == replay.run_id
    assert replay_context.replay_of_run_id == discovery.run_id

    {:ok, replay_output_run_id} =
      Artifact.Store.get(ctx.store_root, replay.outputs["ctx"]["run_id"])

    assert replay_output_run_id == discovery.run_id

    {:ok, events} = Event.Store.read_all(ctx.runs_root, replay.run_id)
    run_started = Enum.find(events, &(&1["event_type"] == "run_started"))

    assert run_started["payload"]["execution_context"]["run_id"] == replay.run_id
  end

  test "replay_recorded context-aware ops fail explicitly when replay data is missing and the source context is missing",
       ctx do
    {:ok, discovery} =
      Run.execute(recordable_context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    File.rm!(Path.join([ctx.runs_root, discovery.run_id, "execution_context.json"]))
    File.rm!(Path.join([ctx.runs_root, discovery.run_id, "decisions", "ctx.json"]))

    {:ok, replay} =
      Run.execute(recordable_context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root,
        replay: discovery.run_id
      )

    assert replay.status == :failed
    assert replay.failed_nodes == ["ctx"]

    {:ok, events} = Event.Store.read_all(ctx.runs_root, replay.run_id)
    run_started = Enum.find(events, &(&1["event_type"] == "run_started"))
    op_failed = Enum.find(events, &(&1["event_type"] == "op_failed"))

    assert run_started["payload"]["execution_context"] == nil
    assert op_failed["payload"]["error_type"] == "missing_replay_execution_context"
    refute File.exists?(Path.join([ctx.runs_root, replay.run_id, "execution_context.json"]))
  end

  test "replay_recorded context-aware ops fail explicitly when replay data is missing even if the source context exists",
       ctx do
    {:ok, discovery} =
      Run.execute(recordable_context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    File.rm!(Path.join([ctx.runs_root, discovery.run_id, "decisions", "ctx.json"]))

    {:ok, replay} =
      Run.execute(recordable_context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root,
        replay: discovery.run_id
      )

    assert replay.status == :failed
    assert replay.failed_nodes == ["ctx"]

    {:ok, events} = Event.Store.read_all(ctx.runs_root, replay.run_id)
    op_failed = Enum.find(events, &(&1["event_type"] == "op_failed"))

    assert op_failed["payload"]["error_type"] == "missing_replay_recording"
  end

  test "replay fails explicitly when a context-aware source run has invalid execution_context.json",
       ctx do
    {:ok, discovery} =
      Run.execute(context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    File.write!(
      Path.join([ctx.runs_root, discovery.run_id, "execution_context.json"]),
      "{bad json"
    )

    {:ok, replay} =
      Run.execute(context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root,
        replay: discovery.run_id
      )

    assert replay.status == :failed
    assert replay.failed_nodes == ["ctx"]

    {:ok, events} = Event.Store.read_all(ctx.runs_root, replay.run_id)
    run_started = Enum.find(events, &(&1["event_type"] == "run_started"))
    op_failed = Enum.find(events, &(&1["event_type"] == "op_failed"))

    assert run_started["payload"]["execution_context"] == nil
    assert op_failed["payload"]["error_type"] == "invalid_replay_execution_context"
    refute File.exists?(Path.join([ctx.runs_root, replay.run_id, "execution_context.json"]))
  end

  test "replay fails explicitly when a context-aware source run has non-object execution_context.json",
       ctx do
    {:ok, discovery} =
      Run.execute(context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    File.write!(Path.join([ctx.runs_root, discovery.run_id, "execution_context.json"]), "123")

    {:ok, replay} =
      Run.execute(context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root,
        replay: discovery.run_id
      )

    assert replay.status == :failed
    assert replay.failed_nodes == ["ctx"]

    {:ok, events} = Event.Store.read_all(ctx.runs_root, replay.run_id)
    run_started = Enum.find(events, &(&1["event_type"] == "run_started"))
    op_failed = Enum.find(events, &(&1["event_type"] == "op_failed"))

    assert run_started["payload"]["execution_context"] == nil
    assert op_failed["payload"]["error_type"] == "invalid_replay_execution_context"
    refute File.exists?(Path.join([ctx.runs_root, replay.run_id, "execution_context.json"]))
  end

  test "replay fails explicitly when a context-aware source run has malformed optional execution_context fields",
       ctx do
    {:ok, discovery} =
      Run.execute(context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    File.write!(
      Path.join([ctx.runs_root, discovery.run_id, "execution_context.json"]),
      Jason.encode!(%{
        "run_id" => discovery.run_id,
        "started_at" => "2026-04-04T12:00:00Z",
        "pack_id" => "test_pack",
        "pack_version" => "0.1.0",
        "replay_of_run_id" => 123,
        "topic_id" => nil
      })
    )

    {:ok, replay} =
      Run.execute(context_plan(),
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root,
        replay: discovery.run_id
      )

    assert replay.status == :failed
    assert replay.failed_nodes == ["ctx"]

    {:ok, events} = Event.Store.read_all(ctx.runs_root, replay.run_id)
    run_started = Enum.find(events, &(&1["event_type"] == "run_started"))
    op_failed = Enum.find(events, &(&1["event_type"] == "op_failed"))

    assert run_started["payload"]["execution_context"] == nil
    assert op_failed["payload"]["error_type"] == "invalid_replay_execution_context"
    refute File.exists?(Path.join([ctx.runs_root, replay.run_id, "execution_context.json"]))
  end

  test "replay without context-aware ops still records replay-owned execution context", ctx do
    plan =
      Plan.new()
      |> Plan.add_node("plain", Liminara.TestOps.Upcase, %{
        "text" => {:literal, "hello"}
      })

    {:ok, discovery} =
      Run.execute(plan,
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root
      )

    File.rm!(Path.join([ctx.runs_root, discovery.run_id, "execution_context.json"]))

    {:ok, replay} =
      Run.execute(plan,
        pack_id: "test_pack",
        pack_version: "0.1.0",
        store_root: ctx.store_root,
        runs_root: ctx.runs_root,
        replay: discovery.run_id
      )

    assert replay.status == :success

    assert {:ok, replay_context} =
             Event.Store.read_execution_context(ctx.runs_root, replay.run_id)

    assert replay_context.run_id == replay.run_id
    assert replay_context.replay_of_run_id == discovery.run_id

    {:ok, events} = Event.Store.read_all(ctx.runs_root, replay.run_id)
    run_started = Enum.find(events, &(&1["event_type"] == "run_started"))

    assert run_started["payload"]["execution_context"]["run_id"] == replay.run_id
  end
end
