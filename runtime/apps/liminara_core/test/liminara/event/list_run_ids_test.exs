defmodule Liminara.Event.ListRunIdsTest do
  use ExUnit.Case, async: true

  alias Liminara.Event.Store

  setup do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "liminara_list_run_ids_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    %{runs_root: tmp}
  end

  describe "list_run_ids/1 (direct API)" do
    test "empty directory returns empty list", %{runs_root: root} do
      assert Store.list_run_ids(root) == []
    end

    test "single run directory returns one-element list", %{runs_root: root} do
      File.mkdir_p!(Path.join(root, "run-001"))
      assert Store.list_run_ids(root) == ["run-001"]
    end

    test "multiple run directories returns all sorted", %{runs_root: root} do
      for id <- ["run-003", "run-001", "run-002"] do
        File.mkdir_p!(Path.join(root, id))
      end

      assert Store.list_run_ids(root) == ["run-001", "run-002", "run-003"]
    end

    test "ignores regular files in the runs directory", %{runs_root: root} do
      File.mkdir_p!(Path.join(root, "run-001"))
      File.write!(Path.join(root, "some-file.txt"), "not a run")
      File.write!(Path.join(root, "seal.json"), "{}")

      assert Store.list_run_ids(root) == ["run-001"]
    end

    test "returns sorted list when directories were created out of order", %{runs_root: root} do
      for id <- ["zzz-run", "aaa-run", "mmm-run"] do
        File.mkdir_p!(Path.join(root, id))
      end

      result = Store.list_run_ids(root)
      assert result == Enum.sort(result)
      assert length(result) == 3
    end

    test "run directory with events file is still listed", %{runs_root: root} do
      run_dir = Path.join(root, "run-with-events")
      File.mkdir_p!(run_dir)
      File.write!(Path.join(run_dir, "events.jsonl"), "")

      assert Store.list_run_ids(root) == ["run-with-events"]
    end

    test "non-existent directory returns empty list" do
      assert Store.list_run_ids("/tmp/does_not_exist_#{:erlang.unique_integer([:positive])}") ==
               []
    end

    test "returns run IDs created via Event.Store.append/5", %{runs_root: root} do
      # Verify that real run directories (created by append) are discovered
      run_id = "test-run-#{:erlang.unique_integer([:positive])}"
      {:ok, _event} = Store.append(root, run_id, "run_started", %{"run_id" => run_id}, nil)

      assert run_id in Store.list_run_ids(root)
    end
  end
end
