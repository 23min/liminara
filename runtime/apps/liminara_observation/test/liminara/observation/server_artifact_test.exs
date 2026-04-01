defmodule Liminara.Observation.ServerArtifactTest do
  @moduledoc """
  Tests for Observation.Server.get_artifact_content/2 — the artifact API
  that delegates to the Artifact Store. All observation goes through one door.
  """
  use ExUnit.Case, async: false

  alias Liminara.Observation.Server
  alias Liminara.{Artifact, Plan}

  # ── Helpers ────────────────────────────────────────────────────────────

  defp simple_plan do
    Plan.new()
    |> Plan.add_node("a", Liminara.TestOps.Upcase, %{"text" => {:literal, "hello"}})
  end

  defp unique_run_id do
    "obs-artifact-#{:erlang.unique_integer([:positive])}"
  end

  # ── get_artifact_content/2 ─────────────────────────────────────────────

  describe "Observation.Server.get_artifact_content/2" do
    test "returns {:ok, content} for a hash that exists in the artifact store" do
      run_id = unique_run_id()
      plan = simple_plan()

      # Write a known artifact directly into the supervised Artifact.Store
      content = "hello world artifact content"
      {:ok, hash} = Artifact.Store.put(content)

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      result = Server.get_artifact_content(pid, run_id, hash)

      assert {:ok, ^content} = result

      GenServer.stop(pid)
    end

    test "returns {:error, :not_found} for an unknown hash" do
      run_id = unique_run_id()
      plan = simple_plan()

      unknown_hash = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      result = Server.get_artifact_content(pid, run_id, unknown_hash)

      assert result == {:error, :not_found}

      GenServer.stop(pid)
    end

    test "returns content for binary artifact (non-text bytes)" do
      run_id = unique_run_id()
      plan = simple_plan()

      # Store arbitrary binary content (simulate a PDF or image)
      binary_content = <<0, 1, 2, 3, 255, 254, 253>>
      {:ok, hash} = Artifact.Store.put(binary_content)

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      result = Server.get_artifact_content(pid, run_id, hash)

      assert {:ok, ^binary_content} = result

      GenServer.stop(pid)
    end

    test "returns content for JSON artifact" do
      run_id = unique_run_id()
      plan = simple_plan()

      json_content = ~s({"key":"value","number":42})
      {:ok, hash} = Artifact.Store.put(json_content)

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      result = Server.get_artifact_content(pid, run_id, hash)

      assert {:ok, ^json_content} = result

      GenServer.stop(pid)
    end

    test "different run_ids can retrieve the same artifact (content-addressed)" do
      run_id_1 = unique_run_id()
      run_id_2 = unique_run_id()
      plan = simple_plan()

      content = "shared artifact content"
      {:ok, hash} = Artifact.Store.put(content)

      {:ok, pid1} = Server.start_link(run_id: run_id_1, plan: plan)
      {:ok, pid2} = Server.start_link(run_id: run_id_2, plan: plan)

      assert {:ok, ^content} = Server.get_artifact_content(pid1, run_id_1, hash)
      assert {:ok, ^content} = Server.get_artifact_content(pid2, run_id_2, hash)

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end

    test "returns {:error, :not_found} for empty string hash" do
      run_id = unique_run_id()
      plan = simple_plan()

      {:ok, pid} = Server.start_link(run_id: run_id, plan: plan)

      result = Server.get_artifact_content(pid, run_id, "")

      assert result == {:error, :not_found}

      GenServer.stop(pid)
    end

    test "get_artifact_content/2 (arity-2 module-level API) returns content for known hash" do
      run_id = unique_run_id()

      content = "module level api test content"
      {:ok, hash} = Artifact.Store.put(content)

      result = Server.get_artifact_content(run_id, hash)

      assert {:ok, ^content} = result
    end

    test "get_artifact_content/2 (arity-2 module-level API) returns error for unknown hash" do
      run_id = unique_run_id()
      unknown_hash = "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

      result = Server.get_artifact_content(run_id, unknown_hash)

      assert result == {:error, :not_found}
    end
  end
end
