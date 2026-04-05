defmodule Liminara.Run do
  @moduledoc """
  Run execution and subscription API.

  Contains the synchronous scheduler loop (direct mode) and the
  subscribe/unsubscribe API for :pg-based event broadcasting.
  """

  alias Liminara.{
    Artifact,
    Cache,
    Canonical,
    Decision,
    Event,
    ExecutionContext,
    Executor,
    Hash,
    Op,
    OpResult,
    Plan
  }

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
            event_count: non_neg_integer(),
            node_states: map(),
            failed_nodes: [String.t()]
          }
    defstruct [:run_id, :status, :outputs, :event_count, node_states: %{}, failed_nodes: []]
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
    {:ok, task_supervisor} = Task.Supervisor.start_link()
    Process.unlink(task_supervisor)

    try do
      run_id = generate_run_id(pack_id)
      replay_run_id = Keyword.get(opts, :replay)

      replay_requires_source_execution_context =
        plan_replay_requires_source_execution_context?(plan, replay_run_id, runs_root)

      {execution_context, replay_execution_context_error} =
        resolve_execution_context(runs_root, run_id, pack_id, pack_version, replay_run_id)

      state = %{
        plan: plan,
        run_id: run_id,
        pack_id: pack_id,
        pack_version: pack_version,
        store_root: store_root,
        runs_root: runs_root,
        cache: Keyword.get(opts, :cache),
        replay: replay_run_id,
        task_supervisor: task_supervisor,
        replay_requires_source_execution_context: replay_requires_source_execution_context,
        replay_execution_context_error: replay_execution_context_error,
        execution_context: execution_context,
        completed: MapSet.new(),
        # node_id => %{output_key => artifact_hash}
        outputs: %{},
        prev_hash: nil,
        event_count: 0
      }

      # Persist the plan
      Event.Store.write_plan(runs_root, run_id, plan)

      unless replay_execution_context_error != nil and replay_requires_source_execution_context do
        Event.Store.write_execution_context(runs_root, run_id, execution_context)
      end

      # Emit run_started
      state =
        emit_event(state, "run_started", %{
          "run_id" => run_id,
          "pack_id" => pack_id,
          "pack_version" => pack_version,
          "plan_hash" => Plan.hash(plan),
          "execution_context" =>
            if(replay_execution_context_error != nil and replay_requires_source_execution_context,
              do: nil,
              else: execution_context_payload(execution_context)
            )
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

        {:error, state, node_id, reason} ->
          state =
            emit_event(state, "run_failed", %{
              "run_id" => run_id,
              "error_type" => "op_failure",
              "error_message" => inspect(reason),
              "failed_node" => node_id
            })

          {:ok,
           %Result{
             run_id: run_id,
             status: :failed,
             outputs: state.outputs,
             event_count: state.event_count,
             failed_nodes: [node_id],
             node_states: build_node_states(state, node_id)
           }}
      end
    after
      if Process.alive?(task_supervisor) do
        Process.exit(task_supervisor, :shutdown)
      end
    end
  end

  defp build_node_states(state, failed_node_id) do
    all_nodes = Plan.nodes(state.plan) |> Map.keys()

    Map.new(all_nodes, fn id ->
      cond do
        id == failed_node_id -> {id, :failed}
        MapSet.member?(state.completed, id) -> {id, :completed}
        true -> {id, :pending}
      end
    end)
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
    spec = Op.execution_spec(op_module)
    determinism = spec.determinism.class || op_module.determinism()
    replay_policy = Op.replay_policy(spec)

    # Emit op_started
    state =
      emit_event(state, "op_started", %{
        "node_id" => node_id,
        "op_id" => spec.identity.name || op_module.name(),
        "op_version" => spec.identity.version || op_module.version(),
        "determinism" => Atom.to_string(determinism),
        "input_hashes" => input_hashes
      })

    dispatch_node_by_mode(state, node_id, node, op_module, input_hashes, spec, replay_policy)
  end

  defp dispatch_node_by_mode(state, node_id, node, op_module, input_hashes, spec, replay_policy) do
    cond do
      replay_execution_context_failed?(state, node_id, spec, replay_policy) ->
        handle_replay_execution_context_error(state, node_id, replay_policy)

      state.replay != nil and replay_policy == :skip ->
        handle_replay_skip(state, node_id)

      state.replay != nil and replay_policy == :replay_recorded ->
        handle_replay_inject(state, node_id)

      true ->
        dispatch_cached_or_execute(state, node_id, node, op_module, input_hashes, spec)
    end
  end

  defp dispatch_cached_or_execute(state, node_id, node, op_module, input_hashes, spec) do
    case check_cache(state, op_module, input_hashes) do
      {:hit, output_hashes} -> handle_cache_hit(state, node_id, output_hashes)
      :miss -> dispatch_execute(state, node_id, node, input_hashes, spec)
    end
  end

  defp replay_execution_context_failed?(state, node_id, spec, replay_policy) do
    state.replay != nil and
      state.replay_execution_context_error != nil and
      replay_requires_source_execution_context?(state, node_id, spec, replay_policy)
  end

  defp dispatch_execute(state, node_id, node, input_hashes, spec) do
    resolved_inputs = resolve_inputs(state, node.inputs)

    case Executor.run(node.op_module, resolved_inputs,
           execution_spec: spec,
           task_supervisor: state.task_supervisor,
           execution_context:
             maybe_execution_context(node.op_module, spec, state.execution_context)
         ) do
      {:ok, %OpResult{} = result, duration_ms} ->
        handle_success(state, node_id, result, duration_ms, input_hashes)

      {:gate, prompt, duration_ms} ->
        handle_gate_failure(state, node_id, prompt, duration_ms)

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

  defp handle_gate_failure(state, node_id, prompt, duration_ms) do
    state =
      emit_event(state, "gate_requested", %{
        "node_id" => node_id,
        "prompt" => prompt
      })

    state =
      emit_event(state, "op_failed", %{
        "node_id" => node_id,
        "error_type" => "gate_requires_run_server",
        "error_message" => "gate ops require Run.Server in synchronous mode",
        "duration_ms" => duration_ms
      })

    {:error, state, node_id, {:gate_requires_run_server, prompt}}
  end

  defp handle_replay_execution_context_error(state, node_id, replay_policy) do
    {error_type, error_message, reason} =
      replay_execution_context_error_details(state.replay_execution_context_error, replay_policy)

    state =
      emit_event(state, "op_failed", %{
        "node_id" => node_id,
        "error_type" => error_type,
        "error_message" => error_message,
        "duration_ms" => 0
      })

    {:error, state, node_id, reason}
  end

  defp handle_replay_skip(state, node_id) do
    # Side-effecting op in replay: skip, use empty outputs
    state =
      emit_event(
        state,
        "op_completed",
        %{
          "node_id" => node_id,
          "cache_hit" => true,
          "duration_ms" => 0
        }
        |> Map.merge(output_hash_payload(%{}))
      )

    state = %{
      state
      | completed: MapSet.put(state.completed, node_id),
        outputs: Map.put(state.outputs, node_id, %{})
    }

    {:ok, state}
  end

  defp handle_replay_inject(state, node_id) do
    with {:ok, decisions} <- Decision.Store.get(state.runs_root, state.replay, node_id),
         {:ok, output_hashes} <-
           Decision.Store.get_outputs(state.runs_root, state.replay, node_id) do
      warnings = replay_warnings(state, node_id)

      # Emit decision_recorded events to match discovery provenance
      state =
        Enum.reduce(decisions, state, fn decision, state ->
          emit_event(state, "decision_recorded", %{
            "node_id" => node_id,
            "decision_hash" => decision["decision_hash"],
            "decision_type" => decision["decision_type"]
          })
        end)

      state =
        emit_event(
          state,
          "op_completed",
          %{
            "node_id" => node_id,
            "cache_hit" => false,
            "duration_ms" => 0,
            "warnings" => warnings
          }
          |> Map.merge(output_hash_payload(output_hashes))
        )

      state = %{
        state
        | completed: MapSet.put(state.completed, node_id),
          outputs: Map.put(state.outputs, node_id, output_hashes)
      }

      {:ok, state}
    else
      {:error, :not_found} ->
        handle_missing_replay_recording(state, node_id)
    end
  end

  defp handle_missing_replay_recording(state, node_id) do
    state =
      emit_event(state, "op_failed", %{
        "node_id" => node_id,
        "error_type" => "missing_replay_recording",
        "error_message" => "replay source run is missing stored decision or output data",
        "duration_ms" => 0
      })

    {:error, state, node_id, :missing_replay_recording}
  end

  defp handle_cache_hit(state, node_id, output_hashes) do
    state =
      emit_event(
        state,
        "op_completed",
        %{
          "node_id" => node_id,
          "cache_hit" => true,
          "duration_ms" => 0
        }
        |> Map.merge(output_hash_payload(output_hashes))
      )

    state = %{
      state
      | completed: MapSet.put(state.completed, node_id),
        outputs: Map.put(state.outputs, node_id, output_hashes)
    }

    {:ok, state}
  end

  defp handle_success(state, node_id, %OpResult{} = result, duration_ms, input_hashes) do
    # Store output artifacts
    {output_hashes, state} = store_outputs(state, result.outputs)

    # Record decisions and output_hashes for replay
    state = record_decisions(state, node_id, result.decisions)
    store_output_hashes(state, node_id, output_hashes)
    store_warnings(state, node_id, result.warnings)

    # Store in cache if cacheable
    store_in_cache(state, node_id, input_hashes, output_hashes)

    # Emit op_completed
    state =
      emit_event(
        state,
        "op_completed",
        %{
          "node_id" => node_id,
          "cache_hit" => false,
          "duration_ms" => duration_ms,
          "warnings" => Enum.map(result.warnings, &warning_payload/1)
        }
        |> Map.merge(output_hash_payload(output_hashes))
      )

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

  defp store_output_hashes(_state, _node_id, output_hashes) when map_size(output_hashes) == 0,
    do: :ok

  defp store_output_hashes(state, node_id, output_hashes) do
    Decision.Store.put_outputs(state.runs_root, state.run_id, node_id, output_hashes)
  end

  defp store_warnings(_state, _node_id, []), do: :ok

  defp store_warnings(state, node_id, warnings) do
    warnings = Enum.map(warnings, &warning_payload/1)
    Decision.Store.put_warnings(state.runs_root, state.run_id, node_id, warnings)
  end

  defp replay_warnings(state, node_id) do
    case Decision.Store.get_warnings(state.runs_root, state.replay, node_id) do
      {:ok, warnings} -> warnings
      {:error, :not_found} -> []
    end
  end

  defp record_decisions(state, _node_id, []), do: state

  defp record_decisions(state, node_id, decisions) do
    node = Plan.get_node(state.plan, node_id)
    op_module = node.op_module
    spec = Op.execution_spec(op_module)

    Enum.reduce(decisions, state, fn decision, state ->
      record =
        Map.merge(decision, %{
          "node_id" => node_id,
          "op_id" => spec.identity.name || op_module.name(),
          "op_version" => spec.identity.version || op_module.version(),
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

  defp build_execution_context(run_id, pack_id, pack_version, replay_run_id) do
    %ExecutionContext{
      run_id: run_id,
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      pack_id: pack_id,
      pack_version: pack_version,
      replay_of_run_id: replay_run_id
    }
  end

  defp resolve_execution_context(runs_root, run_id, pack_id, pack_version, replay_run_id) do
    fallback_context = build_execution_context(run_id, pack_id, pack_version, replay_run_id)

    case replay_run_id do
      nil ->
        {fallback_context, nil}

      replay_run_id ->
        case Event.Store.read_execution_context(runs_root, replay_run_id) do
          {:ok, execution_context} ->
            {
              %ExecutionContext{execution_context | replay_of_run_id: replay_run_id},
              nil
            }

          {:error, reason} when reason in [:not_found, :invalid] ->
            {fallback_context, reason}
        end
    end
  end

  defp execution_context_payload(%ExecutionContext{} = execution_context),
    do: Map.from_struct(execution_context)

  defp warning_payload(%_{} = warning), do: Map.from_struct(warning)
  defp warning_payload(warning) when is_map(warning), do: warning

  defp output_hash_payload(output_hashes) do
    %{
      "output_hashes" => Map.values(output_hashes),
      "output_hashes_by_key" => output_hashes
    }
  end

  defp maybe_execution_context(_op_module, spec, execution_context) do
    if spec.execution.requires_execution_context do
      execution_context
    else
      nil
    end
  end

  defp plan_replay_requires_source_execution_context?(_plan, replay_run_id, _runs_root)
       when is_nil(replay_run_id),
       do: false

  defp plan_replay_requires_source_execution_context?(plan, replay_run_id, runs_root) do
    Enum.any?(plan.nodes, fn {node_id, node} ->
      spec = Op.execution_spec(node.op_module)

      replay_requires_source_execution_context?(
        spec,
        Op.replay_policy(spec),
        fn -> replay_recorded_data_available?(runs_root, replay_run_id, node_id) end
      )
    end)
  end

  defp replay_requires_source_execution_context?(spec, :replay_recorded, replay_data_available?) do
    spec.execution.requires_execution_context and not replay_data_available?.()
  end

  defp replay_requires_source_execution_context?(spec, replay_policy, _replay_data_available?) do
    spec.execution.requires_execution_context and replay_policy_requires_execution?(replay_policy)
  end

  defp replay_requires_source_execution_context?(state, node_id, spec, :replay_recorded) do
    spec.execution.requires_execution_context and
      not replay_recorded_data_available?(state.runs_root, state.replay, node_id)
  end

  defp replay_requires_source_execution_context?(_state, _node_id, spec, replay_policy) do
    spec.execution.requires_execution_context and replay_policy_requires_execution?(replay_policy)
  end

  defp replay_policy_requires_execution?(:skip), do: false

  defp replay_policy_requires_execution?(_policy), do: true

  defp replay_recorded_data_available?(runs_root, replay_run_id, node_id) do
    match?({:ok, _}, Decision.Store.get(runs_root, replay_run_id, node_id)) and
      match?({:ok, _}, Decision.Store.get_outputs(runs_root, replay_run_id, node_id))
  end

  defp replay_execution_context_error_details(:not_found, _replay_policy) do
    {
      "missing_replay_execution_context",
      "replay source run is missing execution_context.json",
      :missing_replay_execution_context
    }
  end

  defp replay_execution_context_error_details(:invalid, _replay_policy) do
    {
      "invalid_replay_execution_context",
      "replay source run has invalid execution_context.json",
      :invalid_replay_execution_context
    }
  end
end
