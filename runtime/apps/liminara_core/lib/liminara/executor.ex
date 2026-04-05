defmodule Liminara.Executor do
  @moduledoc """
  Dispatches op execution to the appropriate executor.

  Supports `:inline` (direct call) and `:task` (supervised Task).
  Measures execution duration in milliseconds.
  """

  alias Liminara.{Op, OpResult}

  @default_task_timeout 5_000

  @doc """
  Run an op module with the given inputs.

  Options:
  - `:executor` — `:inline` (default) or `:task`
  - `:task_supervisor` — required for `:task` executor
  - `:timeout` — overrides the canonical execution timeout for `:task` and `:port`

  Returns:
  - `{:ok, %Liminara.OpResult{}, duration_ms}` for successful execution
  - `{:gate, prompt, duration_ms}` for gate ops
  - `{:error, reason, duration_ms}` for failed ops
  """
  @spec run(module(), map(), keyword()) ::
          {:ok, OpResult.t(), non_neg_integer()}
          | {:gate, term(), non_neg_integer()}
          | {:error, term(), non_neg_integer()}
  def run(op_module, inputs, opts \\ []) do
    spec = Keyword.get_lazy(opts, :execution_spec, fn -> Op.execution_spec(op_module) end)
    executor = Keyword.get(opts, :executor, spec.execution.executor || :inline)
    opts = Keyword.put(opts, :execution_spec, spec)

    case executor do
      :inline -> run_inline(op_module, inputs, opts)
      :task -> run_task(op_module, inputs, opts)
      :port -> run_port(op_module, inputs, opts)
    end
  end

  defp run_inline(op_module, inputs, opts) do
    {duration_us, result} = :timer.tc(fn -> invoke_op(op_module, inputs, opts) end)
    duration_ms = div(duration_us, 1000)
    wrap_result(result, duration_ms)
  end

  defp run_task(op_module, inputs, opts) do
    spec = Keyword.fetch!(opts, :execution_spec)
    supervisor = Keyword.fetch!(opts, :task_supervisor)
    timeout = resolve_timeout(opts, spec, @default_task_timeout)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        invoke_op(op_module, inputs, opts)
      end)

    {duration_us, result} = :timer.tc(fn -> await_task(task, timeout) end)
    duration_ms = div(duration_us, 1000)

    case result do
      {:ok, task_result} -> wrap_result(task_result, duration_ms)
      {:error, reason} -> {:error, reason, duration_ms}
    end
  end

  defp run_port(op_module, inputs, opts) do
    spec = Keyword.get_lazy(opts, :execution_spec, fn -> Op.execution_spec(op_module) end)
    op_name = spec.execution.entrypoint || spec.identity.name
    extra_env = spec.isolation.env_vars || []

    execution_context =
      if spec.execution.requires_execution_context do
        Keyword.get(opts, :execution_context)
      end

    opts
    |> Keyword.put(:extra_env, extra_env)
    |> Keyword.put(:execution_context, execution_context)
    |> then(&Liminara.Executor.Port.run(op_name, inputs, &1))
  end

  defp wrap_result(%OpResult{} = result, duration_ms), do: {:ok, result, duration_ms}

  defp wrap_result({:ok, outputs}, duration_ms),
    do: {:ok, %OpResult{outputs: outputs}, duration_ms}

  defp wrap_result({:ok, outputs, decisions}, duration_ms),
    do: {:ok, %OpResult{outputs: outputs, decisions: decisions}, duration_ms}

  defp wrap_result({:ok, outputs, decisions, warnings}, duration_ms),
    do: {:ok, %OpResult{outputs: outputs, decisions: decisions, warnings: warnings}, duration_ms}

  defp wrap_result({:gate, prompt}, duration_ms), do: {:gate, prompt, duration_ms}

  defp wrap_result({:error, reason}, duration_ms), do: {:error, reason, duration_ms}

  defp invoke_op(op_module, inputs, opts) do
    case Keyword.get(opts, :execution_context) do
      nil ->
        op_module.execute(inputs)

      execution_context ->
        invoke_with_context(op_module, inputs, execution_context)
    end
  end

  defp invoke_with_context(op_module, inputs, execution_context) do
    if function_exported?(op_module, :execute, 2) do
      op_module.execute(inputs, execution_context)
    else
      {:error, :missing_execution_context_handler}
    end
  end

  defp await_task(task, timeout) do
    case Task.yield(task, timeout) do
      {:ok, result} ->
        {:ok, result}

      {:exit, reason} ->
        {:error, reason}

      nil ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  defp resolve_timeout(opts, spec, default) do
    case Keyword.fetch(opts, :timeout) do
      {:ok, timeout} when is_integer(timeout) -> timeout
      _ -> spec.execution.timeout_ms || default
    end
  end
end
