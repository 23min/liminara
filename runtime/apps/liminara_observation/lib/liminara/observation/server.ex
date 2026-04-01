defmodule Liminara.Observation.Server do
  @moduledoc false

  use GenServer

  alias Liminara.{Artifact, Event, Plan}
  alias Liminara.Observation.ViewModel

  # ── Public API ───────────────────────────────────────────────────

  def start_link(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    plan = Keyword.fetch!(opts, :plan)
    GenServer.start(__MODULE__, {run_id, plan})
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  def get_node(pid, node_id) do
    GenServer.call(pid, {:get_node, node_id})
  end

  def get_events(pid) do
    GenServer.call(pid, :get_events)
  end

  def get_events(pid, filters) do
    GenServer.call(pid, {:get_events, filters})
  end

  def get_artifact_content(run_id, hash) when is_binary(run_id) and is_binary(hash) do
    Artifact.Store.get(hash)
  end

  def get_artifact_content(pid, _run_id, hash) when is_pid(pid) do
    GenServer.call(pid, {:get_artifact_content, hash})
  end

  # ── GenServer callbacks ──────────────────────────────────────────

  @impl true
  def init({run_id, %Plan{} = plan}) do
    :pg.join(:liminara, {:run, run_id}, self())

    view = ViewModel.init(run_id, plan)

    {:ok, existing_events} = Event.Store.read_all(run_id)

    {view, seen_hashes, events} =
      Enum.reduce(existing_events, {view, MapSet.new(), []}, fn event, {v, h, e} ->
        hash = event["event_hash"]
        {ViewModel.apply_event(v, event), MapSet.put(h, hash), e ++ [event]}
      end)

    {:ok, %{view: view, seen_hashes: seen_hashes, events: events, run_id: run_id}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.view, state}
  end

  def handle_call({:get_node, node_id}, _from, state) do
    {:reply, Map.get(state.view.nodes, node_id), state}
  end

  def handle_call(:get_events, _from, state) do
    {:reply, state.events, state}
  end

  def handle_call({:get_events, filters}, _from, state) do
    {:reply, ViewModel.filter_events(state.view, filters), state}
  end

  def handle_call({:get_artifact_content, hash}, _from, state) do
    {:reply, Artifact.Store.get(hash), state}
  end

  @impl true
  def handle_info({:run_event, run_id, event}, state) do
    event_hash = Map.get(event, "event_hash") || Map.get(event, :event_hash)

    if event_hash != nil and MapSet.member?(state.seen_hashes, event_hash) do
      {:noreply, state}
    else
      new_view = ViewModel.apply_event(state.view, event)

      new_hashes =
        if event_hash, do: MapSet.put(state.seen_hashes, event_hash), else: state.seen_hashes

      new_events = state.events ++ [event]

      publish_state(run_id, new_view)
      publish_event(run_id, event)

      {:noreply, %{state | view: new_view, seen_hashes: new_hashes, events: new_events}}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    :pg.leave(:liminara, {:run, state.run_id}, self())
  end

  # ── Private ──────────────────────────────────────────────────────

  defp publish_state(run_id, view) do
    Phoenix.PubSub.broadcast(
      Liminara.Observation.PubSub,
      "observation:#{run_id}:state",
      {:state_update, run_id, view}
    )

    if view.run_status in [:running, :completed, :failed] do
      Phoenix.PubSub.broadcast(
        Liminara.Observation.PubSub,
        "runs:index",
        {:run_updated, run_id, view}
      )
    end
  end

  defp publish_event(run_id, event) do
    Phoenix.PubSub.broadcast(
      Liminara.Observation.PubSub,
      "observation:#{run_id}:events",
      {:event_update, run_id, event}
    )
  end
end
