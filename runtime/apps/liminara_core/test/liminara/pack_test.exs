defmodule Liminara.PackTest do
  use ExUnit.Case

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_pack_test_#{:erlang.unique_integer([:positive])}"
      )

    store_root = Path.join(tmp, "artifacts")
    runs_root = Path.join(tmp, "runs")
    File.mkdir_p!(store_root)
    File.mkdir_p!(runs_root)

    on_exit(fn -> File.rm_rf!(tmp) end)

    %{store_root: store_root, runs_root: runs_root}
  end

  describe "Pack behaviour" do
    test "TestPack implements all callbacks" do
      assert Liminara.TestPack.id() == :test_pack
      assert Liminara.TestPack.version() == "0.1.0"
      assert is_list(Liminara.TestPack.ops())
      assert %Liminara.Plan{} = Liminara.TestPack.plan("hello")
    end
  end

  describe "Liminara.run/3" do
    test "runs a pack end-to-end", ctx do
      {:ok, result} =
        Liminara.run(Liminara.TestPack, "hello world",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert result.status == :success
      assert is_binary(result.run_id)
      assert Map.has_key?(result.outputs, "load")
      assert Map.has_key?(result.outputs, "transform")
      assert Map.has_key?(result.outputs, "save")
    end
  end

  describe "Liminara.replay/4" do
    test "replays a previous run", ctx do
      {:ok, discovery} =
        Liminara.run(Liminara.TestPack, "replay me",
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      {:ok, replay} =
        Liminara.replay(Liminara.TestPack, "replay me", discovery.run_id,
          store_root: ctx.store_root,
          runs_root: ctx.runs_root
        )

      assert replay.status == :success
      assert replay.run_id != discovery.run_id

      # Recordable op output matches
      assert replay.outputs["transform"]["result"] ==
               discovery.outputs["transform"]["result"]
    end
  end
end
