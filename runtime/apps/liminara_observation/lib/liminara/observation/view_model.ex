defmodule Liminara.Observation.ViewModel do
  @moduledoc false

  alias Liminara.Plan

  @required_warning_fields ["code", "severity", "summary"]

  defstruct [
    :run_id,
    :plan,
    run_status: :pending,
    nodes: %{},
    run_started_at: nil,
    run_completed_at: nil,
    event_count: 0,
    events: [],
    events_cap: 1000,
    warning_count: 0,
    degraded_nodes: [],
    degraded: false
  ]

  def init(run_id, %Plan{} = plan, opts \\ []) do
    cap = Keyword.get(opts, :events_cap, 1000)

    nodes =
      Map.new(plan.nodes, fn {node_id, node} ->
        op = node.op_module

        view = %{
          status: :pending,
          op_name: op.name(),
          op_version: op.version(),
          determinism: op.determinism(),
          started_at: nil,
          completed_at: nil,
          duration_ms: nil,
          input_hashes: [],
          output_hashes: [],
          cache_hit: nil,
          error: nil,
          gate_prompt: nil,
          gate_response: nil,
          decisions: [],
          warnings: [],
          degraded: false
        }

        {node_id, view}
      end)

    %__MODULE__{run_id: run_id, plan: plan, nodes: nodes, events_cap: cap}
  end

  def apply_event(state, event) do
    state = %{state | event_count: state.event_count + 1}
    state = apply_typed(state, event_type(event), timestamp(event), payload(event))
    append_event(state, event)
  end

  def filter_events(%__MODULE__{events: events}, filters) when map_size(filters) == 0 do
    events
  end

  def filter_events(%__MODULE__{events: events}, %{event_type: type}) do
    Enum.filter(events, fn e -> (e[:event_type] || e["event_type"]) == type end)
  end

  def filter_events(%__MODULE__{events: events}, %{node_id: node_id}) do
    Enum.filter(events, fn e ->
      pl = e[:payload] || e["payload"] || %{}
      (pl["node_id"] || pl[:node_id]) == node_id
    end)
  end

  defp append_event(%{events: events, events_cap: cap} = state, event) do
    new_events = events ++ [event]

    trimmed =
      if length(new_events) > cap do
        Enum.drop(new_events, length(new_events) - cap)
      else
        new_events
      end

    %{state | events: trimmed}
  end

  defp apply_typed(state, "run_started", ts, _pl) do
    %{state | run_status: :running, run_started_at: ts}
  end

  defp apply_typed(state, "op_started", ts, pl) do
    update_node(state, pl["node_id"], fn n ->
      %{n | status: :running, started_at: ts, input_hashes: pl["input_hashes"] || []}
    end)
  end

  defp apply_typed(state, "op_completed", ts, pl) do
    warnings = extract_op_completed_warnings(pl)

    update_node(state, pl["node_id"], fn n ->
      %{
        n
        | status: :completed,
          completed_at: ts,
          duration_ms: pl["duration_ms"],
          output_hashes: pl["output_hashes"] || [],
          cache_hit: pl["cache_hit"],
          warnings: warnings,
          degraded: warnings != []
      }
    end)
  end

  defp apply_typed(state, "op_failed", _ts, pl) do
    update_node(state, pl["node_id"], fn n ->
      %{n | status: :failed, error: %{type: pl["error_type"], message: pl["error_message"]}}
    end)
  end

  defp apply_typed(state, "gate_requested", _ts, pl) do
    update_node(state, pl["node_id"], fn n ->
      %{n | status: :waiting, gate_prompt: pl["prompt"]}
    end)
  end

  defp apply_typed(state, "gate_resolved", _ts, pl) do
    update_node(state, pl["node_id"], fn n ->
      %{n | gate_response: pl["response"]}
    end)
  end

  defp apply_typed(state, "decision_recorded", _ts, pl) do
    update_node(state, pl["node_id"], fn n ->
      entry = %{hash: pl["decision_hash"], type: pl["decision_type"]}
      %{n | decisions: n.decisions ++ [entry]}
    end)
  end

  defp apply_typed(state, "run_completed", ts, pl) do
    {warning_count, degraded_nodes} = extract_warning_summary!(pl)

    %{
      state
      | run_status: :completed,
        run_completed_at: ts,
        warning_count: warning_count,
        degraded_nodes: degraded_nodes,
        degraded: derive_degraded(:completed, warning_count)
    }
  end

  defp apply_typed(state, "run_failed", ts, pl) do
    {warning_count, degraded_nodes} = extract_warning_summary!(pl)

    %{
      state
      | run_status: :failed,
        run_completed_at: ts,
        warning_count: warning_count,
        degraded_nodes: degraded_nodes,
        degraded: derive_degraded(:failed, warning_count)
    }
  end

  defp apply_typed(state, _unknown, _ts, _pl), do: state

  defp update_node(state, node_id, fun) do
    case Map.fetch(state.nodes, node_id) do
      {:ok, node} -> %{state | nodes: Map.put(state.nodes, node_id, fun.(node))}
      :error -> state
    end
  end

  # ── Warning extraction / validation ──────────────────────────────

  # Every op_completed payload is required to carry a "warnings" list
  # (empty when the node emitted none). Missing or malformed is a contract
  # violation and raises.
  defp extract_op_completed_warnings(payload) do
    case Map.fetch(payload, "warnings") do
      {:ok, warnings} ->
        validate_warnings!(warnings)

      :error ->
        raise ArgumentError,
              "op_completed payload missing required key \"warnings\""
    end
  end

  defp validate_warnings!(warnings) when is_list(warnings) do
    Enum.each(warnings, &validate_warning_entry!/1)
    warnings
  end

  defp validate_warnings!(other) do
    raise ArgumentError,
          "op_completed.warnings must be a list, got: #{inspect(other)}"
  end

  defp validate_warning_entry!(entry) when is_map(entry) do
    for field <- @required_warning_fields do
      unless Map.has_key?(entry, field) do
        raise ArgumentError,
              "warning entry missing required field #{inspect(field)}: #{inspect(entry)}"
      end
    end

    :ok
  end

  defp validate_warning_entry!(other) do
    raise ArgumentError, "warning entry must be a map, got: #{inspect(other)}"
  end

  # run_completed and run_failed both carry warning_summary (M-WARN-01
  # guarantees the key is present on every run, with stable shape).
  # Missing or malformed is a contract violation.
  defp extract_warning_summary!(payload) do
    summary = fetch_summary_map!(payload)
    warning_count = fetch_non_neg_integer!(summary, "warning_count")
    degraded_node_ids = fetch_list!(summary, "degraded_node_ids")
    {warning_count, degraded_node_ids}
  end

  defp fetch_summary_map!(payload) do
    case Map.fetch(payload, "warning_summary") do
      {:ok, %{} = m} ->
        m

      {:ok, other} ->
        raise ArgumentError, "warning_summary must be a map, got: #{inspect(other)}"

      :error ->
        raise ArgumentError,
              "run_completed/run_failed payload missing required key \"warning_summary\""
    end
  end

  defp fetch_non_neg_integer!(summary, key) do
    case Map.fetch(summary, key) do
      {:ok, n} when is_integer(n) and n >= 0 ->
        n

      {:ok, other} ->
        raise ArgumentError,
              "warning_summary.#{key} must be a non-negative integer, got: #{inspect(other)}"

      :error ->
        raise ArgumentError, "warning_summary missing required key #{inspect(key)}"
    end
  end

  defp fetch_list!(summary, key) do
    case Map.fetch(summary, key) do
      {:ok, ids} when is_list(ids) ->
        ids

      {:ok, other} ->
        raise ArgumentError,
              "warning_summary.#{key} must be a list, got: #{inspect(other)}"

      :error ->
        raise ArgumentError, "warning_summary missing required key #{inspect(key)}"
    end
  end

  defp derive_degraded(:failed, _warning_count), do: false
  defp derive_degraded(_status, warning_count) when warning_count > 0, do: true
  defp derive_degraded(_status, _warning_count), do: false

  defp event_type(%{event_type: t}), do: t
  defp event_type(%{"event_type" => t}), do: t

  defp timestamp(%{timestamp: t}), do: t
  defp timestamp(%{"timestamp" => t}), do: t

  defp payload(%{payload: p}), do: p
  defp payload(%{"payload" => p}), do: p
end
