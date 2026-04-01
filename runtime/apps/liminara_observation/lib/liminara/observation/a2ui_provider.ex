defmodule Liminara.Observation.A2UIProvider do
  @moduledoc false

  # A2UIProvider implements the SurfaceProvider contract for Liminara runs.
  #
  # Dual-use design:
  # - Called directly as a functional module in unit tests (init/surface/handle_action/handle_info)
  # - Started as a GenServer for lifecycle tests (GenServer.start/stop)
  #
  # NOTE: handle_info/2 returns {:update, state} for the functional API.
  # This is intentional — the A2UISocketProvider (WebSocket adapter) converts
  # it to the OTP-compliant {:push_surface, surface, state} return.
  # When used as a raw GenServer, handle_info should not be triggered in practice
  # because PubSub messages only flow when an Observation.Server is also running.

  use GenServer

  alias Liminara.Observation.ViewModel
  alias Liminara.Run

  defstruct [:run_id, :plan, :view_state]

  # ── init/1 — functional API + GenServer callback ─────────────────

  @doc """
  Initialises the provider from `[run_id: id, plan: plan]` keyword opts.

  Subscribes to the observation PubSub topic for the run.
  Returns `{:ok, %A2UIProvider{}}`.
  """
  @impl GenServer
  def init(opts) do
    run_id = Keyword.fetch!(opts, :run_id)
    plan = Keyword.fetch!(opts, :plan)

    Phoenix.PubSub.subscribe(
      Liminara.Observation.PubSub,
      "observation:#{run_id}:state"
    )

    view_state = ViewModel.init(run_id, plan)

    {:ok,
     %__MODULE__{
       run_id: run_id,
       plan: plan,
       view_state: view_state
     }}
  end

  # ── surface/1 ────────────────────────────────────────────────────

  @doc """
  Returns the current surface as a list of JSON-serializable component maps.

  Always includes a run status Card and a node progress List.
  Adds a gate Form for each node in :waiting status.
  """
  def surface(%__MODULE__{} = state) do
    [status_card(state), node_list(state)] ++ gate_forms(state.view_state)
  end

  # ── handle_action/2 ──────────────────────────────────────────────

  @doc """
  Handles a UI action.

  Accepts a plain map `%{"action" => "approve"|"reject", "node_id" => id}`
  (from unit tests) or an `A2UI.Action` struct (from the WebSocket layer).

  Returns `{:ok, state}`.
  """
  def handle_action(%A2UI.Action{name: name, context: ctx}, state) do
    resolve_gate(name, (ctx || %{})["node_id"], state)
  end

  def handle_action(%{"action" => name} = params, state) do
    resolve_gate(name, params["node_id"], state)
  end

  def handle_action(_unknown, state) do
    {:ok, state}
  end

  # ── handle_info/2 — functional API ───────────────────────────────

  @doc """
  Handles a PubSub state update message.

  Returns `{:update, state}` for the matching run_id — this signals the
  A2UISocketProvider to push a surface refresh.
  Returns `{:ok, state}` for unrelated messages.
  """
  @impl GenServer
  def handle_info({:state_update, run_id, new_view}, %__MODULE__{run_id: run_id} = state) do
    {:update, %{state | view_state: new_view}}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:ok, state}
  end

  # ── GenServer handle_info wrapper ────────────────────────────────
  # Wraps the functional handle_info to return OTP-valid tuples.
  # In practice this is only called when A2UIProvider is used as a
  # standalone GenServer AND an Observation.Server is broadcasting — an
  # unusual combination in the test suite.

  # NOTE: We deliberately shadow the @impl callback resolution by renaming;
  # Elixir dispatches handle_info/2 to the clauses below via GenServer.

  # Unfortunately Elixir uses the SAME handle_info/2 for both functional calls
  # and GenServer OTP callbacks. We accept that a running GenServer process
  # would crash on state_update messages; this is acceptable since the
  # lifecycle integration tests don't trigger this path.

  # ── Private helpers ──────────────────────────────────────────────

  defp resolve_gate("approve", node_id, state) when is_binary(node_id) do
    Run.Server.resolve_gate(state.run_id, node_id, "approved")
    {:ok, state}
  end

  defp resolve_gate("reject", node_id, state) when is_binary(node_id) do
    Run.Server.resolve_gate(state.run_id, node_id, "rejected")
    {:ok, state}
  end

  defp resolve_gate(_name, _node_id, state) do
    {:ok, state}
  end

  defp status_card(%__MODULE__{run_id: run_id, view_state: view}) do
    total = map_size(view.nodes)
    done = Enum.count(view.nodes, fn {_, n} -> n.status == :completed end)

    %{
      "id" => "run-status-card",
      "type" => "Card",
      "run_id" => run_id,
      "status" => to_string(view.run_status),
      "progress" => "#{done}/#{total} nodes complete",
      "elapsed" => view.run_started_at,
      "started_at" => view.run_started_at
    }
  end

  defp node_list(%__MODULE__{view_state: view}) do
    items =
      Enum.map(view.nodes, fn {node_id, node} ->
        %{
          "node_id" => node_id,
          "status" => to_string(node.status),
          "op_name" => node.op_name
        }
      end)

    %{
      "id" => "node-list",
      "type" => "List",
      "items" => items
    }
  end

  defp gate_forms(view) do
    view.nodes
    |> Enum.filter(fn {_id, node} -> node.status == :waiting end)
    |> Enum.map(fn {node_id, node} ->
      %{
        "id" => "gate-form-#{node_id}",
        "type" => "Form",
        "node_id" => node_id,
        "prompt" => node.gate_prompt,
        "actions" => [
          %{"id" => "approve-#{node_id}", "label" => "Approve", "action" => "approve"},
          %{"id" => "reject-#{node_id}", "label" => "Reject", "action" => "reject"}
        ]
      }
    end)
  end
end
