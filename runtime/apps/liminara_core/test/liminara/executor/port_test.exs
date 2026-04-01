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
end
