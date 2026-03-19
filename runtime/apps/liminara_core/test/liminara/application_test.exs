defmodule Liminara.ApplicationTest do
  use ExUnit.Case, async: false

  # These tests verify the OTP application and supervision tree
  # that M-OTP-01 introduces. They test:
  # - Application startup and shutdown
  # - Supervision tree structure
  # - ETS table ownership
  # - Store configuration

  describe "application startup" do
    test "application starts without error" do
      # The app should already be started by test_helper.exs / mix test
      assert {:ok, _} = Application.ensure_all_started(:liminara_core)
    end

    test "all expected children are alive after startup" do
      children =
        Liminara.Supervisor
        |> Supervisor.which_children()
        |> Enum.map(fn {id, _pid, _type, _modules} -> id end)

      assert Liminara.Artifact.Store in children
      assert Liminara.Event.Store in children
      assert Liminara.Decision.Store in children
      assert Liminara.Cache in children
      assert Liminara.Run.Registry in children
      assert Liminara.Run.DynamicSupervisor in children
    end

    test "all children are running (not :undefined or :restarting)" do
      children = Supervisor.which_children(Liminara.Supervisor)

      for {id, pid, _type, _modules} <- children do
        assert is_pid(pid), "#{id} should be a running process, got #{inspect(pid)}"
        assert Process.alive?(pid), "#{id} process should be alive"
      end
    end
  end

  describe "supervision tree structure" do
    test "Artifact.Store is a child of the top-level supervisor" do
      children = Supervisor.which_children(Liminara.Supervisor)
      assert Enum.any?(children, fn {id, _, _, _} -> id == Liminara.Artifact.Store end)
    end

    test "Cache ETS table exists after application start" do
      # The Cache process should own an ETS table
      assert :ets.info(Liminara.Cache) != :undefined,
             "Cache ETS table should exist"
    end

    test "Run.Registry is a Registry process" do
      # Registry should be findable and respond to lookups
      assert Registry.lookup(Liminara.Run.Registry, "nonexistent_run") == []
    end

    test "Run.DynamicSupervisor is a DynamicSupervisor with no children initially" do
      children = DynamicSupervisor.which_children(Liminara.Run.DynamicSupervisor)
      assert children == []
    end
  end

  describe "ETS table ownership" do
    test "Cache ETS table survives the death of a caller process" do
      # Spawn a process that uses the cache, then let it die
      task =
        Task.async(fn ->
          Liminara.Cache.store(Liminara.TestOps.Upcase, ["sha256:ownership_test"], %{
            "r" => "sha256:result"
          })
        end)

      Task.await(task)
      # The task process is now dead, but the ETS table should still exist
      assert :ets.info(Liminara.Cache) != :undefined
      # And the data should still be there
      assert {:hit, _} =
               Liminara.Cache.lookup(Liminara.TestOps.Upcase, ["sha256:ownership_test"])
    end

    test "Artifact.Store ETS metadata table survives caller death" do
      # The Artifact.Store process owns its state; callers don't affect it
      task =
        Task.async(fn ->
          Liminara.Artifact.Store.put("test content for ownership")
        end)

      {:ok, hash} = Task.await(task)
      # Caller is dead, but artifact is still retrievable
      assert {:ok, "test content for ownership"} = Liminara.Artifact.Store.get(hash)
    end
  end

  describe "store configuration" do
    test "stores use a configured root directory" do
      # After application start, stores should be using a configured directory
      # We verify by storing and retrieving — the data persists in the configured location
      {:ok, hash} = Liminara.Artifact.Store.put("config test content")
      assert {:ok, "config test content"} = Liminara.Artifact.Store.get(hash)
    end
  end
end
