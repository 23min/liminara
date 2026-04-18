defmodule LiminaraWeb.RunsLive.Show do
  use LiminaraWeb, :live_view

  alias Liminara.Event.Store
  alias Liminara.Observation.Server, as: ObsServer
  alias Liminara.Plan

  @impl true
  def mount(%{"id" => run_id}, _session, socket) do
    if connected?(socket) do
      :pg.join(:liminara, {:run, run_id}, self())
      Phoenix.PubSub.subscribe(Liminara.Observation.PubSub, "observation:#{run_id}:state")
      Phoenix.PubSub.subscribe(Liminara.Observation.PubSub, "observation:#{run_id}:events")
    end

    {view_model, obs_nodes} = build_view_model_with_obs(run_id)
    dag_data = build_dag_data(run_id, view_model.nodes)
    initial_events = load_initial_events(run_id)

    # Auto-select a waiting gate node so the user sees the action required
    {gate_node_id, gate_node_data} = find_waiting_gate(obs_nodes)

    {:ok,
     assign(socket,
       run_id: run_id,
       view_model: view_model,
       dag_data: dag_data,
       selected_node: gate_node_id,
       selected_node_data: gate_node_data,
       viewing_artifact: nil,
       obs_nodes: obs_nodes,
       timeline_visible: true,
       timeline_filter: %{},
       all_timeline_events: initial_events
     )}
  end

  @impl true
  def handle_event("select_node", %{"node-id" => node_id}, socket) do
    node_data =
      get_node_data(socket.assigns.obs_nodes, node_id) ||
        find_in_view_model(socket.assigns.view_model, node_id)

    {:noreply,
     assign(socket, selected_node: node_id, selected_node_data: node_data, viewing_artifact: nil)}
  end

  def handle_event("deselect_node", _params, socket) do
    {:noreply, assign(socket, selected_node: nil, selected_node_data: nil, viewing_artifact: nil)}
  end

  def handle_event("view_artifact", %{"hash" => hash}, socket) do
    run_id = socket.assigns.run_id
    result = ObsServer.get_artifact_content(run_id, hash)

    viewing_artifact =
      case result do
        {:ok, content} ->
          type = detect_content_type(content)
          {hash, content, type}

        {:error, :not_found} ->
          {hash, :not_found, :error}
      end

    {:noreply, assign(socket, viewing_artifact: viewing_artifact)}
  end

  def handle_event("close_artifact", _params, socket) do
    {:noreply, assign(socket, viewing_artifact: nil)}
  end

  def handle_event("toggle_timeline", _params, socket) do
    {:noreply, assign(socket, timeline_visible: !socket.assigns.timeline_visible)}
  end

  def handle_event("filter_timeline", %{"filter" => code}, socket) do
    type = filter_code_to_type(code)
    {:noreply, assign(socket, timeline_filter: %{event_type: type})}
  end

  def handle_event("filter_timeline", %{"event_type" => type}, socket) do
    {:noreply, assign(socket, timeline_filter: %{event_type: type})}
  end

  def handle_event("filter_timeline", %{"node_id" => node_id}, socket) do
    {:noreply, assign(socket, timeline_filter: %{node_id: node_id})}
  end

  def handle_event("clear_timeline_filter", _params, socket) do
    {:noreply, assign(socket, timeline_filter: %{})}
  end

  def handle_event("resolve_gate", %{"node-id" => node_id, "action" => action}, socket) do
    run_id = socket.assigns.run_id

    response =
      case action do
        "approve" -> %{"approved" => true}
        "reject" -> %{"approved" => false, "rejected" => true}
        _ -> %{"response" => action}
      end

    Liminara.Run.Server.resolve_gate(run_id, node_id, response)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:run_event, _run_id, event}, socket) do
    view_model = apply_event_to_view_model(socket.assigns.view_model, event)
    dag_data = build_dag_data(socket.assigns.run_id, view_model.nodes)

    selected_node_data =
      maybe_refresh_node_data(socket.assigns.obs_nodes, socket.assigns.selected_node)

    {:noreply,
     assign(socket,
       view_model: view_model,
       dag_data: dag_data,
       selected_node_data: selected_node_data
     )}
  end

  def handle_info({:state_update, _run_id, obs_state}, socket) do
    view_model = observation_state_to_view_model(obs_state)
    dag_data = build_dag_data(socket.assigns.run_id, view_model.nodes)
    obs_nodes = Map.get(obs_state, :nodes, %{})
    selected_node_data = maybe_refresh_node_data(obs_nodes, socket.assigns.selected_node)

    # Sync timeline events from the Observation.Server's authoritative event list
    obs_events = Map.get(obs_state, :events, [])

    all_events =
      if length(obs_events) > length(socket.assigns.all_timeline_events),
        do: obs_events,
        else: socket.assigns.all_timeline_events

    {:noreply,
     assign(socket,
       view_model: view_model,
       dag_data: dag_data,
       obs_nodes: obs_nodes,
       selected_node_data: selected_node_data,
       all_timeline_events: all_events
     )}
  end

  def handle_info({:event_update, _run_id, event}, socket) do
    all_events = socket.assigns.all_timeline_events ++ [event]
    {:noreply, assign(socket, all_timeline_events: all_events)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    run_id = socket.assigns.run_id
    :pg.leave(:liminara, {:run, run_id}, self())
  end

  @impl true
  def render(assigns) do
    {waiting_gate_id, _} = find_waiting_gate(assigns.obs_nodes)

    assigns =
      assign(assigns,
        timeline_events:
          apply_timeline_filter(assigns.all_timeline_events, assigns.timeline_filter),
        decisions: collect_decisions(assigns.obs_nodes),
        waiting_gate: waiting_gate_id
      )

    ~H"""
    <div class="page">
      <nav>
        <a href="/runs">&larr; runs</a>
      </nav>
      <%= if @view_model.not_found do %>
        <h1>{@run_id}</h1>
        <p style="color:var(--dm-muted); font-size:12px;">
          Run <code>{@run_id}</code> not found
        </p>
      <% else %>
        <h1>Run: {@run_id}</h1>
        <div class="run-meta">
          <div>
            <dt>Status</dt>
            <dd>
              <span class={"status status--#{@view_model.run_status}"}>{@view_model.run_status}</span>
              <%= if @view_model[:degraded] do %>
                <span class="status status--degraded" title="Run completed with warnings">
                  degraded
                </span>
              <% end %>
            </dd>
          </div>
          <div>
            <dt>Started</dt>
            <dd>{@view_model.started_at || "&mdash;"}</dd>
          </div>
          <div>
            <dt>Completed</dt>
            <dd>{@view_model.completed_at || "&mdash;"}</dd>
          </div>
          <div>
            <dt>Events</dt>
            <dd>{@view_model.event_count}</dd>
          </div>
          <div>
            <dt>Nodes</dt>
            <dd>{length(@view_model.nodes)}</dd>
          </div>
          <%= if @view_model[:degraded] do %>
            <div>
              <dt>Warnings</dt>
              <dd>{@view_model[:warning_count] || 0}</dd>
            </div>
          <% end %>
          <div style="margin-left:auto;">
            <a
              href={"http://localhost:#{Application.get_env(:liminara_observation, :a2ui_port, 4006)}/?run_id=#{@run_id}"}
              target="_blank"
              style="font-size:13px; color:#888; text-decoration:none; border:1px solid #ccc; border-radius:4px; padding:3px 10px;"
            >
              A2UI
            </a>
          </div>
        </div>
        <%= if @view_model[:degraded] do %>
          <div class="degraded-banner">
            Degraded run: {@view_model[:warning_count] || 0} warning(s) in
            <code>{Enum.join(@view_model[:degraded_nodes] || [], ", ")}</code>
          </div>
        <% end %>
        <div class="gate-banner-slot">
          <%= if @waiting_gate do %>
            <div class="gate-banner" phx-click="select_node" phx-value-node-id={@waiting_gate}>
              Action required: gate <code>{@waiting_gate}</code> is waiting for approval
            </div>
          <% end %>
        </div>
        <div class="run-detail-layout" phx-hook="PanelResize" id="run-detail-layout">
          <div class="dag-area">
            <%= if @dag_data do %>
              <div
                id="dag-map"
                phx-hook="DagMap"
                data-dag={@dag_data}
                data-selected-node={@selected_node || ""}
                style="overflow:auto; padding:8px;"
              >
              </div>
            <% end %>
          </div>
          <%= if @selected_node_data do %>
            <div class="node-inspector">
              <div class="inspector-header">
                <span class="inspector-title">Inspector: <code>{@selected_node}</code></span>
                <button phx-click="deselect_node" class="inspector-close">✕</button>
              </div>
              <%= if @viewing_artifact do %>
                {render_artifact_viewer(assigns)}
              <% else %>
                {render_node_detail(assigns)}
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
      <div class={"timeline-panel #{if @timeline_visible, do: "", else: "timeline--collapsed"}"}>
        <div class="timeline-header">
          <span class="timeline-title">Event Timeline</span>
          <button phx-click="toggle_timeline" class="timeline-toggle">
            {if @timeline_visible, do: "▾", else: "▸"}
          </button>
        </div>
        <%= if @timeline_visible do %>
          <%= if @all_timeline_events != [] do %>
            <div class="timeline-filters">
              <%= if map_size(@timeline_filter) == 0 do %>
                <%= for {code, label} <- [{"os", "Op Start"}, {"oc", "Op Done"}, {"rs", "Run Start"}, {"rc", "Run Done"}] do %>
                  <button phx-click="filter_timeline" phx-value-filter={code} class="filter-btn">
                    {label}
                  </button>
                <% end %>
              <% else %>
                <button phx-click="clear_timeline_filter" class="filter-btn filter-btn--clear">
                  Show All
                </button>
              <% end %>
            </div>
          <% end %>
          <div class="timeline-events">
            <%= for event <- @timeline_events do %>
              <% node_id =
                get_in(event, [:payload, "node_id"]) || get_in(event, ["payload", "node_id"]) %>
              <% event_type = event[:event_type] || event["event_type"] %>
              <% ts = event[:timestamp] || event["timestamp"] %>
              <% short_ts = format_timeline_ts(ts) %>
              <% selected = node_id != nil and node_id == @selected_node %>
              <%= if node_id do %>
                <div
                  class={"timeline-event timeline-event--clickable#{if selected, do: " timeline-event--selected", else: ""}"}
                  phx-click="select_node"
                  phx-value-node-id={node_id}
                >
                  <span class="timeline-event-type">{event_type}</span>
                  <span class="timeline-event-node">{node_id}</span>
                  <span class="timeline-event-ts">{short_ts}</span>
                </div>
              <% else %>
                <div class="timeline-event">
                  <span class="timeline-event-type">{event_type}</span>
                  <span class="timeline-event-ts">{short_ts}</span>
                </div>
              <% end %>
            <% end %>
          </div>
          <%= if @decisions != [] do %>
            <div class="decision-viewer">
              <h4 class="decision-viewer-title">Decisions</h4>
              <%= for dec <- @decisions do %>
                <div
                  class="decision-entry"
                  phx-click="select_node"
                  phx-value-node-id={dec[:node_id]}
                >
                  <span>{dec[:node_id]}</span>
                  <span>{dec[:type] || dec["type"]}</span>
                  <code>{dec[:hash] || dec["hash"]}</code>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp render_node_detail(assigns) do
    ~H"""
    <div class="inspector-body">
      <dl class="inspector-fields">
        <dt>op</dt>
        <dd>{@selected_node_data[:op_name]}</dd>
        <dt>version</dt>
        <dd>{@selected_node_data[:op_version]}</dd>
        <dt>determinism</dt>
        <dd>{@selected_node_data[:determinism]}</dd>
        <dt>status</dt>
        <dd>{@selected_node_data[:status]}</dd>
        <%= if @selected_node_data[:started_at] do %>
          <dt>started</dt>
          <dd>{@selected_node_data[:started_at]}</dd>
        <% end %>
        <%= if @selected_node_data[:completed_at] do %>
          <dt>completed</dt>
          <dd>{@selected_node_data[:completed_at]}</dd>
        <% end %>
        <%= if @selected_node_data[:duration_ms] do %>
          <dt>duration_ms</dt>
          <dd>{@selected_node_data[:duration_ms]}</dd>
        <% end %>
        <%= if @selected_node_data[:cache_hit] != nil do %>
          <dt>cache_hit</dt>
          <dd>{inspect(@selected_node_data[:cache_hit])}</dd>
        <% end %>
      </dl>
      <%= if @selected_node_data[:error] do %>
        <div class="inspector-section">
          <h4>Error</h4>
          <dl class="inspector-fields">
            <dt>type</dt>
            <dd>{@selected_node_data[:error][:type] || @selected_node_data[:error]["type"]}</dd>
            <dt>message</dt>
            <dd>{@selected_node_data[:error][:message] || @selected_node_data[:error]["message"]}</dd>
          </dl>
        </div>
      <% end %>
      <%= if @selected_node_data[:gate_prompt] do %>
        <div class="inspector-section">
          <h4>Gate</h4>
          <dl class="inspector-fields">
            <dt>prompt</dt>
            <dd>{@selected_node_data[:gate_prompt]}</dd>
            <%= if @selected_node_data[:gate_response] do %>
              <dt>response</dt>
              <dd>{format_gate_response(@selected_node_data[:gate_response])}</dd>
            <% end %>
          </dl>
          <%= if @selected_node_data[:status] == :waiting do %>
            <div class="gate-actions">
              <button
                phx-click="resolve_gate"
                phx-value-node-id={@selected_node}
                phx-value-action="approve"
                class="gate-btn gate-btn--approve"
              >
                Approve
              </button>
              <button
                phx-click="resolve_gate"
                phx-value-node-id={@selected_node}
                phx-value-action="reject"
                class="gate-btn gate-btn--reject"
              >
                Reject
              </button>
            </div>
          <% end %>
        </div>
      <% end %>
      <%= if @selected_node_data[:warnings] != [] and @selected_node_data[:warnings] != nil do %>
        <div class="inspector-section inspector-warnings">
          <h4>Warnings</h4>
          <%= for w <- @selected_node_data[:warnings] do %>
            <div class="warning-entry">
              <span class="warning-entry-severity">{w["severity"] || w[:severity]}</span>
              <strong>{w["summary"] || w[:summary]}</strong>
              <dl>
                <dt>Code</dt>
                <dd><code>{w["code"] || w[:code]}</code></dd>
                <%= if (w["cause"] || w[:cause]) do %>
                  <dt>Cause</dt>
                  <dd>{w["cause"] || w[:cause]}</dd>
                <% end %>
                <%= if (w["remediation"] || w[:remediation]) do %>
                  <dt>Remediation</dt>
                  <dd>{w["remediation"] || w[:remediation]}</dd>
                <% end %>
                <%= if (w["affected_outputs"] || w[:affected_outputs]) not in [nil, []] do %>
                  <dt>Affected outputs</dt>
                  <dd>{Enum.join(w["affected_outputs"] || w[:affected_outputs] || [], ", ")}</dd>
                <% end %>
              </dl>
            </div>
          <% end %>
        </div>
      <% end %>
      <%= if @selected_node_data[:decisions] != [] and @selected_node_data[:decisions] != nil do %>
        <div class="inspector-section">
          <h4>Decisions</h4>
          <%= for dec <- @selected_node_data[:decisions] do %>
            <div class="decision-entry">
              <span>{dec[:type] || dec["type"]}</span>
              <span><code>{dec[:hash] || dec["hash"]}</code></span>
            </div>
          <% end %>
        </div>
      <% end %>
      <%= if @selected_node_data[:input_hashes] != [] and @selected_node_data[:input_hashes] != nil do %>
        <div class="inspector-section">
          <h4>Inputs</h4>
          <%= for hash <- @selected_node_data[:input_hashes] do %>
            <div>
              <button phx-click="view_artifact" phx-value-hash={hash} class="hash-link">
                <span class="hash-short">{truncate_hash(hash)}</span>
              </button>
            </div>
          <% end %>
        </div>
      <% end %>
      <%= if @selected_node_data[:output_hashes] != [] and @selected_node_data[:output_hashes] != nil do %>
        <div class="inspector-section">
          <h4>Outputs</h4>
          <%= for hash <- @selected_node_data[:output_hashes] do %>
            <div>
              <button phx-click="view_artifact" phx-value-hash={hash} class="hash-link">
                <span class="hash-short">{truncate_hash(hash)}</span>
              </button>
            </div>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp render_artifact_viewer(assigns) do
    ~H"""
    <div class="artifact-viewer">
      <div class="artifact-header">
        <button phx-click="close_artifact" class="back-btn">&larr; back</button>
        <code class="artifact-hash">{elem(@viewing_artifact, 0)}</code>
      </div>
      <%= case elem(@viewing_artifact, 2) do %>
        <% :json -> %>
          <div class="artifact-content artifact-content--json">
            <span class="artifact-type-badge">json</span>
            <pre>{format_json(elem(@viewing_artifact, 1))}</pre>
          </div>
        <% :text -> %>
          <div class="artifact-content artifact-content--text">
            <pre>{elem(@viewing_artifact, 1)}</pre>
          </div>
        <% :binary -> %>
          <div class="artifact-content artifact-content--binary">
            <dl>
              <dt>type</dt>
              <dd>binary</dd>
              <dt>bytes</dt>
              <dd>{byte_size(elem(@viewing_artifact, 1))}</dd>
              <dt>hash</dt>
              <dd><code>{elem(@viewing_artifact, 0)}</code></dd>
            </dl>
          </div>
        <% :error -> %>
          <div class="artifact-content artifact-content--error">
            <p>Artifact not found: <code>{elem(@viewing_artifact, 0)}</code></p>
          </div>
      <% end %>
    </div>
    """
  end

  # ── DAG data helpers (builds JSON for client-side dag-map) ─────

  defp build_dag_data(run_id, view_model_nodes) do
    result =
      try do
        Store.read_plan(run_id)
      catch
        :exit, _ -> {:error, :unavailable}
      end

    case result do
      {:ok, plan} ->
        plan_to_dag_json(plan, view_model_nodes, run_id)

      _ ->
        # Plan not found or deserialization failed (e.g. test op modules
        # not loaded in web runtime). Fall back to nodes-only layout.
        nodes_only_dag_json(view_model_nodes, run_id)
    end
  end

  defp plan_to_dag_json(%Plan{} = plan, view_model_nodes, run_id) do
    # Build a status lookup from view_model nodes
    status_map = Map.new(view_model_nodes, fn n -> {n.node_id, n.status} end)

    degraded_map =
      Map.new(view_model_nodes, fn n -> {n.node_id, Map.get(n, :degraded, false)} end)

    nodes =
      Enum.map(plan.insert_order, fn node_id ->
        node = Map.fetch!(plan.nodes, node_id)
        status = Map.get(status_map, node_id, "pending")
        cls = status_to_cls(status)
        dim = status == "pending"
        degraded = Map.get(degraded_map, node_id, false)

        base = %{id: node_id, label: dag_label(node), cls: cls, dim: dim}
        if degraded, do: Map.put(base, :degraded, true), else: base
      end)

    # Extract edges from plan refs
    edges =
      for {node_id, node} <- plan.nodes,
          {_input_name, input_val} <- node.inputs,
          ref_id <- extract_ref(input_val),
          do: [ref_id, node_id]

    Jason.encode!(%{
      title: "RUN #{String.slice(run_id, 0..7)}",
      nodes: nodes,
      edges: edges
    })
  end

  defp nodes_only_dag_json([], _run_id), do: nil

  defp nodes_only_dag_json(view_model_nodes, run_id) do
    nodes =
      Enum.map(view_model_nodes, fn n ->
        base = %{
          id: n.node_id,
          label: n.op_name,
          cls: status_to_cls(n.status),
          dim: n.status == "pending"
        }

        if Map.get(n, :degraded, false), do: Map.put(base, :degraded, true), else: base
      end)

    Jason.encode!(%{
      title: "RUN #{String.slice(run_id, 0..7)}",
      nodes: nodes,
      edges: []
    })
  end

  defp extract_ref({:ref, ref_id}), do: [ref_id]
  defp extract_ref({:ref, ref_id, _key}), do: [ref_id]
  defp extract_ref(_), do: []

  defp dag_label(%Plan.Node{op_module: op_module}) do
    op_module
    |> Module.split()
    |> List.last()
  end

  # Map run status to dag-map node class for coloring
  defp status_to_cls("completed"), do: "pure"
  defp status_to_cls("running"), do: "recordable"
  defp status_to_cls("failed"), do: "gate"
  defp status_to_cls("waiting"), do: "gate"
  defp status_to_cls("pending"), do: "pending"
  defp status_to_cls(_), do: "pending"

  # ── view_model build helpers ──────────────────────────────────────

  defp load_initial_events(run_id) do
    case Store.read_all(run_id) do
      {:ok, events} -> events
      _ -> []
    end
  end

  defp apply_timeline_filter(events, filter) when map_size(filter) == 0, do: events

  defp apply_timeline_filter(events, %{event_type: type}) do
    Enum.filter(events, fn e -> (e[:event_type] || e["event_type"]) == type end)
  end

  defp apply_timeline_filter(events, %{node_id: node_id}) do
    Enum.filter(events, fn e ->
      pl = e[:payload] || e["payload"] || %{}
      (pl["node_id"] || pl[:node_id]) == node_id
    end)
  end

  defp collect_decisions(obs_nodes) do
    Enum.flat_map(obs_nodes, fn {node_id, node} ->
      decisions = Map.get(node, :decisions, [])
      Enum.map(decisions, fn d -> Map.put(d, :node_id, node_id) end)
    end)
  end

  defp build_view_model_with_obs(run_id) do
    # Try to start an Observation.Server to get rich node data (timing, hashes, etc.)
    obs_state = try_start_obs_server(run_id)

    case obs_state do
      %{nodes: nodes} = state when map_size(nodes) > 0 ->
        {observation_state_to_view_model(state), nodes}

      _ ->
        {build_view_model(run_id), %{}}
    end
  end

  defp try_start_obs_server(run_id) do
    with {:ok, plan} <- safe_read_plan(run_id),
         {:ok, pid} <- ObsServer.start_link(run_id: run_id, plan: plan) do
      state = ObsServer.get_state(pid)
      # Store pid so we can stop it on terminate, but the GenServer is linked
      # to this LiveView process so it will stop when we stop
      state
    else
      _ -> nil
    end
  end

  defp safe_read_plan(run_id) do
    try do
      Store.read_plan(run_id)
    catch
      :exit, _ -> {:error, :unavailable}
    end
  end

  defp build_view_model(run_id) do
    case Store.read_all(run_id) do
      {:ok, []} ->
        empty_view_model()

      {:ok, events} ->
        build_from_events(events)
    end
  end

  defp empty_view_model do
    %{
      not_found: true,
      run_status: "unknown",
      started_at: nil,
      completed_at: nil,
      event_count: 0,
      nodes: [],
      warning_count: 0,
      degraded_nodes: [],
      degraded: false
    }
  end

  defp build_from_events(events) do
    first = List.first(events)
    last = List.last(events)

    node_events =
      Enum.filter(events, fn e ->
        e["event_type"] in ["op_started", "op_completed", "op_failed"]
      end)

    nodes = build_nodes(node_events)
    {warning_count, degraded_nodes, degraded} = derive_degraded_from_events(events)

    %{
      not_found: false,
      run_status: derive_status(last["event_type"]),
      started_at: first["timestamp"],
      completed_at: completed_at(last),
      event_count: length(events),
      nodes: nodes,
      warning_count: warning_count,
      degraded_nodes: degraded_nodes,
      degraded: degraded
    }
  end

  defp derive_degraded_from_events(events) do
    summary = find_terminal_warning_summary(events)

    case summary do
      %{"warning_count" => n, "degraded_node_ids" => ids} when is_integer(n) and is_list(ids) ->
        {n, ids, n > 0 and not last_event_failed?(events)}

      _ ->
        {0, [], false}
    end
  end

  defp find_terminal_warning_summary(events) do
    events
    |> Enum.reverse()
    |> Enum.find_value(&warning_summary_from_terminal_event/1)
  end

  defp warning_summary_from_terminal_event(event) do
    type = event["event_type"] || event[:event_type]

    if type in ["run_completed", "run_failed"] do
      payload = event["payload"] || event[:payload] || %{}
      payload["warning_summary"] || payload[:warning_summary]
    end
  end

  defp last_event_failed?(events) do
    case List.last(events) do
      nil -> false
      last -> (last["event_type"] || last[:event_type]) == "run_failed"
    end
  end

  defp apply_event_to_view_model(view_model, event) do
    event_type = Map.get(event, "event_type") || Map.get(event, :event_type)
    payload = Map.get(event, "payload") || Map.get(event, :payload) || %{}
    ts = Map.get(event, "timestamp") || Map.get(event, :timestamp)

    view_model =
      view_model
      |> maybe_mark_found(ts)
      |> Map.update!(:event_count, &(&1 + 1))

    apply_event_type(view_model, event_type, payload, ts)
  end

  defp maybe_mark_found(%{not_found: true} = vm, ts), do: %{vm | not_found: false, started_at: ts}
  defp maybe_mark_found(vm, _ts), do: vm

  defp apply_event_type(vm, "run_started", _payload, ts) do
    %{vm | run_status: "running", started_at: ts}
  end

  defp apply_event_type(vm, "run_completed", payload, ts) do
    {wc, ids} = extract_summary(payload)

    vm
    |> Map.put(:run_status, "completed")
    |> Map.put(:completed_at, ts)
    |> Map.put(:warning_count, wc)
    |> Map.put(:degraded_nodes, ids)
    |> Map.put(:degraded, wc > 0)
  end

  defp apply_event_type(vm, "run_failed", payload, ts) do
    {wc, ids} = extract_summary(payload)

    vm
    |> Map.put(:run_status, "failed")
    |> Map.put(:completed_at, ts)
    |> Map.put(:warning_count, wc)
    |> Map.put(:degraded_nodes, ids)
    |> Map.put(:degraded, false)
  end

  defp apply_event_type(vm, "op_started", payload, _ts) do
    node_id = Map.get(payload, "node_id")
    op_name = Map.get(payload, "op_id", node_id)
    update_node(vm, node_id, fn _ -> %{node_id: node_id, op_name: op_name, status: "running"} end)
  end

  defp apply_event_type(vm, "op_completed", payload, _ts) do
    node_id = Map.get(payload, "node_id")
    update_node(vm, node_id, fn n -> %{n | status: "completed"} end)
  end

  defp apply_event_type(vm, "op_failed", payload, _ts) do
    node_id = Map.get(payload, "node_id")
    update_node(vm, node_id, fn n -> %{n | status: "failed"} end)
  end

  defp apply_event_type(vm, "gate_requested", payload, _ts) do
    node_id = Map.get(payload, "node_id")
    update_node(vm, node_id, fn n -> %{n | status: "waiting"} end)
  end

  defp apply_event_type(vm, "gate_resolved", payload, _ts) do
    node_id = Map.get(payload, "node_id")
    update_node(vm, node_id, fn n -> %{n | status: "running"} end)
  end

  defp apply_event_type(vm, _event_type, _payload, _ts), do: vm

  defp extract_summary(payload) do
    summary = payload["warning_summary"] || payload[:warning_summary] || %{}

    wc = summary["warning_count"] || summary[:warning_count] || 0
    ids = summary["degraded_node_ids"] || summary[:degraded_node_ids] || []
    {wc, ids}
  end

  defp update_node(view_model, node_id, fun) when is_binary(node_id) do
    nodes = view_model.nodes

    new_nodes =
      if Enum.find(nodes, fn n -> n.node_id == node_id end) do
        Enum.map(nodes, &apply_to_node(&1, node_id, fun))
      else
        nodes ++ [fun.(%{node_id: node_id, op_name: node_id, status: "pending"})]
      end

    %{view_model | nodes: new_nodes}
  end

  defp update_node(view_model, nil, _fun), do: view_model

  defp apply_to_node(node, node_id, fun) do
    if node.node_id == node_id, do: fun.(node), else: node
  end

  defp derive_status("run_completed"), do: "completed"
  defp derive_status("run_failed"), do: "failed"
  defp derive_status("op_completed"), do: "running"
  defp derive_status("op_started"), do: "running"
  defp derive_status(_), do: "running"

  defp completed_at(%{"event_type" => t, "timestamp" => ts})
       when t in ["run_completed", "run_failed"],
       do: ts

  defp completed_at(_), do: nil

  defp build_nodes(node_events) do
    node_events
    |> Enum.reduce(%{}, fn event, acc ->
      node_id = event["payload"]["node_id"]
      current = Map.get(acc, node_id, %{node_id: node_id, op_name: node_id, status: "pending"})

      updated =
        case event["event_type"] do
          "op_started" ->
            op_name = event["payload"]["op_id"] || node_id
            %{current | op_name: op_name, status: "running"}

          "op_completed" ->
            %{current | status: "completed"}

          "op_failed" ->
            %{current | status: "failed"}

          _ ->
            current
        end

      Map.put(acc, node_id, updated)
    end)
    |> Map.values()
  end

  defp observation_state_to_view_model(obs_state) when is_map(obs_state) do
    nodes =
      obs_state
      |> Map.get(:nodes, %{})
      |> Enum.map(fn {node_id, node} ->
        %{
          node_id: node_id,
          op_name: Map.get(node, :op_name, node_id),
          status: atom_status_to_string(Map.get(node, :status, :pending)),
          degraded: Map.get(node, :degraded, false)
        }
      end)

    %{
      not_found: false,
      run_status: atom_status_to_string(Map.get(obs_state, :run_status, :pending)),
      started_at: Map.get(obs_state, :run_started_at),
      completed_at: Map.get(obs_state, :run_completed_at),
      event_count: Map.get(obs_state, :event_count, 0),
      nodes: nodes,
      warning_count: Map.get(obs_state, :warning_count, 0),
      degraded_nodes: Map.get(obs_state, :degraded_nodes, []),
      degraded: Map.get(obs_state, :degraded, false)
    }
  end

  defp atom_status_to_string(:completed), do: "completed"
  defp atom_status_to_string(:failed), do: "failed"
  defp atom_status_to_string(:running), do: "running"
  defp atom_status_to_string(:waiting), do: "waiting"
  defp atom_status_to_string(:pending), do: "pending"
  defp atom_status_to_string(other), do: to_string(other)

  # ── Inspector helpers ──────────────────────────────────────────

  defp get_node_data(obs_nodes, node_id) do
    Map.get(obs_nodes, node_id)
  end

  defp find_in_view_model(view_model, node_id) do
    Enum.find(view_model.nodes, fn n -> n.node_id == node_id end)
  end

  defp maybe_refresh_node_data(_obs_nodes, nil), do: nil

  defp maybe_refresh_node_data(obs_nodes, node_id) do
    get_node_data(obs_nodes, node_id)
  end

  defp detect_content_type(content) when is_binary(content) do
    cond do
      match?({:ok, _}, Jason.decode(content)) -> :json
      String.valid?(content) -> :text
      true -> :binary
    end
  end

  defp format_json(content) do
    case Jason.decode(content) do
      {:ok, decoded} -> Jason.Formatter.pretty_print(Jason.encode!(decoded))
      _ -> content
    end
  end

  defp format_timeline_ts(nil), do: ""

  defp format_timeline_ts(ts) when is_binary(ts) do
    case String.split(ts, "T") do
      [_date, time] -> String.replace(time, "Z", "")
      _ -> ts
    end
  end

  defp format_timeline_ts(ts), do: to_string(ts)

  defp filter_code_to_type("os"), do: "op_started"
  defp filter_code_to_type("oc"), do: "op_completed"
  defp filter_code_to_type("rs"), do: "run_started"
  defp filter_code_to_type("rc"), do: "run_completed"
  defp filter_code_to_type(other), do: other

  defp format_gate_response(resp) when is_map(resp), do: Jason.encode!(resp)
  defp format_gate_response(resp) when is_binary(resp), do: resp
  defp format_gate_response(resp), do: inspect(resp)

  defp find_waiting_gate(obs_nodes) when map_size(obs_nodes) == 0, do: {nil, nil}

  defp find_waiting_gate(obs_nodes) do
    case Enum.find(obs_nodes, fn {_id, node} -> node[:status] == :waiting end) do
      {node_id, node_data} -> {node_id, node_data}
      nil -> {nil, nil}
    end
  end

  defp truncate_hash("sha256:" <> hex), do: "sha256:#{String.slice(hex, 0, 8)}..."
  defp truncate_hash(hash) when byte_size(hash) > 16, do: String.slice(hash, 0, 16) <> "..."
  defp truncate_hash(hash), do: hash
end
