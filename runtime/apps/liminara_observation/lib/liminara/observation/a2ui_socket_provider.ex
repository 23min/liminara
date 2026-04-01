defmodule Liminara.Observation.A2UISocketProvider do
  @moduledoc false

  # A2UISocketProvider implements the A2UI.SurfaceProvider behaviour for WebSocket
  # connections. It wraps A2UIProvider (the functional core) and adapts its
  # return values to the OTP-compliant A2UI.SurfaceProvider contract.
  #
  # On connect, it resolves the run_id from query_params, looks up the running
  # Observation.Server via :pg to fetch the plan, then initialises A2UIProvider.
  #
  # The surface/1 callback converts A2UIProvider's list of plain maps to an
  # A2UI.Surface.t() by wrapping each map in an A2UI.Component struct.
  #
  # handle_info/2 converts {:update, state} → {:push_surface, surface, state}
  # so the WebSocket layer pushes a fresh surface to the client.

  @behaviour A2UI.SurfaceProvider

  alias Liminara.Observation.{A2UIProvider, Server}

  defstruct [:run_id, :provider_state]

  # ── init/1 ───────────────────────────────────────────────────────────────

  @impl A2UI.SurfaceProvider
  def init(%{query_params: %{"run_id" => run_id}} = _opts) do
    case resolve_state(run_id) do
      {:ok, plan, current_view} ->
        {:ok, provider_state} = A2UIProvider.init(run_id: run_id, plan: plan)
        # Update with current view state from the running Observation.Server
        provider_state = %{provider_state | view_state: current_view}
        {:ok, %__MODULE__{run_id: run_id, provider_state: provider_state}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def init(%{query_params: params}) do
    {:error, {:missing_run_id, params}}
  end

  def init(_opts) do
    {:error, :missing_query_params}
  end

  # ── surface/1 ────────────────────────────────────────────────────────────

  @impl A2UI.SurfaceProvider
  def surface(%__MODULE__{run_id: run_id, provider_state: provider_state}) do
    components = A2UIProvider.surface(provider_state)
    build_surface(run_id, components)
  end

  # ── handle_action/2 ──────────────────────────────────────────────────────

  @impl A2UI.SurfaceProvider
  def handle_action(%A2UI.Action{} = action, %__MODULE__{} = state) do
    case A2UIProvider.handle_action(action, state.provider_state) do
      {:ok, new_provider_state} ->
        {:noreply, %{state | provider_state: new_provider_state}}
    end
  end

  # ── handle_info/2 ────────────────────────────────────────────────────────

  @impl A2UI.SurfaceProvider
  def handle_info(msg, %__MODULE__{} = state) do
    case A2UIProvider.handle_info(msg, state.provider_state) do
      {:update, new_provider_state} ->
        new_state = %{state | provider_state: new_provider_state}
        {:push_surface, surface(new_state), new_state}

      {:ok, new_provider_state} ->
        {:noreply, %{state | provider_state: new_provider_state}}
    end
  end

  # ── Private helpers ──────────────────────────────────────────────────────

  defp resolve_state(run_id) do
    members = :pg.get_members(:liminara, {:run, run_id})

    obs_pid =
      Enum.find(members, fn pid ->
        case :erlang.process_info(pid, :dictionary) do
          {:dictionary, dict} ->
            initial_call = Keyword.get(dict, :"$initial_call")
            initial_call == {Server, :init, 1}

          _ ->
            false
        end
      end)

    case obs_pid do
      nil ->
        {:error, {:no_observation_server, run_id}}

      pid ->
        view = Server.get_state(pid)
        {:ok, view.plan, view}
    end
  end

  defp build_surface(run_id, component_maps) do
    alias A2UI.{Builder, Surface, Action}

    surface = Surface.new("run-#{run_id}")

    # Build the component tree using the pipe-based Builder API
    surface =
      Enum.reduce(component_maps, surface, fn comp_map, s ->
        build_components(s, comp_map)
      end)

    # Collect top-level component IDs (Card/Form) for the root column
    top_ids =
      Enum.map(component_maps, fn map -> map["id"] end)

    surface
    |> Builder.column("root", children: top_ids)
    |> Surface.set_root("root")
  end

  # Status card: Card with Text children for run info
  defp build_components(surface, %{"type" => "Card", "id" => id} = map) do
    alias A2UI.Builder

    surface
    |> Builder.text("#{id}-run", "Run: #{map["run_id"]}")
    |> Builder.text("#{id}-status", "Status: #{map["status"]}")
    |> Builder.text("#{id}-progress", map["progress"])
    |> Builder.card(id,
      title: "Run Status",
      children: ["#{id}-run", "#{id}-status", "#{id}-progress"]
    )
  end

  # Node list: Card with Text children per node
  defp build_components(surface, %{"type" => "List", "id" => id} = map) do
    alias A2UI.Builder

    items = map["items"] || []

    {surface, child_ids} =
      Enum.with_index(items)
      |> Enum.reduce({surface, []}, fn {item, i}, {s, ids} ->
        icon =
          case item["status"] do
            "completed" -> "✓"
            "running" -> "▶"
            "waiting" -> "⏸"
            "failed" -> "✗"
            _ -> "○"
          end

        child_id = "#{id}-item-#{i}"
        s = Builder.text(s, child_id, "#{icon}  #{item["op_name"]} — #{item["status"]}")
        {s, ids ++ [child_id]}
      end)

    Builder.card(surface, id, title: "Nodes", children: child_ids)
  end

  # Gate form: Card with prompt Text + Approve/Reject Buttons
  defp build_components(surface, %{"type" => "Form", "id" => id} = map) do
    alias A2UI.{Builder, Action}

    node_id = map["node_id"]

    surface
    |> Builder.text("#{id}-prompt", map["prompt"] || "Approve?")
    |> Builder.button("#{id}-approve", "Approve",
      action: %Action{name: "approve", context: %{"node_id" => node_id}}
    )
    |> Builder.button("#{id}-reject", "Reject",
      action: %Action{name: "reject", context: %{"node_id" => node_id}}
    )
    |> Builder.row("#{id}-buttons", children: ["#{id}-approve", "#{id}-reject"])
    |> Builder.card(id,
      title: "Gate: #{node_id}",
      children: ["#{id}-prompt", "#{id}-buttons"]
    )
  end

  defp build_components(surface, _unknown), do: surface
end
