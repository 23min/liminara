defmodule Liminara.Op do
  @moduledoc """
  Behaviour for Liminara operations.

  An op is a typed function (inputs → outputs) with a determinism class
  that controls caching and replay behaviour.
  """

  alias Liminara.ExecutionSpec

  @type determinism :: :pure | :pinned_env | :recordable | :side_effecting
  @type execute_result ::
          {:ok, map()}
          | {:ok, map(), list()}
          | {:ok, map(), list(), list()}
          | {:error, term()}
          | {:gate, term()}
          | struct()

  @doc "Op identifier."
  @callback name() :: String.t()

  @doc "Op version (used in cache key computation)."
  @callback version() :: String.t()

  @doc "Determinism class — controls caching and replay."
  @callback determinism() :: determinism()

  @doc "Canonical execution contract. Preferred over legacy callbacks when exported."
  @callback execution_spec() :: struct()

  @doc "Legacy executor hint. Temporary bridge surface during M-TRUTH-02 migration."
  @callback executor() :: atom()

  @doc "Legacy Python entrypoint hint. Temporary bridge surface during M-TRUTH-02 migration."
  @callback python_op() :: String.t()

  @doc "Legacy environment whitelist hint. Temporary bridge surface during M-TRUTH-02 migration."
  @callback env_vars() :: [String.t()]

  @doc """
  Execute the op with the given inputs.

  Runtime implementations may expose either the legacy `execute/1` surface or
  the canonical `execute/2` form when `execution_spec.requires_execution_context`
  is true.

  Returns a canonical `%Liminara.OpResult{}`, a legacy success tuple,
  `{:error, reason}`, or `{:gate, prompt}` for gate ops.
  """
  @callback execute(inputs :: map()) :: execute_result()

  @doc "Canonical execution entrypoint for ops that require runtime execution context."
  @callback execute(inputs :: map(), execution_context :: struct()) :: execute_result()

  @optional_callbacks execute: 2, execution_spec: 0, executor: 0, python_op: 0, env_vars: 0

  @doc """
  Resolve the canonical execution spec for an op.

  Prefers explicit `execution_spec/0`. Legacy callbacks are derived through a
  bounded runtime shim and must not be treated as a second first-class
  long-term contract surface. Radar no longer relies on this path; remaining
  users are non-Radar/test modules and should migrate before the shim is
  removed from core.
  """
  @spec execution_spec(module()) :: ExecutionSpec.t()
  def execution_spec(op_module) do
    Code.ensure_loaded?(op_module)

    if function_exported?(op_module, :execution_spec, 0) do
      op_module.execution_spec()
    else
      # Remaining compatibility path for non-Radar/test modules that still rely
      # on legacy callback derivation. Remove after those modules migrate to
      # explicit execution_spec/0.
      derive_execution_spec(op_module)
    end
  end

  @doc "Resolve the effective replay policy for an execution spec or op module."
  @spec replay_policy(ExecutionSpec.t() | module()) :: atom() | nil
  def replay_policy(%ExecutionSpec{} = spec) do
    spec.determinism.replay_policy || replay_policy_from_class(spec.determinism.class)
  end

  def replay_policy(op_module) when is_atom(op_module) do
    op_module
    |> execution_spec()
    |> replay_policy()
  end

  defp derive_execution_spec(op_module) do
    determinism = op_module.determinism()

    executor =
      if function_exported?(op_module, :executor, 0), do: op_module.executor(), else: :inline

    entrypoint =
      cond do
        executor == :port and function_exported?(op_module, :python_op, 0) ->
          op_module.python_op()

        true ->
          op_module.name()
      end

    env_vars = if function_exported?(op_module, :env_vars, 0), do: op_module.env_vars(), else: []

    ExecutionSpec.new(%{
      identity: %{name: op_module.name(), version: op_module.version()},
      determinism: %{
        class: determinism,
        cache_policy: cache_policy_for(determinism),
        replay_policy: replay_policy_for(determinism)
      },
      execution: %{
        executor: executor,
        entrypoint: entrypoint,
        requires_execution_context: false
      },
      isolation: %{env_vars: env_vars},
      contracts: %{
        decisions: %{may_emit: determinism == :recordable},
        warnings: %{may_emit: false}
      }
    })
  end

  defp cache_policy_for(:pure), do: :content_addressed
  defp cache_policy_for(:pinned_env), do: :content_addressed_with_environment
  defp cache_policy_for(:recordable), do: :none
  defp cache_policy_for(:side_effecting), do: :none

  defp replay_policy_for(:pure), do: :reexecute
  defp replay_policy_for(:pinned_env), do: :reexecute
  defp replay_policy_for(:recordable), do: :replay_recorded
  defp replay_policy_for(:side_effecting), do: :skip

  defp replay_policy_from_class(nil), do: nil
  defp replay_policy_from_class(class), do: replay_policy_for(class)
end
