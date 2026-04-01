defmodule Liminara.Run.PortIntegrationTest do
  use ExUnit.Case

  alias Liminara.{Artifact, Event, Plan, Run}

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_port_int_test_#{:erlang.unique_integer([:positive])}"
      )

    store_root = Path.join(tmp, "artifacts")
    runs_root = Path.join(tmp, "runs")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    cache = :ets.new(:port_int_test_cache, [:set, :public])

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{store_root: store_root, runs_root: runs_root, cache: cache}
  end

  defp run_opts(ctx) do
    [
      pack_id: "port_test",
      pack_version: "0.1.0",
      store_root: ctx.store_root,
      runs_root: ctx.runs_root,
      cache: ctx.cache
    ]
  end

  describe "pure Python op via Run.Server" do
    test "executes and stores artifacts", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("reverse", Liminara.TestPortOps.PureReverse, %{
          "text" => {:literal, "hello"}
        })

      {:ok, result} = Run.execute(plan, run_opts(ctx))

      assert result.status == :success
      assert Map.has_key?(result.outputs, "reverse")

      {:ok, content} = Artifact.Store.get(ctx.store_root, result.outputs["reverse"]["result"])
      assert content == "olleh"
    end

    test "cached on second run with same inputs", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("reverse", Liminara.TestPortOps.PureReverse, %{
          "text" => {:literal, "cache_test"}
        })

      opts = run_opts(ctx)

      # First run — executes Python
      {:ok, result1} = Run.execute(plan, opts)
      assert result1.status == :success

      # Second run — should hit cache (no Python spawn)
      {:ok, result2} = Run.execute(plan, opts)
      assert result2.status == :success

      # Outputs should be identical (same artifact hashes)
      assert result1.outputs["reverse"] == result2.outputs["reverse"]

      # Verify second run used cache by checking events
      {:ok, events2} = Event.Store.read_all(ctx.runs_root, result2.run_id)
      op_completed = Enum.find(events2, &(&1["event_type"] == "op_completed"))
      assert op_completed["payload"]["cache_hit"] == true
    end
  end

  describe "recordable Python op via Run.Server" do
    test "executes, stores decisions, and produces output", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("llm", Liminara.TestPortOps.Recordable, %{
          "prompt" => {:literal, "test prompt"}
        })

      {:ok, result} = Run.execute(plan, run_opts(ctx))

      assert result.status == :success

      {:ok, content} = Artifact.Store.get(ctx.store_root, result.outputs["llm"]["result"])
      assert content =~ "Generated response for: test prompt"

      # Verify decision was recorded
      {:ok, events} = Event.Store.read_all(ctx.runs_root, result.run_id)
      assert Enum.any?(events, &(&1["event_type"] == "decision_recorded"))
    end

    test "replay uses stored decisions without spawning Python", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("llm", Liminara.TestPortOps.Recordable, %{
          "prompt" => {:literal, "replay test"}
        })

      opts = run_opts(ctx)

      # Discovery run
      {:ok, discovery} = Run.execute(plan, opts)
      assert discovery.status == :success

      # Replay run
      {:ok, replay} = Run.execute(plan, Keyword.put(opts, :replay, discovery.run_id))
      assert replay.status == :success

      # Outputs should match
      {:ok, disc_content} =
        Artifact.Store.get(ctx.store_root, discovery.outputs["llm"]["result"])

      {:ok, replay_content} =
        Artifact.Store.get(ctx.store_root, replay.outputs["llm"]["result"])

      assert disc_content == replay_content
    end
  end

  describe "side_effecting Python op via Run.Server" do
    test "executes on first run", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("effect", Liminara.TestPortOps.SideEffect, %{
          "data" => {:literal, "write_this"}
        })

      {:ok, result} = Run.execute(plan, run_opts(ctx))

      assert result.status == :success
      {:ok, content} = Artifact.Store.get(ctx.store_root, result.outputs["effect"]["result"])
      assert content == "side_effect_done:write_this"
    end

    test "skipped on replay", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("effect", Liminara.TestPortOps.SideEffect, %{
          "data" => {:literal, "skip_me"}
        })

      opts = run_opts(ctx)

      # Discovery run
      {:ok, discovery} = Run.execute(plan, opts)
      assert discovery.status == :success

      # Replay — side_effecting should be skipped
      {:ok, replay} = Run.execute(plan, Keyword.put(opts, :replay, discovery.run_id))
      assert replay.status == :success

      # Verify it was skipped in replay
      {:ok, replay_events} = Event.Store.read_all(ctx.runs_root, replay.run_id)

      op_completed =
        Enum.find(replay_events, fn e ->
          e["event_type"] == "op_completed" and e["payload"]["node_id"] == "effect"
        end)

      # Side-effecting ops are marked as cache_hit (skipped) during replay
      assert op_completed["payload"]["cache_hit"] == true
    end
  end

  describe "mixed Elixir + Python plan" do
    test "data flows correctly between Elixir and Python ops", ctx do
      # Elixir upcase → Python reverse → Elixir identity
      plan =
        Plan.new()
        |> Plan.add_node("upcase", Liminara.TestOps.Upcase, %{
          "text" => {:literal, "hello"}
        })
        |> Plan.add_node("py_reverse", Liminara.TestPortOps.PureReverse, %{
          "text" => {:ref, "upcase", "result"}
        })
        |> Plan.add_node("identity", Liminara.TestOps.Identity, %{
          "result" => {:ref, "py_reverse", "result"}
        })

      {:ok, result} = Run.execute(plan, run_opts(ctx))

      assert result.status == :success

      # "hello" → upcase → "HELLO" → py_reverse → "OLLEH" → identity → "OLLEH"
      {:ok, content} = Artifact.Store.get(ctx.store_root, result.outputs["identity"]["result"])
      assert content == "OLLEH"
    end

    test "all events logged in correct order", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("upcase", Liminara.TestOps.Upcase, %{
          "text" => {:literal, "events"}
        })
        |> Plan.add_node("py_reverse", Liminara.TestPortOps.PureReverse, %{
          "text" => {:ref, "upcase", "result"}
        })

      {:ok, result} = Run.execute(plan, run_opts(ctx))

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
  end

  describe "Python op failure" do
    test "error results in failed node and run status", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("fail", Liminara.TestPortOps.Fail, %{
          "data" => {:literal, "boom"}
        })

      {:ok, result} = Run.execute(plan, run_opts(ctx))

      assert result.status in [:failed, :partial]
    end

    test "downstream nodes not dispatched after failure", ctx do
      plan =
        Plan.new()
        |> Plan.add_node("fail", Liminara.TestPortOps.Fail, %{
          "data" => {:literal, "boom"}
        })
        |> Plan.add_node("after_fail", Liminara.TestPortOps.PureEcho, %{
          "input" => {:ref, "fail", "result"}
        })

      {:ok, result} = Run.execute(plan, run_opts(ctx))

      assert result.status in [:failed, :partial]
      refute Map.has_key?(result.outputs, "after_fail")
    end
  end
end
