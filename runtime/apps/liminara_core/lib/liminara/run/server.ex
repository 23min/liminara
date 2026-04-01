defmodule Liminara.Run.Server do
  @moduledoc """
  GenServer owning one run's lifecycle.

  Dispatches ops as supervised Tasks, handles completions/failures
  asynchronously, and supports fan-out, fan-in, replay, and caching.

  Started under `Liminara.Run.DynamicSupervisor` and registered
  in `Liminara.Run.Registry` by run_id.
  """

  use GenServer

  alias Liminara.{Artifact, Cache, Canonical, Decision, Event, Executor, Hash, Plan}
  alias Liminara.Run.Result

  defstruct [
    :run_id,
    :pack_id,
    :pack_version,
    :plan,
    :replay,
    :task_supervisor,
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
            Process.demonitor(ref, [:flush])
            {:ok, result}

          {:DOWN, ^ref, :process, ^pid, :normal} ->
            # Server exited before we got the result — it might have sent it
            receive do
              {:run_result, ^run_id, result} -> {:ok, result}
            after
              0 -> {:error, :server_exited}
            end

          {:DOWN, ^ref, :process, ^pid, reason} ->
            {:error, {:crashed, reason}}
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
      task_supervisor: task_sup,
      node_states: node_states
    }

    # Check if there's an existing event log for this run (crash recovery)
    {:ok, existing_events} = Event.Store.read_all(run_id)

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

    state =
      emit_event(state, "run_started", %{
        "run_id" => state.run_id,
        "pack_id" => state.pack_id,
        "pack_version" => state.pack_version,
        "plan_hash" => Plan.hash(state.plan)
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

        status = if last_type == "run_completed", do: :success, else: :failed

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
        {:ok, outputs, duration_ms} ->
          handle_node_success(state, node_id, outputs, duration_ms, [])

        {:ok, outputs, duration_ms, decisions} ->
          handle_node_success(state, node_id, outputs, duration_ms, decisions)

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
    determinism = op_module.determinism()
    input_hashes = compute_input_hashes(state, node.inputs)

    # Emit op_started
    state =
      emit_event(state, "op_started", %{
        "node_id" => node_id,
        "op_id" => op_module.name(),
        "op_version" => op_module.version(),
        "determinism" => Atom.to_string(determinism),
        "input_hashes" => input_hashes
      })

    cond do
      # Replay: skip side-effecting
      state.replay != nil and determinism == :side_effecting ->
        handle_replay_skip(state, node_id)

      # Replay: inject recordable decision
      state.replay != nil and determinism == :recordable ->
        handle_replay_inject(state, node_id)

      # Cache hit
      check_cache(op_module, input_hashes) != :miss ->
        {:hit, output_hashes} = check_cache(op_module, input_hashes)
        handle_cache_hit(state, node_id, output_hashes)

      # Normal execution via Task
      true ->
        dispatch_task(state, node_id, node, input_hashes)
    end
  end

  defp dispatch_task(state, node_id, node, _input_hashes) do
    resolved_inputs = resolve_inputs(state, node.inputs)

    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        result = Executor.run(node.op_module, resolved_inputs)
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
      emit_event(state, "op_completed", %{
        "node_id" => node_id,
        "output_hashes" => [],
        "cache_hit" => true,
        "duration_ms" => 0
      })

    %{
      state
      | node_states: Map.put(state.node_states, node_id, :completed),
        node_outputs: Map.put(state.node_outputs, node_id, %{})
    }
  end

  defp handle_replay_inject(state, node_id) do
    case Decision.Store.get(state.replay, node_id) do
      {:ok, decision} ->
        output_value = get_in(decision, ["output", "response"]) || ""
        {output_hashes, state} = store_outputs(state, %{"result" => output_value})

        state =
          emit_event(state, "op_completed", %{
            "node_id" => node_id,
            "output_hashes" => Map.values(output_hashes),
            "cache_hit" => false,
            "duration_ms" => 0
          })

        %{
          state
          | node_states: Map.put(state.node_states, node_id, :completed),
            node_outputs: Map.put(state.node_outputs, node_id, output_hashes)
        }

      {:error, :not_found} ->
        # No stored decision — fall back to task dispatch
        node = Plan.get_node(state.plan, node_id)
        input_hashes = compute_input_hashes(state, node.inputs)
        dispatch_task(state, node_id, node, input_hashes)
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

    state =
      emit_event(state, "gate_resolved", %{
        "node_id" => node_id,
        "response" => response
      })

    state =
      emit_event(state, "op_completed", %{
        "node_id" => node_id,
        "output_hashes" => Map.values(output_hashes),
        "cache_hit" => false,
        "duration_ms" => 0
      })

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
      emit_event(state, "op_completed", %{
        "node_id" => node_id,
        "output_hashes" => Map.values(output_hashes),
        "cache_hit" => true,
        "duration_ms" => 0
      })

    %{
      state
      | node_states: Map.put(state.node_states, node_id, :completed),
        node_outputs: Map.put(state.node_outputs, node_id, output_hashes)
    }
  end

  # ── Node success / failure ───────────────────────────────────────

  defp handle_node_success(state, node_id, outputs, duration_ms, decisions) do
    {output_hashes, state} = store_outputs(state, outputs)

    # Record decisions
    state = record_decisions(state, node_id, decisions)

    # Cache if applicable
    node = Plan.get_node(state.plan, node_id)
    input_hashes = compute_input_hashes(state, node.inputs)
    store_in_cache(state, node_id, input_hashes, output_hashes)

    state =
      emit_event(state, "op_completed", %{
        "node_id" => node_id,
        "output_hashes" => Map.values(output_hashes),
        "cache_hit" => false,
        "duration_ms" => duration_ms
      })

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

  # ── Completion check ─────────────────────────────────────────────

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

  defp result_from_event_log(run_id) do
    with {:ok, [_ | _] = events} <- Event.Store.read_all(run_id),
         last <- List.last(events),
         t when t in ["run_completed", "run_failed"] <- last["event_type"] do
      status = if t == "run_completed", do: :success, else: :failed

      {:ok,
       %Result{
         run_id: run_id,
         status: status,
         outputs: %{},
         event_count: length(events),
         node_states: %{},
         failed_nodes: []
       }}
    else
      _ -> {:error, :not_found}
    end
  end
end
