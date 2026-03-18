defmodule Liminara.IntegrationTest do
  use ExUnit.Case

  alias Liminara.Event

  @fixtures_dir Path.expand("../../../../../test_fixtures/golden_run", __DIR__)

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_integration_test_#{:erlang.unique_integer([:positive])}"
      )

    store_root = Path.join(tmp, "artifacts")
    runs_root = Path.join(tmp, "runs")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{store_root: store_root, runs_root: runs_root}
  end

  describe "full discovery → replay cycle" do
    test "discovery then replay produces matching output", ctx do
      {:ok, discovery} =
        Liminara.run(Liminara.TestPack, "integration test",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert discovery.status == :success

      {:ok, replay} =
        Liminara.replay(Liminara.TestPack, "integration test", discovery.run_id,
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert replay.status == :success

      # Pure op output identical
      assert discovery.outputs["load"] == replay.outputs["load"]

      # Recordable op output identical (decision injected)
      assert discovery.outputs["transform"] == replay.outputs["transform"]

      # Both have valid hash chains
      assert {:ok, _} = Event.Store.verify(ctx.runs_root, discovery.run_id)
      assert {:ok, _} = Event.Store.verify(ctx.runs_root, replay.run_id)
    end
  end

  describe "cache behavior" do
    test "second fresh run: pure ops cache-hit", ctx do
      cache = :ets.new(:integration_cache, [:set, :public])

      {:ok, _run1} =
        Liminara.run(Liminara.TestPack, "cache test",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: cache
        )

      {:ok, run2} =
        Liminara.run(Liminara.TestPack, "cache test",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root,
          cache: cache
        )

      {:ok, events} = Event.Store.read_all(ctx.runs_root, run2.run_id)

      load_completed =
        Enum.find(events, fn e ->
          e["event_type"] == "op_completed" and e["payload"]["node_id"] == "load"
        end)

      # Pure op should be cache hit on second run
      assert load_completed["payload"]["cache_hit"] == true

      # Recordable op should NOT be cached
      transform_completed =
        Enum.find(events, fn e ->
          e["event_type"] == "op_completed" and e["payload"]["node_id"] == "transform"
        end)

      assert transform_completed["payload"]["cache_hit"] == false
    end
  end

  describe "golden fixture interop" do
    test "Elixir storage layer reads golden events" do
      events =
        @fixtures_dir
        |> Path.join("events.jsonl")
        |> File.read!()
        |> String.trim()
        |> String.split("\n")
        |> Enum.map(&Jason.decode!/1)

      assert length(events) == 7
      assert hd(events)["event_type"] == "run_started"
      assert List.last(events)["event_type"] == "run_completed"
    end

    test "golden event hash chain validates", ctx do
      run_id = "golden_interop"
      run_dir = Path.join(ctx.runs_root, run_id)
      File.mkdir_p!(run_dir)
      File.cp!(Path.join(@fixtures_dir, "events.jsonl"), Path.join(run_dir, "events.jsonl"))

      assert {:ok, 7} = Event.Store.verify(ctx.runs_root, run_id)
    end

    test "golden artifacts are retrievable" do
      hash = "sha256:fbebbef195fa31dd9ee877e294bec860f9bfba77abc08f9244c21d5930552521"
      hex = String.replace_prefix(hash, "sha256:", "")

      path =
        Path.join([
          @fixtures_dir,
          "artifacts",
          String.slice(hex, 0, 2),
          String.slice(hex, 2, 2),
          hex
        ])

      content = File.read!(path)
      assert Liminara.Hash.hash_bytes(content) == hash
    end

    test "Elixir-written event log is canonical JSON", ctx do
      {:ok, result} =
        Liminara.run(Liminara.TestPack, "canonical test",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      events_path = Path.join([ctx.runs_root, result.run_id, "events.jsonl"])
      lines = events_path |> File.read!() |> String.trim() |> String.split("\n")

      for line <- lines do
        decoded = Jason.decode!(line)
        # Re-encoding with canonical should produce the same bytes
        re_encoded = Liminara.Canonical.encode(decoded)
        assert line == re_encoded, "Event is not canonical JSON"
      end
    end
  end
end
