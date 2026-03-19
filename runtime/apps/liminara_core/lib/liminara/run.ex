defmodule Liminara.Run do
  @moduledoc """
  Run execution and subscription API.

  Contains the synchronous scheduler loop (direct mode) and the
  subscribe/unsubscribe API for :pg-based event broadcasting.
  """

  alias Liminara.{Artifact, Cache, Canonical, Decision, Event, Executor, Hash, Plan}

  @doc "Subscribe the calling process to events from the given run."
  @spec subscribe(String.t()) :: :ok
  def subscribe(run_id) do
    :pg.join(:liminara, {:run, run_id}, self())
    :ok
  end

  @doc "Unsubscribe the calling process from events for the given run."
  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(run_id) do
    :pg.leave(:liminara, {:run, run_id}, self())
    :ok
  end

  defmodule Result do
    @moduledoc false
    @type t :: %__MODULE__{
            run_id: String.t(),
            status: atom(),
            outputs: map(),
            event_count: non_neg_integer()
          }
    defstruct [:run_id, :status, :outputs, :event_count]
  end

  @doc """
  Execute a plan and return the result.

  Options:
  - `:pack_id` — pack identifier
  - `:pack_version` — pack version
  - `:store_root` — artifact store root directory
  - `:runs_root` — runs root directory
  """
  @spec execute(Plan.t(), keyword()) :: {:ok, Result.t()}
  def execute(%Plan{} = plan, opts) do
    pack_id = Keyword.fetch!(opts, :pack_id)
    pack_version = Keyword.fetch!(opts, :pack_version)
    store_root = Keyword.fetch!(opts, :store_root)
    runs_root = Keyword.fetch!(opts, :runs_root)

    run_id = generate_run_id(pack_id)

    state = %{
      plan: plan,
      run_id: run_id,
      pack_id: pack_id,
      pack_version: pack_version,
      store_root: store_root,
      runs_root: runs_root,
      cache: Keyword.get(opts, :cache),
      replay: Keyword.get(opts, :replay),
      completed: MapSet.new(),
      # node_id => %{output_key => artifact_hash}
      outputs: %{},
      prev_hash: nil,
      event_count: 0
    }

    # Emit run_started
    state =
      emit_event(state, "run_started", %{
        "run_id" => run_id,
        "pack_id" => pack_id,
        "pack_version" => pack_version,
        "plan_hash" => Plan.hash(plan)
      })

    # Run the scheduler loop
    case scheduler_loop(state) do
      {:ok, state} ->
        # Collect all artifact hashes
        artifact_hashes =
          state.outputs
          |> Map.values()
          |> Enum.flat_map(&Map.values/1)

        state =
          emit_event(state, "run_completed", %{
            "run_id" => run_id,
            "outcome" => "success",
            "artifact_hashes" => artifact_hashes
          })

        # Write seal
        Event.Store.write_seal(runs_root, run_id)

        {:ok,
         %Result{
           run_id: run_id,
           status: :success,
           outputs: state.outputs,
           event_count: state.event_count
         }}

      {:error, state, _node_id, reason} ->
        state =
          emit_event(state, "run_failed", %{
            "run_id" => run_id,
            "error_type" => "op_failure",
            "error_message" => inspect(reason)
          })

        {:ok,
         %Result{
           run_id: run_id,
           status: :failed,
           outputs: state.outputs,
           event_count: state.event_count
         }}
    end
  end

  # ── Scheduler loop ──────────────────────────────────────────────

  defp scheduler_loop(state) do
    ready = Plan.ready_nodes(state.plan, state.completed)

    cond do
      ready == [] and Plan.all_complete?(state.plan, state.completed) ->
        {:ok, state}

      ready == [] ->
        # Should not happen in a valid DAG with no external deps
        {:ok, state}

      true ->
        case dispatch_nodes(state, ready) do
          {:ok, state} -> scheduler_loop(state)
          {:error, _state, _node_id, _reason} = err -> err
        end
    end
  end

  defp dispatch_nodes(state, node_ids) do
    Enum.reduce_while(node_ids, {:ok, state}, fn node_id, {:ok, state} ->
      case dispatch_node(state, node_id) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, state, node_id, reason} -> {:halt, {:error, state, node_id, reason}}
      end
    end)
  end

  defp dispatch_node(state, node_id) do
    node = Plan.get_node(state.plan, node_id)
    op_module = node.op_module
    input_hashes = compute_input_hashes(state, node.inputs)
    determinism = op_module.determinism()

    # Emit op_started
    state =
      emit_event(state, "op_started", %{
        "node_id" => node_id,
        "op_id" => op_module.name(),
        "op_version" => op_module.version(),
        "determinism" => Atom.to_string(determinism),
        "input_hashes" => input_hashes
      })

    # Replay mode: skip side-effecting, inject recordable decisions
    cond do
      state.replay != nil and determinism == :side_effecting ->
        handle_replay_skip(state, node_id)

      state.replay != nil and determinism == :recordable ->
        handle_replay_inject(state, node_id)

      check_cache(state, op_module, input_hashes) != :miss ->
        {:hit, output_hashes} = check_cache(state, op_module, input_hashes)
        handle_cache_hit(state, node_id, output_hashes)

      true ->
        dispatch_execute(state, node_id, node, input_hashes)
    end
  end

  defp dispatch_execute(state, node_id, node, input_hashes) do
    resolved_inputs = resolve_inputs(state, node.inputs)

    case Executor.run(node.op_module, resolved_inputs) do
      {:ok, outputs, duration_ms} ->
        handle_success(state, node_id, outputs, duration_ms, [], input_hashes)

      {:ok, outputs, duration_ms, decisions} ->
        handle_success(state, node_id, outputs, duration_ms, decisions, input_hashes)

      {:error, reason, duration_ms} ->
        state =
          emit_event(state, "op_failed", %{
            "node_id" => node_id,
            "error_type" => "execution_error",
            "error_message" => inspect(reason),
            "duration_ms" => duration_ms
          })

        {:error, state, node_id, reason}
    end
  end

  defp handle_replay_skip(state, node_id) do
    # Side-effecting op in replay: skip, use empty outputs
    state =
      emit_event(state, "op_completed", %{
        "node_id" => node_id,
        "output_hashes" => [],
        "cache_hit" => true,
        "duration_ms" => 0
      })

    state = %{
      state
      | completed: MapSet.put(state.completed, node_id),
        outputs: Map.put(state.outputs, node_id, %{})
    }

    {:ok, state}
  end

  defp handle_replay_inject(state, node_id) do
    # Recordable op in replay: load stored decision and use its output
    case Decision.Store.get(state.runs_root, state.replay, node_id) do
      {:ok, decision} ->
        # The decision's output contains the response — store it as an artifact
        output_value = get_in(decision, ["output", "response"]) || ""
        {output_hashes, state} = store_outputs(state, %{"result" => output_value})

        state =
          emit_event(state, "op_completed", %{
            "node_id" => node_id,
            "output_hashes" => Map.values(output_hashes),
            "cache_hit" => false,
            "duration_ms" => 0
          })

        state = %{
          state
          | completed: MapSet.put(state.completed, node_id),
            outputs: Map.put(state.outputs, node_id, output_hashes)
        }

        {:ok, state}

      {:error, :not_found} ->
        # No stored decision — fall back to normal execution
        node = Plan.get_node(state.plan, node_id)
        input_hashes = compute_input_hashes(state, node.inputs)
        dispatch_execute(state, node_id, node, input_hashes)
    end
  end

  defp handle_cache_hit(state, node_id, output_hashes) do
    state =
      emit_event(state, "op_completed", %{
        "node_id" => node_id,
        "output_hashes" => Map.values(output_hashes),
        "cache_hit" => true,
        "duration_ms" => 0
      })

    state = %{
      state
      | completed: MapSet.put(state.completed, node_id),
        outputs: Map.put(state.outputs, node_id, output_hashes)
    }

    {:ok, state}
  end

  defp handle_success(state, node_id, outputs, duration_ms, decisions, input_hashes) do
    # Store output artifacts
    {output_hashes, state} = store_outputs(state, outputs)

    # Record decisions if any
    state = record_decisions(state, node_id, decisions)

    # Store in cache if cacheable
    store_in_cache(state, node_id, input_hashes, output_hashes)

    # Emit op_completed
    state =
      emit_event(state, "op_completed", %{
        "node_id" => node_id,
        "output_hashes" => Map.values(output_hashes),
        "cache_hit" => false,
        "duration_ms" => duration_ms
      })

    state = %{
      state
      | completed: MapSet.put(state.completed, node_id),
        outputs: Map.put(state.outputs, node_id, output_hashes)
    }

    {:ok, state}
  end

  # ── Input resolution ────────────────────────────────────────────

  defp resolve_inputs(state, inputs) do
    Map.new(inputs, fn
      {name, {:literal, value}} ->
        {name, value}

      {name, {:ref, ref_node_id, output_key}} ->
        hash = state.outputs[ref_node_id][output_key]
        {:ok, content} = Artifact.Store.get(state.store_root, hash)
        {name, content}

      {name, {:ref, ref_node_id}} ->
        # Single-output node — get first output
        hashes = state.outputs[ref_node_id]
        {_key, hash} = Enum.at(hashes, 0)
        {:ok, content} = Artifact.Store.get(state.store_root, hash)
        {name, content}
    end)
  end

  defp compute_input_hashes(state, inputs) do
    inputs
    |> Enum.flat_map(fn
      {_name, {:literal, value}} ->
        [Hash.hash_bytes(Canonical.encode_to_iodata(value))]

      {_name, {:ref, ref_node_id, output_key}} ->
        [state.outputs[ref_node_id][output_key]]

      {_name, {:ref, ref_node_id}} ->
        state.outputs[ref_node_id] |> Map.values()
    end)
  end

  # ── Output storage ──────────────────────────────────────────────

  defp store_outputs(state, outputs) do
    Enum.reduce(outputs, {%{}, state}, fn {key, value}, {hashes, state} ->
      content =
        if is_binary(value) do
          value
        else
          Canonical.encode(value)
        end

      {:ok, hash} = Artifact.Store.put(state.store_root, content)
      {Map.put(hashes, key, hash), state}
    end)
  end

  # ── Decision recording ─────────────────────────────────────────

  defp record_decisions(state, _node_id, []), do: state

  defp record_decisions(state, node_id, decisions) do
    Enum.reduce(decisions, state, fn decision, state ->
      record =
        Map.merge(decision, %{
          "node_id" => node_id,
          "op_id" => Plan.get_node(state.plan, node_id).op_module.name(),
          "op_version" => Plan.get_node(state.plan, node_id).op_module.version(),
          "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        })

      {:ok, decision_hash} = Decision.Store.put(state.runs_root, state.run_id, record)

      emit_event(state, "decision_recorded", %{
        "node_id" => node_id,
        "decision_hash" => decision_hash,
        "decision_type" => decision["decision_type"]
      })
    end)
  end

  # ── Cache ────────────────────────────────────────────────────────

  defp check_cache(%{cache: nil}, _op_module, _input_hashes), do: :miss

  defp check_cache(%{cache: cache}, op_module, input_hashes) do
    if Cache.cacheable?(op_module) do
      Cache.lookup(cache, op_module, input_hashes)
    else
      :miss
    end
  end

  defp store_in_cache(%{cache: nil}, _node_id, _input_hashes, _output_hashes), do: :ok

  defp store_in_cache(%{cache: cache, plan: plan}, node_id, input_hashes, output_hashes) do
    op_module = Plan.get_node(plan, node_id).op_module

    if Cache.cacheable?(op_module) do
      Cache.store(cache, op_module, input_hashes, output_hashes)
    else
      :ok
    end
  end

  # ── Event emission ──────────────────────────────────────────────

  defp emit_event(state, event_type, payload) do
    {:ok, event} =
      Event.Store.append(
        state.runs_root,
        state.run_id,
        event_type,
        payload,
        state.prev_hash
      )

    %{state | prev_hash: event.event_hash, event_count: state.event_count + 1}
  end

  # ── Helpers ─────────────────────────────────────────────────────

  defp generate_run_id(pack_id) do
    now = DateTime.utc_now()
    ts = Calendar.strftime(now, "%Y%m%dT%H%M%S")
    rand = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{pack_id}-#{ts}-#{rand}"
  end
end
