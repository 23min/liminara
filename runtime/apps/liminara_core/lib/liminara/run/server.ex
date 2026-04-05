defmodule Liminara.Run.Server do
  @moduledoc """
  GenServer owning one run's lifecycle.

  Dispatches ops as supervised Tasks, handles completions/failures
  asynchronously, and supports fan-out, fan-in, replay, and caching.

  Started under `Liminara.Run.DynamicSupervisor` and registered
  in `Liminara.Run.Registry` by run_id.
  """

  use GenServer

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

  alias Liminara.Run.Result

  defstruct [
    :run_id,
    :pack_id,
    :pack_version,
    :plan,
    :replay,
    :task_supervisor,
    :execution_context,
    :replay_requires_source_execution_context,
    :replay_execution_context_error,
    node_states: %{},
    node_outputs: %{},
    task_refs: %{},
    prev_hash: nil,
    event_count: 0,
    awaiting: [],
    result: nil
  ]

  # ── Public API ───────────────────────────────────────────────────

  @doc """
  Start a Run.Server under the DynamicSupervisor.

  Options:
  - `:pack_id` — pack identifier (default: "anonymous")
  - `:pack_version` — pack version (default: "0.0.0")
  - `:replay` — run_id of a previous run to replay decisions from
  """
  def start(run_id, %Plan{} = plan, opts \\ []) do
    child_spec = {__MODULE__, Keyword.merge(opts, run_id: run_id, plan: plan)}

    DynamicSupervisor.start_child(Liminara.Run.DynamicSupervisor, child_spec)
  end

  @doc """
  Await the result of a run. Returns `{:ok, result}` or `{:error, :timeout}`.
  """
  def await(run_id, timeout \\ 5000) do
    case Registry.lookup(Liminara.Run.Registry, run_id) do
      [{pid, _}] ->
        ref = Process.monitor(pid)

        # Ask the server for its result (it may already be done)
        send(pid, {:await, self()})

        receive do
          {:run_result, ^run_id, result} ->
            receive do
              {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
            after
              50 -> :ok
            end

            Process.demonitor(ref, [:flush])
            {:ok, result}

          {:DOWN, ^ref, :process, ^pid, reason} ->
            Process.demonitor(ref, [:flush])
            await_result_after_down(run_id, reason)
        after
          timeout ->
            Process.demonitor(ref, [:flush])
            {:error, :timeout}
        end

      [] ->
        result_from_event_log(run_id)
    end
  end

  @doc """
  Resolve a gate for a waiting node. The response becomes the gate's decision and output.
  """
  def resolve_gate(run_id, node_id, response) do
    case Registry.lookup(Liminara.Run.Registry, run_id) do
      [{pid, _}] ->
        GenServer.cast(pid, {:resolve_gate, node_id, response})

      [] ->
        {:error, :not_found}
    end
  end

  # ── GenServer child_spec / start_link ────────────────────────────

  def child_spec(opts) do
    run_id = Keyword.fetch!(opts, :run_id)

    %{
      id: {__MODULE__, run_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)

    GenServer.start_link(__MODULE__, opts,
      name: {:via, Registry, {Liminara.Run.Registry, run_id}}
    )
  end

  # ── GenServer callbacks ──────────────────────────────────────────

  @impl true
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    plan = Keyword.fetch!(opts, :plan)
    pack_id = Keyword.get(opts, :pack_id, "anonymous")
    pack_version = Keyword.get(opts, :pack_version, "0.0.0")
    replay = Keyword.get(opts, :replay)

    replay_requires_source_execution_context =
      plan_replay_requires_source_execution_context?(plan, replay)

    generated_execution_context = build_execution_context(run_id, pack_id, pack_version, replay)

    {replay_execution_context, replay_execution_context_error} =
      replay_execution_context(replay, generated_execution_context)

    # Check if there's an existing event log for this run (crash recovery)
    {:ok, existing_events} = Event.Store.read_all(run_id)

    execution_context =
      if existing_events != [] do
        recover_execution_context(run_id, replay_execution_context, existing_events)
      else
        replay_execution_context
      end

    replay_execution_context_error =
      if existing_events != [] and
           current_run_execution_context_available?(run_id, existing_events) do
        nil
      else
        replay_execution_context_error
      end

    # Start a per-run TaskSupervisor
    {:ok, task_sup} = Task.Supervisor.start_link()

    node_states =
      plan.nodes
      |> Map.keys()
      |> Map.new(fn id -> {id, :pending} end)

    state = %__MODULE__{
      run_id: run_id,
      pack_id: pack_id,
      pack_version: pack_version,
      plan: plan,
      replay: replay,
      execution_context: execution_context,
      replay_requires_source_execution_context: replay_requires_source_execution_context,
      replay_execution_context_error: replay_execution_context_error,
      task_supervisor: task_sup,
      node_states: node_states
    }

    if existing_events != [] do
      {:ok, state, {:continue, {:rebuild, existing_events}}}
    else
      {:ok, state, {:continue, :start_run}}
    end
  end

  @impl true
  def handle_continue(:start_run, state) do
    # Persist the plan as a first-class artifact of the run
    Event.Store.write_plan(state.run_id, state.plan)

    unless state.replay_execution_context_error != nil and
             state.replay_requires_source_execution_context do
      Event.Store.write_execution_context(state.run_id, state.execution_context)
    end

    state =
      emit_event(state, "run_started", %{
        "run_id" => state.run_id,
        "pack_id" => state.pack_id,
        "pack_version" => state.pack_version,
        "plan_hash" => Plan.hash(state.plan),
        "execution_context" =>
          if(
            state.replay_execution_context_error != nil and
              state.replay_requires_source_execution_context,
            do: nil,
            else: execution_context_payload(state.execution_context)
          )
      })

    state = dispatch_ready(state)
    {:noreply, maybe_complete(state)}
  end

  def handle_continue({:rebuild, events}, state) do
    state = rebuild_from_events(state, events)

    last_event = List.last(events)
    last_type = last_event["event_type"]

    cond do
      last_type in ["run_completed", "run_failed"] ->
        # Run was already finished — just report the result
        # Touch events.jsonl so mtime-based run lists reflect recent access
        Event.Store.touch(state.run_id)
        # Broadcast all events (atom-keyed) so live observers receive the full run
        Enum.each(events, fn e -> broadcast(state.run_id, atomize_event(e)) end)

        status = terminal_status(last_type, state.node_states)

        failed_nodes =
          state.node_states
          |> Enum.filter(fn {_, s} -> s == :failed end)
          |> Enum.map(fn {id, _} -> id end)

        result = %Result{
          run_id: state.run_id,
          status: status,
          outputs: state.node_outputs,
          event_count: state.event_count,
          node_states: state.node_states,
          failed_nodes: failed_nodes
        }

        state = %{state | result: result}
        Process.send_after(self(), :stop, 0)
        {:noreply, state}

      true ->
        # Run was interrupted — reset in-progress nodes and continue
        node_states =
          Map.new(state.node_states, fn
            {id, :running} -> {id, :pending}
            other -> other
          end)

        state = %{state | node_states: node_states}
        state = dispatch_ready(state)
        {:noreply, maybe_complete(state)}
    end
  end

  defp rebuild_from_events(state, events) do
    Enum.reduce(events, state, fn event, state ->
      type = event["event_type"]
      payload = event["payload"]

      state = %{
        state
        | prev_hash: event["event_hash"],
          event_count: state.event_count + 1
      }

      case type do
        "op_completed" ->
          node_id = payload["node_id"]
          # Rebuild output hashes from event store artifacts
          # The artifacts are already in the store from the original run
          output_hashes = rebuild_output_hashes(state, node_id, payload)

          %{
            state
            | node_states: Map.put(state.node_states, node_id, :completed),
              node_outputs: Map.put(state.node_outputs, node_id, output_hashes)
          }

        "op_started" ->
          node_id = payload["node_id"]
          %{state | node_states: Map.put(state.node_states, node_id, :running)}

        "op_failed" ->
          node_id = payload["node_id"]
          %{state | node_states: Map.put(state.node_states, node_id, :failed)}

        _ ->
          state
      end
    end)
  end

  defp rebuild_output_hashes(_state, _node_id, %{"output_hashes_by_key" => output_hashes})
       when is_map(output_hashes) do
    output_hashes
  end

  defp rebuild_output_hashes(_state, _node_id, %{"output_hashes" => hashes})
       when is_list(hashes) and hashes != [] do
    # For rebuild, we reconstruct a simple map from the stored hashes
    # The original key names are lost in the event, use "result" as default
    hashes
    |> Enum.with_index()
    |> Map.new(fn
      {hash, 0} -> {"result", hash}
      {hash, i} -> {"output_#{i}", hash}
    end)
  end

  defp rebuild_output_hashes(_state, _node_id, _payload), do: %{}

  @impl true
  def handle_info({ref, {:node_result, node_id, result}}, state) when is_reference(ref) do
    # Task completed successfully — demonitor and flush
    Process.demonitor(ref, [:flush])
    state = %{state | task_refs: Map.delete(state.task_refs, ref)}

    state =
      case result do
        {:ok, %OpResult{} = op_result, duration_ms} ->
          handle_node_success(state, node_id, op_result, duration_ms)

        {:gate, prompt, _duration_ms} ->
          handle_gate_requested(state, node_id, prompt)

        {:error, reason, duration_ms} ->
          handle_node_failure(state, node_id, reason, duration_ms)
      end

    state = dispatch_ready(state)
    {:noreply, maybe_complete(state)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) when is_reference(ref) do
    # Task crashed
    case Map.pop(state.task_refs, ref) do
      {nil, _} ->
        {:noreply, state}

      {node_id, task_refs} ->
        state = %{state | task_refs: task_refs}
        state = handle_node_failure(state, node_id, reason, 0)
        state = dispatch_ready(state)
        {:noreply, maybe_complete(state)}
    end
  end

  def handle_info({:await, caller}, %{result: nil} = state) do
    {:noreply, %{state | awaiting: [caller | state.awaiting]}}
  end

  def handle_info({:await, caller}, %{result: result} = state) do
    send(caller, {:run_result, state.run_id, result})
    {:noreply, state}
  end

  def handle_info(:stop, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:resolve_gate, node_id, response}, state) do
    if state.node_states[node_id] == :waiting do
      state = handle_gate_resolved(state, node_id, response)
      state = dispatch_ready(state)
      {:noreply, maybe_complete(state)}
    else
      {:noreply, state}
    end
  end

  # ── Dispatch ─────────────────────────────────────────────────────

  defp dispatch_ready(state) do
    # Find all pending nodes whose inputs are satisfied
    completed = completed_set(state)
    ready = Plan.ready_nodes(state.plan, completed)

    pending_ready =
      Enum.filter(ready, fn id -> state.node_states[id] == :pending end)

    case pending_ready do
      [] ->
        state

      _ ->
        # Dispatch all pending_ready nodes in this batch, then re-check.
        state = Enum.reduce(pending_ready, state, &dispatch_if_pending/2)

        # Re-check: synchronous completions (cache hits) may have
        # unblocked new nodes.
        dispatch_ready(state)
    end
  end

  defp dispatch_if_pending(node_id, acc) do
    if acc.node_states[node_id] == :pending, do: dispatch_node(acc, node_id), else: acc
  end

  defp dispatch_node(state, node_id) do
    node = Plan.get_node(state.plan, node_id)
    op_module = node.op_module
    spec = Op.execution_spec(op_module)
    determinism = spec.determinism.class || op_module.determinism()
    replay_policy = Op.replay_policy(spec)
    input_hashes = compute_input_hashes(state, node.inputs)

    # Emit op_started
    state =
      emit_event(state, "op_started", %{
        "node_id" => node_id,
        "op_id" => spec.identity.name || op_module.name(),
        "op_version" => spec.identity.version || op_module.version(),
        "determinism" => Atom.to_string(determinism),
        "input_hashes" => input_hashes
      })

    cond do
      state.replay != nil and state.replay_execution_context_error != nil and
          replay_requires_source_execution_context?(state, node_id, spec, replay_policy) ->
        handle_replay_execution_context_error(state, node_id, replay_policy)

      # Replay: branch on canonical replay policy.
      state.replay != nil and replay_policy == :skip ->
        handle_replay_skip(state, node_id)

      state.replay != nil and replay_policy == :replay_recorded ->
        handle_replay_inject(state, node_id)

      # Cache hit
      check_cache(op_module, input_hashes) != :miss ->
        {:hit, output_hashes} = check_cache(op_module, input_hashes)
        handle_cache_hit(state, node_id, output_hashes)

      # Normal execution via Task
      true ->
        dispatch_task(state, node_id, node, input_hashes, spec)
    end
  end

  defp dispatch_task(state, node_id, node, _input_hashes, spec) do
    resolved_inputs = resolve_inputs(state, node.inputs)

    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        result =
          Executor.run(node.op_module, resolved_inputs,
            execution_spec: spec,
            task_supervisor: state.task_supervisor,
            execution_context:
              maybe_execution_context(node.op_module, spec, state.execution_context)
          )

        {:node_result, node_id, result}
      end)

    %{
      state
      | node_states: Map.put(state.node_states, node_id, :running),
        task_refs: Map.put(state.task_refs, task.ref, node_id)
    }
  end

  # ── Replay handling ──────────────────────────────────────────────

  defp handle_replay_skip(state, node_id) do
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

    %{
      state
      | node_states: Map.put(state.node_states, node_id, :completed),
        node_outputs: Map.put(state.node_outputs, node_id, %{})
    }
  end

  defp handle_replay_inject(state, node_id) do
    with {:ok, decisions} <- Decision.Store.get(state.replay, node_id),
         {:ok, output_hashes} <- Decision.Store.get_outputs(state.replay, node_id) do
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

      %{
        state
        | node_states: Map.put(state.node_states, node_id, :completed),
          node_outputs: Map.put(state.node_outputs, node_id, output_hashes)
      }
    else
      {:error, :not_found} ->
        handle_missing_replay_recording(state, node_id)
    end
  end

  # ── Gate handling ─────────────────────────────────────────────────

  defp handle_gate_requested(state, node_id, prompt) do
    state =
      emit_event(state, "gate_requested", %{
        "node_id" => node_id,
        "prompt" => prompt
      })

    %{state | node_states: Map.put(state.node_states, node_id, :waiting)}
  end

  defp handle_gate_resolved(state, node_id, response) do
    # Record the gate decision
    decision = %{
      "decision_type" => "gate_approval",
      "inputs" => %{"node_id" => node_id},
      "output" => %{"response" => Jason.encode!(response)}
    }

    {output_hashes, state} = store_outputs(state, %{"result" => Jason.encode!(response)})

    state = record_decisions(state, node_id, [decision])
    store_output_hashes(state, node_id, output_hashes)

    state =
      emit_event(state, "gate_resolved", %{
        "node_id" => node_id,
        "response" => response
      })

    state =
      emit_event(
        state,
        "op_completed",
        %{
          "node_id" => node_id,
          "cache_hit" => false,
          "duration_ms" => 0
        }
        |> Map.merge(output_hash_payload(output_hashes))
      )

    %{
      state
      | node_states: Map.put(state.node_states, node_id, :completed),
        node_outputs: Map.put(state.node_outputs, node_id, output_hashes)
    }
  end

  # ── Cache handling ───────────────────────────────────────────────

  defp check_cache(op_module, input_hashes) do
    if Cache.cacheable?(op_module) do
      Cache.lookup(Liminara.Cache, op_module, input_hashes)
    else
      :miss
    end
  end

  defp store_in_cache(state, node_id, input_hashes, output_hashes) do
    op_module = Plan.get_node(state.plan, node_id).op_module

    if Cache.cacheable?(op_module) do
      Cache.store(Liminara.Cache, op_module, input_hashes, output_hashes)
    end
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

    %{
      state
      | node_states: Map.put(state.node_states, node_id, :completed),
        node_outputs: Map.put(state.node_outputs, node_id, output_hashes)
    }
  end

  # ── Node success / failure ───────────────────────────────────────

  defp handle_node_success(state, node_id, %OpResult{} = result, duration_ms) do
    {output_hashes, state} = store_outputs(state, result.outputs)

    # Record decisions and output_hashes for replay
    state = record_decisions(state, node_id, result.decisions)
    store_output_hashes(state, node_id, output_hashes)
    store_warnings(state, node_id, result.warnings)

    # Cache if applicable
    node = Plan.get_node(state.plan, node_id)
    input_hashes = compute_input_hashes(state, node.inputs)
    store_in_cache(state, node_id, input_hashes, output_hashes)

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

    %{
      state
      | node_states: Map.put(state.node_states, node_id, :completed),
        node_outputs: Map.put(state.node_outputs, node_id, output_hashes)
    }
  end

  defp handle_node_failure(state, node_id, reason, duration_ms) do
    state =
      emit_event(state, "op_failed", %{
        "node_id" => node_id,
        "error_type" => "execution_error",
        "error_message" => inspect(reason),
        "duration_ms" => duration_ms
      })

    %{state | node_states: Map.put(state.node_states, node_id, :failed)}
  end

  defp handle_replay_execution_context_error(state, node_id, replay_policy) do
    {error_type, error_message, _reason} =
      replay_execution_context_error_details(state.replay_execution_context_error, replay_policy)

    state =
      emit_event(state, "op_failed", %{
        "node_id" => node_id,
        "error_type" => error_type,
        "error_message" => error_message,
        "duration_ms" => 0
      })

    %{state | node_states: Map.put(state.node_states, node_id, :failed)}
  end

  defp handle_missing_replay_recording(state, node_id) do
    state =
      emit_event(state, "op_failed", %{
        "node_id" => node_id,
        "error_type" => "missing_replay_recording",
        "error_message" => "replay source run is missing stored decision or output data",
        "duration_ms" => 0
      })

    %{state | node_states: Map.put(state.node_states, node_id, :failed)}
  end

  # ── Completion check ─────────────────────────────────────────────

  defp maybe_complete(%{result: result} = state) when not is_nil(result), do: state

  defp maybe_complete(state) do
    completed = completed_set(state)

    if Plan.all_complete?(state.plan, completed) do
      finish_run(state, :success)
    else
      maybe_complete_stuck(state)
    end
  end

  defp maybe_complete_stuck(state) do
    statuses = Map.values(state.node_states)
    any_running = :running in statuses
    any_waiting = :waiting in statuses
    any_failed = :failed in statuses
    any_pending = :pending in statuses
    any_completed = :completed in statuses
    stuck = not any_running and not any_waiting

    cond do
      stuck and any_failed and any_completed and not any_pending ->
        finish_run(state, :partial)

      stuck and any_failed ->
        finish_run(state, :failed)

      true ->
        state
    end
  end

  defp finish_run(state, status) do
    event_type = if status == :success, do: "run_completed", else: "run_failed"

    artifact_hashes =
      state.node_outputs
      |> Map.values()
      |> Enum.flat_map(&Map.values/1)

    failed_nodes =
      state.node_states
      |> Enum.filter(fn {_, s} -> s == :failed end)
      |> Enum.map(fn {id, _} -> id end)

    payload =
      case status do
        :success ->
          %{
            "run_id" => state.run_id,
            "outcome" => "success",
            "artifact_hashes" => artifact_hashes
          }

        _ ->
          %{
            "run_id" => state.run_id,
            "error_type" => "run_failure",
            "error_message" => "one or more nodes failed",
            "failed_nodes" => failed_nodes
          }
      end

    state = emit_event(state, event_type, payload)

    # Write seal on success or partial
    if status in [:success, :partial] do
      Event.Store.write_seal(state.run_id)
    end

    result = %Result{
      run_id: state.run_id,
      status: status,
      outputs: state.node_outputs,
      event_count: state.event_count,
      node_states: state.node_states,
      failed_nodes: failed_nodes
    }

    # Notify all waiting callers
    for caller <- state.awaiting do
      send(caller, {:run_result, state.run_id, result})
    end

    # Schedule stop
    Process.send_after(self(), :stop, 0)

    %{state | result: result, awaiting: []}
  end

  # ── Input resolution ─────────────────────────────────────────────

  defp resolve_inputs(state, inputs) do
    Map.new(inputs, fn
      {name, {:literal, value}} ->
        {name, value}

      {name, {:ref, ref_node_id, output_key}} ->
        hash = state.node_outputs[ref_node_id][output_key]
        {:ok, content} = Artifact.Store.get(hash)
        {name, content}

      {name, {:ref, ref_node_id}} ->
        hashes = state.node_outputs[ref_node_id]
        {_key, hash} = Enum.at(hashes, 0)
        {:ok, content} = Artifact.Store.get(hash)
        {name, content}
    end)
  end

  defp compute_input_hashes(state, inputs) do
    inputs
    |> Enum.flat_map(fn
      {_name, {:literal, value}} ->
        [Hash.hash_bytes(Canonical.encode_to_iodata(value))]

      {_name, {:ref, ref_node_id, output_key}} ->
        [state.node_outputs[ref_node_id][output_key]]

      {_name, {:ref, ref_node_id}} ->
        state.node_outputs[ref_node_id] |> Map.values()
    end)
  end

  # ── Output storage ───────────────────────────────────────────────

  defp store_outputs(state, outputs) do
    Enum.reduce(outputs, {%{}, state}, fn {key, value}, {hashes, state} ->
      content =
        if is_binary(value) do
          value
        else
          Canonical.encode(value)
        end

      {:ok, hash} = Artifact.Store.put(content)
      {Map.put(hashes, key, hash), state}
    end)
  end

  # ── Decision recording ──────────────────────────────────────────

  defp store_output_hashes(_state, _node_id, output_hashes) when map_size(output_hashes) == 0,
    do: :ok

  defp store_output_hashes(state, node_id, output_hashes) do
    Decision.Store.put_outputs(state.run_id, node_id, output_hashes)
  end

  defp store_warnings(_state, _node_id, []), do: :ok

  defp store_warnings(state, node_id, warnings) do
    warnings = Enum.map(warnings, &warning_payload/1)
    Decision.Store.put_warnings(state.run_id, node_id, warnings)
  end

  defp replay_warnings(state, node_id) do
    case Decision.Store.get_warnings(state.replay, node_id) do
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

      {:ok, decision_hash} = Decision.Store.put(state.run_id, record)

      emit_event(state, "decision_recorded", %{
        "node_id" => node_id,
        "decision_hash" => decision_hash,
        "decision_type" => decision["decision_type"]
      })
    end)
  end

  # ── Event emission ───────────────────────────────────────────────

  defp emit_event(state, event_type, payload) do
    {:ok, event} =
      Event.Store.append(state.run_id, event_type, payload, state.prev_hash)

    broadcast(state.run_id, event)

    %{state | prev_hash: event.event_hash, event_count: state.event_count + 1}
  end

  defp broadcast(run_id, event) do
    msg = {:run_event, run_id, event}

    :pg.get_members(:liminara, {:run, run_id})
    |> Enum.each(&send(&1, msg))

    :pg.get_members(:liminara, :all_runs)
    |> Enum.each(&send(&1, msg))
  end

  # ── Helpers ──────────────────────────────────────────────────────

  defp completed_set(state) do
    state.node_states
    |> Enum.filter(fn {_, s} -> s == :completed end)
    |> Enum.map(fn {id, _} -> id end)
    |> MapSet.new()
  end

  defp atomize_event(%{"event_type" => _} = event) do
    %{
      event_hash: event["event_hash"],
      event_type: event["event_type"],
      payload: event["payload"],
      prev_hash: event["prev_hash"],
      timestamp: event["timestamp"]
    }
  end

  defp atomize_event(event), do: event

  defp await_result_after_down(run_id, reason) do
    receive do
      {:run_result, ^run_id, result} ->
        {:ok, result}
    after
      0 ->
        case result_from_event_log(run_id) do
          {:ok, _result} = ok -> ok
          {:error, :not_found} when reason == :normal -> {:error, :server_exited}
          {:error, :not_found} -> {:error, {:crashed, reason}}
        end
    end
  end

  defp result_from_event_log(run_id) do
    with {:ok, [_ | _] = events} <- Event.Store.read_all(run_id),
         {:ok, plan} <- Event.Store.read_plan(run_id),
         last <- List.last(events),
         t when t in ["run_completed", "run_failed"] <- last["event_type"] do
      node_states = rebuild_node_states(initial_node_states(plan), events)
      outputs = rebuild_outputs_from_events(events)
      status = terminal_status(t, node_states)

      failed_nodes =
        node_states
        |> Enum.filter(fn {_, state} -> state == :failed end)
        |> Enum.map(fn {node_id, _} -> node_id end)

      {:ok,
       %Result{
         run_id: run_id,
         status: status,
         outputs: outputs,
         event_count: length(events),
         node_states: node_states,
         failed_nodes: failed_nodes
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  defp rebuild_node_states(initial_states, events) do
    Enum.reduce(events, initial_states, fn event, states ->
      case {event["event_type"], event["payload"]} do
        {"op_started", %{"node_id" => node_id}} -> Map.put(states, node_id, :running)
        {"op_completed", %{"node_id" => node_id}} -> Map.put(states, node_id, :completed)
        {"op_failed", %{"node_id" => node_id}} -> Map.put(states, node_id, :failed)
        _ -> states
      end
    end)
  end

  defp rebuild_outputs_from_events(events) do
    Enum.reduce(events, %{}, fn event, outputs ->
      case {event["event_type"], event["payload"]} do
        {"op_completed", %{"node_id" => node_id} = payload} ->
          Map.put(
            outputs,
            node_id,
            rebuild_output_hashes(nil, node_id, payload)
          )

        _ ->
          outputs
      end
    end)
  end

  defp initial_node_states(plan) do
    plan.nodes
    |> Map.keys()
    |> Map.new(fn id -> {id, :pending} end)
  end

  defp output_hash_payload(output_hashes) do
    %{
      "output_hashes" => Map.values(output_hashes),
      "output_hashes_by_key" => output_hashes
    }
  end

  defp recover_execution_context(run_id, fallback_context, events) do
    case recover_execution_context_from_events(events) do
      {:ok, execution_context} ->
        execution_context

      :error ->
        case Event.Store.read_execution_context(run_id) do
          {:ok, execution_context} -> execution_context
          {:error, _reason} -> fallback_context
        end
    end
  end

  defp current_run_execution_context_available?(run_id, events) do
    recover_execution_context_from_events(events) != :error or
      match?({:ok, _}, Event.Store.read_execution_context(run_id))
  end

  defp recover_execution_context_from_events(events) do
    run_started =
      events
      |> Enum.filter(&(&1["event_type"] == "run_started"))
      |> Enum.min_by(& &1["timestamp"], fn -> nil end)

    case run_started do
      %{"payload" => %{"execution_context" => execution_context_payload}}
      when is_map(execution_context_payload) ->
        execution_context_from_payload(execution_context_payload)

      _ ->
        :error
    end
  end

  defp execution_context_from_payload(payload) do
    attrs = %{
      run_id: payload["run_id"],
      started_at: payload["started_at"],
      pack_id: payload["pack_id"],
      pack_version: payload["pack_version"],
      replay_of_run_id: payload["replay_of_run_id"],
      topic_id: payload["topic_id"]
    }

    required_valid? =
      Enum.all?([:run_id, :started_at, :pack_id, :pack_version], fn key ->
        value = Map.get(attrs, key)
        is_binary(value) and value != ""
      end)

    optional_valid? =
      Enum.all?([:replay_of_run_id, :topic_id], fn key ->
        case Map.get(attrs, key) do
          nil -> true
          value when is_binary(value) -> true
          _ -> false
        end
      end)

    if required_valid? and optional_valid? do
      {:ok, struct(ExecutionContext, attrs)}
    else
      :error
    end
  end

  defp replay_execution_context(nil, fallback_context), do: {fallback_context, nil}

  defp replay_execution_context(replay_run_id, fallback_context) do
    case Event.Store.read_execution_context(replay_run_id) do
      {:ok, execution_context} ->
        {%ExecutionContext{execution_context | replay_of_run_id: replay_run_id}, nil}

      {:error, reason} when reason in [:not_found, :invalid] ->
        {fallback_context, reason}
    end
  end

  defp terminal_status("run_completed", _node_states), do: :success

  defp terminal_status("run_failed", node_states) do
    statuses = Map.values(node_states)

    cond do
      :failed in statuses and :completed in statuses and :pending not in statuses and
        :running not in statuses and :waiting not in statuses ->
        :partial

      true ->
        :failed
    end
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

  defp execution_context_payload(%ExecutionContext{} = execution_context),
    do: Map.from_struct(execution_context)

  defp warning_payload(%_{} = warning), do: Map.from_struct(warning)
  defp warning_payload(warning) when is_map(warning), do: warning

  defp maybe_execution_context(_op_module, spec, execution_context) do
    if spec.execution.requires_execution_context do
      execution_context
    else
      nil
    end
  end

  defp plan_replay_requires_source_execution_context?(_plan, replay_run_id)
       when is_nil(replay_run_id),
       do: false

  defp plan_replay_requires_source_execution_context?(plan, replay_run_id) do
    Enum.any?(plan.nodes, fn {node_id, node} ->
      spec = Op.execution_spec(node.op_module)

      replay_requires_source_execution_context?(
        spec,
        Op.replay_policy(spec),
        fn -> replay_recorded_data_available?(replay_run_id, node_id) end
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
      not replay_recorded_data_available?(state.replay, node_id)
  end

  defp replay_requires_source_execution_context?(_state, _node_id, spec, replay_policy) do
    spec.execution.requires_execution_context and replay_policy_requires_execution?(replay_policy)
  end

  defp replay_policy_requires_execution?(:skip), do: false

  defp replay_policy_requires_execution?(_policy), do: true

  defp replay_recorded_data_available?(replay_run_id, node_id) do
    match?({:ok, _}, Decision.Store.get(replay_run_id, node_id)) and
      match?({:ok, _}, Decision.Store.get_outputs(replay_run_id, node_id))
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
