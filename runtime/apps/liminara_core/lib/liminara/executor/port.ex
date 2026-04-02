defmodule Liminara.Executor.Port do
  @moduledoc """
  Port executor: spawns a Python process, exchanges {packet,4} length-framed
  JSON over stdio, and returns the result.

  Protocol:
    Request:  {"id": "...", "op": "module_name", "inputs": {...}}
    Success:  {"id": "...", "status": "ok", "outputs": {...}}
    Decisions: {"id": "...", "status": "ok", "outputs": {...}, "decisions": [...]}
    Error:    {"id": "...", "status": "error", "error": "message"}
  """

  @default_timeout 30_000

  @doc """
  Run a Python op by name.

  Options:
    - `:python_root` — path to the Python project root (contains src/)
    - `:runner` — path to liminara_op_runner.py
    - `:timeout` — max milliseconds to wait (default #{@default_timeout})

  Returns:
    - `{:ok, outputs, duration_ms}`
    - `{:ok, outputs, duration_ms, decisions}`
    - `{:error, reason, duration_ms}`
  """
  def run(op_name, inputs, opts \\ []) do
    python_root = Keyword.get(opts, :python_root, default_python_root())
    runner = Keyword.get(opts, :runner, default_runner(python_root))
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    {id, frame} = encode_request(op_name, inputs)

    {duration_us, result} =
      :timer.tc(fn ->
        execute_port(runner, python_root, frame, id, timeout)
      end)

    duration_ms = div(duration_us, 1000)

    case result do
      {:ok, %{"status" => "ok", "outputs" => outputs, "decisions" => decisions}} ->
        {:ok, outputs, duration_ms, decisions}

      {:ok, %{"status" => "ok", "outputs" => outputs}} ->
        {:ok, outputs, duration_ms}

      {:ok, %{"status" => "error", "error" => error}} ->
        {:error, error, duration_ms}

      {:error, reason} ->
        {:error, reason, duration_ms}
    end
  end

  @doc """
  Encode a request into a {packet,4} framed binary.
  Returns `{correlation_id, frame}`.
  """
  def encode_request(op_name, inputs) do
    id = generate_id()

    json =
      Jason.encode!(%{
        "id" => id,
        "op" => op_name,
        "inputs" => inputs
      })

    frame = <<byte_size(json)::unsigned-big-integer-size(32)>> <> json
    {id, frame}
  end

  @doc """
  Decode a {packet,4} framed response binary.
  Returns `{:ok, decoded_map}` or `{:error, :invalid_json}`.
  """
  def decode_response(frame) do
    <<_len::unsigned-big-integer-size(32), json_data::binary>> = frame

    case Jason.decode(json_data) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  # ── Private ──────────────────────────────────────────────────────

  defp execute_port(runner, python_root, frame, expected_id, timeout) do
    uv = System.find_executable("uv") || "uv"
    src_dir = Path.join(python_root, "src")

    port =
      Port.open(
        {:spawn_executable, uv},
        [
          :binary,
          {:packet, 4},
          :exit_status,
          {:args, ["run", "--project", python_root, "python", "-u", runner]},
          {:cd, src_dir},
          {:env,
           [
             {~c"PYTHONDONTWRITEBYTECODE", ~c"1"},
             {~c"VIRTUAL_ENV", false}
           ]}
        ]
      )

    # Send the request
    Port.command(port, frame_payload(frame))

    # Wait for response or timeout
    timer_ref = Process.send_after(self(), {:port_timeout, port}, timeout)

    result = receive_response(port, expected_id)

    Process.cancel_timer(timer_ref)
    # Flush any pending timeout message
    receive do
      {:port_timeout, ^port} -> :ok
    after
      0 -> :ok
    end

    cleanup_port(port)

    result
  end

  defp receive_response(port, expected_id) do
    receive do
      {^port, {:data, data}} ->
        case Jason.decode(data) do
          {:ok, %{"id" => ^expected_id} = response} ->
            {:ok, response}

          {:ok, _wrong_id} ->
            # Unexpected ID — keep waiting
            receive_response(port, expected_id)

          {:error, _} ->
            {:error, :invalid_json}
        end

      {^port, {:exit_status, status}} ->
        {:error, {:port_exit, status}}

      {:port_timeout, ^port} ->
        kill_port(port)
        {:error, :timeout}
    end
  end

  defp cleanup_port(port) do
    if Port.info(port) != nil do
      try do
        Port.close(port)
      rescue
        _ -> :ok
      end

      # Drain any remaining messages
      receive do
        {^port, {:exit_status, _}} -> :ok
      after
        100 -> :ok
      end
    end
  end

  defp kill_port(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} ->
        :os.cmd(~c"kill -9 #{os_pid}")

      nil ->
        :ok
    end

    try do
      Port.close(port)
    rescue
      _ -> :ok
    end
  end

  # With {packet, 4}, Port.command expects the raw payload —
  # the BEAM adds the 4-byte length prefix automatically.
  defp frame_payload(<<_len::unsigned-big-integer-size(32), payload::binary>>), do: payload

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.hex_encode32(case: :lower, padding: false)
  end

  defp default_python_root do
    Application.get_env(:liminara_core, :python_root) ||
      Path.expand("../../../../../python", __DIR__)
  end

  defp default_runner(python_root) do
    Application.get_env(:liminara_core, :python_runner) ||
      Path.join(python_root, "src/liminara_op_runner.py")
  end
end
