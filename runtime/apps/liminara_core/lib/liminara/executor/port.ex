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

  alias Liminara.{OpResult, Warning}

  @default_timeout 30_000

  # Only these host env vars are passed to Python ops.
  # Everything else (VIRTUAL_ENV, CONDA_PREFIX, PYTHONPATH, etc.) is excluded.
  @env_whitelist ~w(PATH HOME LANG TERM USER SHELL LC_ALL LC_CTYPE)c

  @doc """
  Run a Python op by name.

  Options:
    - `:python_root` — path to the Python project root (contains src/)
    - `:runner` — path to liminara_op_runner.py
    - `:timeout` — max milliseconds to wait (default canonical spec timeout or #{@default_timeout})

  Returns:
    - `{:ok, %Liminara.OpResult{}, duration_ms}`
    - `{:error, reason, duration_ms}`
  """
  def run(op_name, inputs, opts \\ []) do
    python_root = Keyword.get(opts, :python_root, default_python_root())
    runner = Keyword.get(opts, :runner, default_runner(python_root))
    timeout = resolve_timeout(opts, @default_timeout)
    extra_env = Keyword.get(opts, :extra_env, [])

    execution_context = Keyword.get(opts, :execution_context)
    {id, frame} = encode_request(op_name, inputs, execution_context)

    {duration_us, result} =
      :timer.tc(fn ->
        execute_port(runner, python_root, frame, id, timeout, extra_env)
      end)

    duration_ms = div(duration_us, 1000)

    case result do
      {:ok, %{"status" => "ok"} = response} ->
        {:ok, normalize_success(response), duration_ms}

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
  def encode_request(op_name, inputs, execution_context \\ nil) do
    id = generate_id()

    request = %{
      "id" => id,
      "op" => op_name,
      "inputs" => inputs
    }

    request =
      if execution_context == nil do
        request
      else
        Map.put(request, "context", Map.from_struct(execution_context))
      end

    json = Jason.encode!(request)

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

  defp execute_port(runner, python_root, frame, expected_id, timeout, extra_env) do
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
          {:env, clean_env(extra_env)}
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

  @doc false
  def clean_env(extra_env_names \\ []) do
    extra_charlists = Enum.map(extra_env_names, &String.to_charlist/1)
    allowed = MapSet.new(@env_whitelist ++ extra_charlists)

    # Unset every host env var NOT in the whitelist
    unset =
      System.get_env()
      |> Enum.reject(fn {k, _v} -> MapSet.member?(allowed, String.to_charlist(k)) end)
      |> Enum.map(fn {k, _v} -> {String.to_charlist(k), false} end)

    # Add our explicit vars
    [{~c"PYTHONDONTWRITEBYTECODE", ~c"1"} | unset]
  end

  defp default_python_root do
    Application.get_env(:liminara_core, :python_root) ||
      Path.expand("../../../../../python", __DIR__)
  end

  defp default_runner(python_root) do
    Application.get_env(:liminara_core, :python_runner) ||
      Path.join(python_root, "src/liminara_op_runner.py")
  end

  defp resolve_timeout(opts, default) do
    case Keyword.fetch(opts, :timeout) do
      {:ok, timeout} when is_integer(timeout) ->
        timeout

      _ ->
        case Keyword.get(opts, :execution_spec) do
          %{execution: %{timeout_ms: timeout_ms}} when is_integer(timeout_ms) -> timeout_ms
          _ -> default
        end
    end
  end

  defp normalize_success(%{"outputs" => outputs} = response) do
    %OpResult{
      outputs: outputs,
      decisions: Map.get(response, "decisions", []),
      warnings: response |> Map.get("warnings", []) |> Enum.map(&normalize_warning/1)
    }
  end

  defp normalize_warning(%Warning{} = warning), do: warning

  defp normalize_warning(warning) when is_map(warning) do
    warning =
      Enum.reduce(warning, %{}, fn {key, value}, acc ->
        case normalize_warning_key(key) do
          nil -> acc
          normalized_key -> Map.put(acc, normalized_key, value)
        end
      end)

    warning = Map.update(warning, :severity, nil, &normalize_severity/1)

    struct(Warning, warning)
  end

  defp normalize_warning_key(key)
       when is_atom(key) and
              key in [:affected_outputs, :cause, :code, :remediation, :severity, :summary],
       do: key

  defp normalize_warning_key("affected_outputs"), do: :affected_outputs
  defp normalize_warning_key("cause"), do: :cause
  defp normalize_warning_key("code"), do: :code
  defp normalize_warning_key("remediation"), do: :remediation
  defp normalize_warning_key("severity"), do: :severity
  defp normalize_warning_key("summary"), do: :summary
  defp normalize_warning_key(_key), do: nil

  defp normalize_severity(severity) when is_atom(severity), do: severity
  defp normalize_severity("low"), do: :low
  defp normalize_severity("medium"), do: :medium
  defp normalize_severity("high"), do: :high
  defp normalize_severity("degraded"), do: :degraded
  defp normalize_severity(severity), do: severity
end
