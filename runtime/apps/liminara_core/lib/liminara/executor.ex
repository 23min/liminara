defmodule Liminara.Executor do
  @moduledoc """
  Dispatches op execution to the appropriate executor.

  Supports `:inline` (direct call) and `:task` (supervised Task).
  Measures execution duration in milliseconds.
  """

  @doc """
  Run an op module with the given inputs.

  Options:
  - `:executor` — `:inline` (default) or `:task`
  - `:task_supervisor` — required for `:task` executor

  Returns:
  - `{:ok, outputs, duration_ms}` for ops returning `{:ok, outputs}`
  - `{:ok, outputs, duration_ms, decisions}` for ops returning `{:ok, outputs, decisions}`
  - `{:error, reason, duration_ms}` for failed ops
  """
  @spec run(module(), map(), keyword()) ::
          {:ok, map(), non_neg_integer()}
          | {:ok, map(), non_neg_integer(), list()}
          | {:error, term(), non_neg_integer()}
  def run(op_module, inputs, opts \\ []) do
    executor =
      Keyword.get_lazy(opts, :executor, fn ->
        if function_exported?(op_module, :executor, 0),
          do: op_module.executor(),
          else: :inline
      end)

    case executor do
      :inline -> run_inline(op_module, inputs)
      :task -> run_task(op_module, inputs, opts)
      :port -> run_port(op_module, inputs, opts)
    end
  end

  defp run_inline(op_module, inputs) do
    {duration_us, result} = :timer.tc(fn -> op_module.execute(inputs) end)
    duration_ms = div(duration_us, 1000)
    wrap_result(result, duration_ms)
  end

  defp run_task(op_module, inputs, opts) do
    supervisor = Keyword.fetch!(opts, :task_supervisor)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        op_module.execute(inputs)
      end)

    {duration_us, result} = :timer.tc(fn -> Task.await(task) end)
    duration_ms = div(duration_us, 1000)
    wrap_result(result, duration_ms)
  end

  defp run_port(op_module, inputs, opts) do
    op_name =
      if function_exported?(op_module, :python_op, 0),
        do: op_module.python_op(),
        else: op_module.name()

    # Pass op-declared env vars to the port executor
    extra_env =
      if function_exported?(op_module, :env_vars, 0),
        do: op_module.env_vars(),
        else: []

    Liminara.Executor.Port.run(op_name, inputs, Keyword.put(opts, :extra_env, extra_env))
  end

  defp wrap_result({:ok, outputs}, duration_ms), do: {:ok, outputs, duration_ms}

  defp wrap_result({:ok, outputs, decisions}, duration_ms),
    do: {:ok, outputs, duration_ms, decisions}

  defp wrap_result({:gate, prompt}, duration_ms), do: {:gate, prompt, duration_ms}

  defp wrap_result({:error, reason}, duration_ms), do: {:error, reason, duration_ms}
end
