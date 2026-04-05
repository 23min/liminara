defmodule Liminara.Radar.Ops.Specs do
  @moduledoc false

  alias Liminara.ExecutionSpec

  def inline(name, version, class, opts \\ []) do
    build(name, version, class, :inline, Keyword.get(opts, :entrypoint, name), opts)
  end

  def port(name, version, class, entrypoint, opts \\ []) do
    build(name, version, class, :port, entrypoint, opts)
  end

  defp build(name, version, class, executor, entrypoint, opts) do
    ExecutionSpec.new(%{
      identity: %{name: name, version: version},
      determinism: %{
        class: class,
        cache_policy: Keyword.get(opts, :cache_policy, cache_policy_for(class)),
        replay_policy: Keyword.get(opts, :replay_policy, replay_policy_for(class))
      },
      execution: %{
        executor: executor,
        entrypoint: entrypoint,
        requires_execution_context: Keyword.get(opts, :requires_execution_context, false)
      },
      isolation: %{env_vars: Keyword.get(opts, :env_vars, [])},
      contracts: %{
        outputs: Keyword.get(opts, :outputs, %{}),
        decisions: %{may_emit: Keyword.get(opts, :decisions, class == :recordable)},
        warnings: %{may_emit: Keyword.get(opts, :warnings, false)}
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
end