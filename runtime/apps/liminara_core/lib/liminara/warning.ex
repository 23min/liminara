defmodule Liminara.Warning do
  @moduledoc """
  Structured warning payload for warning-bearing success.

  Warnings are emitted by ops that complete successfully but produced
  degraded output (fallback content, partial inputs, recoverable LLM
  errors). They are separate from decisions: decisions capture
  nondeterministic choices, warnings capture execution quality.

  The canonical constructor is `new/1`. `code`, `severity`, and
  `summary` are required. `severity` must be drawn from the locked
  taxonomy exposed by `severities/0`.
  """

  @severities [:info, :low, :medium, :high, :degraded]
  @required_fields [:code, :severity, :summary]
  @optional_fields [:cause, :remediation, :affected_outputs]
  @known_fields @required_fields ++ @optional_fields

  @type severity :: :info | :low | :medium | :high | :degraded
  @type t :: %__MODULE__{
          code: String.t(),
          severity: severity(),
          summary: String.t(),
          cause: String.t() | nil,
          remediation: String.t() | nil,
          affected_outputs: [String.t()]
        }

  defstruct [:code, :severity, :summary, :cause, :remediation, affected_outputs: []]

  @doc "Locked severity taxonomy."
  @spec severities() :: [severity()]
  def severities, do: @severities

  @doc """
  Enforce `contracts.warnings.may_emit` for an op's result warnings.

  If `may_emit?` is `false` and `warnings` is non-empty, prepend a canonical
  `"op_warning_contract_violation"` warning so the run still surfaces the
  degraded-outcome signal through the same channel instead of crashing.
  Otherwise, return the warnings unchanged.
  """
  @spec enforce_contract([t() | map()], boolean()) :: [t() | map()]
  def enforce_contract(warnings, may_emit?)
      when is_list(warnings) and is_boolean(may_emit?) do
    cond do
      warnings == [] ->
        warnings

      may_emit? ->
        warnings

      true ->
        [contract_violation_warning(warnings) | warnings]
    end
  end

  defp contract_violation_warning(warnings) do
    emitted = warnings |> Enum.map(&warning_code/1) |> Enum.reject(&is_nil/1)

    summary =
      "op emitted #{length(warnings)} warning(s) while contracts.warnings.may_emit is false" <>
        if emitted == [], do: "", else: " (codes: #{Enum.join(emitted, ", ")})"

    new(%{
      code: "op_warning_contract_violation",
      severity: :high,
      summary: summary,
      cause: "may_emit_false"
    })
  end

  defp warning_code(%__MODULE__{code: code}), do: code
  defp warning_code(%{"code" => code}), do: code
  defp warning_code(%{code: code}), do: code
  defp warning_code(_), do: nil

  @doc """
  Build a validated `%Liminara.Warning{}` from a map or keyword list.

  Raises `ArgumentError` when required fields are missing, when any field has
  the wrong type, when `severity` is outside the locked taxonomy, or when the
  input carries unknown keys.
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) when is_list(attrs), do: new(Map.new(attrs))

  def new(attrs) when is_map(attrs) do
    attrs
    |> reject_unknown_keys!()
    |> validate_required!()
    |> validate_types!()
    |> then(&struct!(__MODULE__, &1))
  end

  defp reject_unknown_keys!(attrs) do
    unknown = Map.keys(attrs) -- @known_fields

    if unknown == [] do
      attrs
    else
      raise ArgumentError,
            "Warning.new/1 received unknown fields: #{inspect(unknown)}"
    end
  end

  defp validate_required!(attrs) do
    missing =
      Enum.filter(@required_fields, fn field ->
        not Map.has_key?(attrs, field) or is_nil(Map.get(attrs, field))
      end)

    if missing == [] do
      attrs
    else
      raise ArgumentError,
            "Warning.new/1 missing required fields: #{inspect(missing)}"
    end
  end

  defp validate_types!(attrs) do
    attrs
    |> validate_binary!(:code)
    |> validate_severity!()
    |> validate_binary!(:summary)
    |> validate_optional_binary!(:cause)
    |> validate_optional_binary!(:remediation)
    |> validate_affected_outputs!()
  end

  defp validate_binary!(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} when is_binary(value) ->
        attrs

      {:ok, value} ->
        raise ArgumentError,
              "Warning.new/1 #{field} must be a binary, got: #{inspect(value)}"

      :error ->
        attrs
    end
  end

  defp validate_optional_binary!(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, nil} -> attrs
      {:ok, value} when is_binary(value) -> attrs
      {:ok, value} -> raise ArgumentError,
                             "Warning.new/1 #{field} must be a binary or nil, got: #{inspect(value)}"
      :error -> attrs
    end
  end

  defp validate_severity!(attrs) do
    case Map.fetch(attrs, :severity) do
      {:ok, severity} when severity in @severities ->
        attrs

      {:ok, other} ->
        raise ArgumentError,
              "Warning.new/1 severity must be one of #{inspect(@severities)}, got: #{inspect(other)}"

      :error ->
        attrs
    end
  end

  defp validate_affected_outputs!(attrs) do
    case Map.fetch(attrs, :affected_outputs) do
      :error ->
        attrs

      {:ok, list} when is_list(list) ->
        if Enum.all?(list, &is_binary/1) do
          attrs
        else
          raise ArgumentError,
                "Warning.new/1 affected_outputs must be a list of binaries, got: #{inspect(list)}"
        end

      {:ok, other} ->
        raise ArgumentError,
              "Warning.new/1 affected_outputs must be a list of binaries, got: #{inspect(other)}"
    end
  end
end
