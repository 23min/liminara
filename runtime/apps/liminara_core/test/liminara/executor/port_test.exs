defmodule Liminara.Executor.PortTest do
  use ExUnit.Case, async: true

  alias Liminara.Executor.Port, as: PortExecutor

  @python_root Path.expand("../../../../../python", __DIR__)
  @runner_path Path.join(@python_root, "src/liminara_op_runner.py")

  # ── Protocol encoding/decoding ─────────────────────────────────

  describe "protocol encoding" do
    test "encode_request produces valid framed JSON with correlation ID" do
      {id, frame} = PortExecutor.encode_request("echo", %{"message" => "hello"})

      assert is_binary(id)
      assert byte_size(id) > 0

      # Decode the frame: 4-byte length prefix + JSON
      <<len::unsigned-big-integer-size(32), json_data::binary>> = frame
      assert len == byte_size(json_data)

      decoded = Jason.decode!(json_data)
      assert decoded["id"] == id
      assert decoded["op"] == "echo"
      assert decoded["inputs"] == %{"message" => "hello"}
    end

    test "encode_request generates unique correlation IDs" do
      {id1, _} = PortExecutor.encode_request("echo", %{})
      {id2, _} = PortExecutor.encode_request("echo", %{})
      assert id1 != id2
    end
  end

  describe "protocol decoding" do
    test "decode_response parses success response" do
      json = Jason.encode!(%{"id" => "abc", "status" => "ok", "outputs" => %{"x" => 1}})
      frame = <<byte_size(json)::unsigned-big-integer-size(32)>> <> json

      assert {:ok, %{"id" => "abc", "status" => "ok", "outputs" => %{"x" => 1}}} =
               PortExecutor.decode_response(frame)
    end

    test "decode_response parses success with decisions" do
      json =
        Jason.encode!(%{
          "id" => "abc",
          "status" => "ok",
          "outputs" => %{"x" => 1},
          "decisions" => [%{"choice" => "a"}]
        })

      frame = <<byte_size(json)::unsigned-big-integer-size(32)>> <> json

      assert {:ok, decoded} = PortExecutor.decode_response(frame)
      assert decoded["decisions"] == [%{"choice" => "a"}]
    end

    test "decode_response parses error response" do
      json = Jason.encode!(%{"id" => "abc", "status" => "error", "error" => "boom"})
      frame = <<byte_size(json)::unsigned-big-integer-size(32)>> <> json

      assert {:ok, %{"id" => "abc", "status" => "error", "error" => "boom"}} =
               PortExecutor.decode_response(frame)
    end

    test "decode_response handles malformed JSON" do
      bad_data = "not json at all"
      frame = <<byte_size(bad_data)::unsigned-big-integer-size(32)>> <> bad_data

      assert {:error, :invalid_json} = PortExecutor.decode_response(frame)
    end
  end

  # ── End-to-end port execution ──────────────────────────────────

  describe "run/3 with echo op" do
    test "echo op returns inputs as outputs" do
      assert {:ok, outputs, duration_ms} =
               PortExecutor.run("echo", %{"message" => "hello"},
                 python_root: @python_root,
                 runner: @runner_path
               )

      assert outputs == %{"message" => "hello"}
      assert is_integer(duration_ms) and duration_ms >= 0
    end

    test "echo op with complex nested inputs" do
      inputs = %{
        "items" => [1, 2, 3],
        "nested" => %{"a" => true, "b" => nil},
        "text" => "hello world"
      }

      assert {:ok, outputs, _duration} =
               PortExecutor.run("echo", inputs,
                 python_root: @python_root,
                 runner: @runner_path
               )

      assert outputs == inputs
    end

    test "echo op with empty inputs" do
      assert {:ok, outputs, _duration} =
               PortExecutor.run("echo", %{},
                 python_root: @python_root,
                 runner: @runner_path
               )

      assert outputs == %{}
    end
  end

  describe "run/3 error handling" do
    test "unknown op returns error" do
      assert {:error, reason, _duration} =
               PortExecutor.run("nonexistent_op", %{},
                 python_root: @python_root,
                 runner: @runner_path
               )

      assert is_binary(reason)
      assert reason =~ "nonexistent_op" or reason =~ "ModuleNotFoundError"
    end

    test "timeout kills the python process" do
      # The sleep op doesn't exist yet — we'll create a test op that sleeps
      assert {:error, :timeout, _duration} =
               PortExecutor.run("test_sleep", %{},
                 python_root: @python_root,
                 runner: @runner_path,
                 timeout: 500
               )
    end

    test "python crash returns port_exit error" do
      assert {:error, {:port_exit, status}, _duration} =
               PortExecutor.run("test_crash", %{},
                 python_root: @python_root,
                 runner: @runner_path
               )

      assert is_integer(status) and status != 0
    end

    test "large payload round-trips correctly" do
      # ~100KB payload
      large_text = String.duplicate("x", 100_000)
      inputs = %{"data" => large_text}

      assert {:ok, outputs, _duration} =
               PortExecutor.run("echo", inputs,
                 python_root: @python_root,
                 runner: @runner_path,
                 timeout: 10_000
               )

      assert outputs["data"] == large_text
    end
  end

  describe "clean_env/0 whitelist" do
    test "VIRTUAL_ENV is excluded" do
      System.put_env("VIRTUAL_ENV", "/some/venv")
      env = PortExecutor.clean_env()
      assert {~c"VIRTUAL_ENV", false} in env
      System.delete_env("VIRTUAL_ENV")
    end

    test "CONDA_PREFIX is excluded" do
      System.put_env("CONDA_PREFIX", "/some/conda")
      env = PortExecutor.clean_env()
      assert {~c"CONDA_PREFIX", false} in env
      System.delete_env("CONDA_PREFIX")
    end

    test "PYTHONPATH is excluded" do
      System.put_env("PYTHONPATH", "/bad/path")
      env = PortExecutor.clean_env()
      assert {~c"PYTHONPATH", false} in env
      System.delete_env("PYTHONPATH")
    end

    test "PATH is preserved (not in unset list)" do
      env = PortExecutor.clean_env()
      unset_keys = for {k, false} <- env, do: k
      refute ~c"PATH" in unset_keys
    end

    test "HOME is preserved" do
      env = PortExecutor.clean_env()
      unset_keys = for {k, false} <- env, do: k
      refute ~c"HOME" in unset_keys
    end

    test "PYTHONDONTWRITEBYTECODE is always set" do
      env = PortExecutor.clean_env()
      assert {~c"PYTHONDONTWRITEBYTECODE", ~c"1"} in env
    end

    test "extra_env preserves declared vars" do
      System.put_env("MY_CUSTOM_VAR", "custom_value")
      env = PortExecutor.clean_env(["MY_CUSTOM_VAR"])
      unset_keys = for {k, false} <- env, do: k
      refute ~c"MY_CUSTOM_VAR" in unset_keys
      System.delete_env("MY_CUSTOM_VAR")
    end

    test "port ops still work with clean env" do
      assert {:ok, outputs, _duration} =
               PortExecutor.run("echo", %{"test" => "env_clean"},
                 python_root: @python_root,
                 runner: @runner_path
               )

      assert outputs["test"] == "env_clean"
    end
  end

  describe "child-process env verification" do
    test "host VIRTUAL_ENV does not leak to the child Python process" do
      System.put_env("VIRTUAL_ENV", "/fake/leaked/venv")

      assert {:ok, outputs, _duration} =
               PortExecutor.run("test_env_report", %{},
                 python_root: @python_root,
                 runner: @runner_path
               )

      child_env = Jason.decode!(outputs["env"])
      # uv run sets its own VIRTUAL_ENV to the project venv,
      # but the host's value (/fake/leaked/venv) must NOT leak through
      refute child_env["VIRTUAL_ENV"] == "/fake/leaked/venv"
      System.delete_env("VIRTUAL_ENV")
    end

    test "PATH is visible to the child Python process" do
      assert {:ok, outputs, _duration} =
               PortExecutor.run("test_env_report", %{},
                 python_root: @python_root,
                 runner: @runner_path
               )

      child_env = Jason.decode!(outputs["env"])
      assert Map.has_key?(child_env, "PATH")
    end

    test "extra_env vars are visible to the child Python process" do
      System.put_env("TEST_DECLARED_VAR", "declared_value")

      assert {:ok, outputs, _duration} =
               PortExecutor.run("test_env_report", %{},
                 python_root: @python_root,
                 runner: @runner_path,
                 extra_env: ["TEST_DECLARED_VAR"]
               )

      child_env = Jason.decode!(outputs["env"])
      assert child_env["TEST_DECLARED_VAR"] == "declared_value"
      System.delete_env("TEST_DECLARED_VAR")
    end
  end
end
