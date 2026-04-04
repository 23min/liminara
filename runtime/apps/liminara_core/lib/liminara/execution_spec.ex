defmodule Liminara.ExecutionSpec do
  @moduledoc """
  Canonical execution contract for an op.

  This structure groups op metadata into explicit sections so execution,
  isolation, and input/output contracts are declared in one place.
  """

  defmodule Identity do
    @moduledoc false
    defstruct [:name, :version]
  end

  defmodule Determinism do
    @moduledoc false
    @type class :: :pure | :pinned_env | :recordable | :side_effecting
    defstruct class: nil, cache_policy: nil, replay_policy: nil
  end

  defmodule Execution do
    @moduledoc false
    defstruct executor: nil,
              entrypoint: nil,
              timeout_ms: nil,
              requires_execution_context: false
  end

  defmodule Isolation do
    @moduledoc false
    defstruct env_vars: [],
              network: :none,
              bootstrap_read_paths: [],
              runtime_read_paths: [],
              runtime_write_paths: []
  end

  defmodule Contracts do
    @moduledoc false
    defstruct inputs: %{},
              outputs: %{},
              decisions: %{may_emit: false},
              warnings: %{may_emit: false}
  end

  defstruct [:identity, :determinism, :execution, :isolation, :contracts]

  @doc """
  Build an ExecutionSpec with canonical section defaults.
  """
  def new(attrs \\ %{}) do
    attrs = normalize_attrs(attrs)

    struct!(
      __MODULE__,
      Map.merge(attrs, %{
        identity: normalize_section(Identity, Map.get(attrs, :identity)),
        determinism: normalize_section(Determinism, Map.get(attrs, :determinism)),
        execution: normalize_section(Execution, Map.get(attrs, :execution)),
        isolation: normalize_section(Isolation, Map.get(attrs, :isolation)),
        contracts: normalize_section(Contracts, Map.get(attrs, :contracts))
      })
    )
  end

  defp normalize_attrs(attrs) when is_map(attrs), do: attrs
  defp normalize_attrs(attrs) when is_list(attrs), do: Map.new(attrs)

  defp normalize_section(module, nil), do: struct(module)

  defp normalize_section(module, %{__struct__: struct_module} = section)
       when struct_module == module,
       do: section

  defp normalize_section(module, attrs) when is_map(attrs), do: struct!(module, attrs)
  defp normalize_section(module, attrs) when is_list(attrs), do: struct!(module, Map.new(attrs))
end
