defmodule LiminaraWeb.RunsLive.Index do
  use LiminaraWeb, :live_view

  @max_recent_runs 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :pg.join(:liminara, :all_runs, self())
    end

    runs =
      if connected?(socket) do
        load_runs_from_store()
      else
        %{}
      end

    {:ok, assign(socket, runs: runs)}
  end

  @impl true
  def handle_info({:run_event, run_id, event}, socket) do
    {:noreply, assign(socket, runs: apply_run_event(socket.assigns.runs, run_id, event))}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("start_demo_run", _params, socket) do
    run_id = "demo-#{System.system_time(:millisecond)}"
    plan = build_demo_plan()
    Liminara.Run.Server.start(run_id, plan, pack_id: "demo_pack", pack_version: "0.1.0")
    {:noreply, push_navigate(socket, to: "/runs/#{run_id}")}
  end

  defp build_demo_plan do
    alias Liminara.{Plan, DemoOps}

    Plan.new()
    |> Plan.add_node("input", DemoOps.Echo, %{"text" => {:literal, "hello world"}})
    |> Plan.add_node("upper", DemoOps.Upcase, %{"text" => {:ref, "input"}})
    |> Plan.add_node("reverse", DemoOps.Reverse, %{"text" => {:ref, "input"}})
    |> Plan.add_node("echo_a", DemoOps.Echo, %{"text" => {:ref, "upper"}})
    |> Plan.add_node("echo_c", DemoOps.Echo, %{"text" => {:ref, "reverse"}})
    |> Plan.add_node("merge", DemoOps.Concat, %{
      "a" => {:ref, "echo_a"},
      "b" => {:ref, "echo_c"}
    })
    |> Plan.add_node("approve", DemoOps.Approve, %{"text" => {:ref, "merge"}})
    |> Plan.add_node("final_upper", DemoOps.Upcase, %{"text" => {:ref, "approve"}})
    |> Plan.add_node("final_reverse", DemoOps.Reverse, %{"text" => {:ref, "approve"}})
    |> Plan.add_node("output", DemoOps.Concat, %{
      "a" => {:ref, "final_upper"},
      "b" => {:ref, "final_reverse"}
    })
  end

  defp apply_run_event(runs, run_id, event) do
    event_type = Map.get(event, "event_type") || Map.get(event, :event_type)
    payload = Map.get(event, "payload") || Map.get(event, :payload) || %{}

    updated_run =
      case Map.get(runs, run_id) do
        nil ->
          pack_id = Map.get(payload, "pack_id", "unknown")
          ts = Map.get(event, "timestamp") || Map.get(event, :timestamp)

          %{
            run_id: run_id,
            pack_id: pack_id,
            status: event_type_to_status(event_type),
            started_at: ts,
            warning_count: warning_count_from_payload(payload),
            degraded: derive_degraded(event_type, payload)
          }

        existing ->
          update_existing_run(existing, event_type, payload)
      end

    Map.put(runs, run_id, updated_run)
  end

  defp update_existing_run(existing, event_type, payload) do
    status = update_status(existing.status, event_type)

    # M-WARN-04 bug_004: assign warning_count directly from the terminal
    # payload (mirroring build_run_summary/3). The payload carries the
    # full aggregate — not a delta — so any re-delivery (mount-race or
    # Run.Server rebuild re-broadcast) would otherwise inflate the count
    # to 2N, 3N, etc. Non-terminal events preserve the existing value.
    updated_warning_count =
      if event_type in ["run_completed", "run_partial", "run_failed"] do
        warning_count_from_payload(payload)
      else
        Map.get(existing, :warning_count, 0)
      end

    updated_degraded =
      derive_degraded(event_type, payload) or Map.get(existing, :degraded, false)

    run = %{
      existing
      | status: status,
        warning_count: updated_warning_count,
        degraded: updated_degraded
    }

    # Failed runs never display as degraded; the failure takes precedence.
    if run.status == "failed", do: %{run | degraded: false}, else: run
  end

  defp warning_count_from_payload(payload) do
    case payload["warning_summary"] do
      %{"warning_count" => n} when is_integer(n) -> n
      _ -> 0
    end
  end

  # M-WARN-04 merged_bug_001: partial-with-warnings is degraded
  # (mirrors the run_completed derivation). run_failed is never degraded.
  defp derive_degraded(event_type, payload)
       when event_type in ["run_completed", "run_partial"] do
    warning_count_from_payload(payload) > 0
  end

  defp derive_degraded(_event_type, _payload), do: false

  @impl true
  def terminate(_reason, _socket) do
    :pg.leave(:liminara, :all_runs, self())
  end

  @impl true
  def render(assigns) do
    sorted_runs =
      assigns.runs
      |> Map.values()
      |> Enum.sort_by(& &1.started_at, :desc)

    assigns = assign(assigns, :sorted_runs, sorted_runs)

    ~H"""
    <div class="page">
      <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:12px;">
        <h1 style="margin-bottom:0;">Runs</h1>
        <button phx-click="start_demo_run" class="filter-btn">Start Demo Run</button>
      </div>
      <%= if @sorted_runs == [] do %>
        <p style="color:var(--dm-muted); font-size:12px;">No runs yet</p>
      <% else %>
        <table style="width:100%; border-collapse:collapse; font-size:12px;">
          <thead>
            <tr style="border-bottom:2px solid var(--dm-border); text-align:left;">
              <th style="padding:8px 12px; color:var(--dm-muted); letter-spacing:0.04em;">Run ID</th>
              <th style="padding:8px 12px; color:var(--dm-muted); letter-spacing:0.04em;">Status</th>
              <th style="padding:8px 12px; color:var(--dm-muted); letter-spacing:0.04em;">Started</th>
              <th style="padding:8px 12px; color:var(--dm-muted); letter-spacing:0.04em;">Pack</th>
            </tr>
          </thead>
          <tbody>
            <%= for run <- @sorted_runs do %>
              <tr style="border-bottom:1px solid var(--dm-border);">
                <td style="padding:8px 12px;">
                  <.link
                    navigate={~p"/runs/#{run.run_id}"}
                    style="color:var(--dm-ink); text-decoration:none;"
                  >
                    {run.run_id}
                  </.link>
                </td>
                <td style="padding:8px 12px;">
                  <span class={"status status--#{run.status}"}>{run.status}</span>
                  <%= if Map.get(run, :degraded, false) do %>
                    <span class="status status--degraded" title="Completed with warnings">
                      degraded ({Map.get(run, :warning_count, 0)})
                    </span>
                  <% end %>
                </td>
                <td style="padding:8px 12px; color:var(--dm-muted);">
                  {format_timestamp(run.started_at)}
                </td>
                <td style="padding:8px 12px; color:var(--dm-muted);">
                  {run.pack_id}
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  defp format_timestamp(nil), do: "—"

  defp format_timestamp(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
      _ -> ts
    end
  end

  defp format_timestamp(ts), do: to_string(ts)

  defp load_runs_from_store do
    runs_root = get_runs_root()

    case :file.list_dir(runs_root) do
      {:ok, names} ->
        names
        |> Enum.map(&List.to_string/1)
        |> Enum.map(fn name ->
          path = Path.join([runs_root, name, "events.jsonl"])
          {name, events_mtime(path)}
        end)
        |> Enum.filter(fn {_n, m} -> m > 0 end)
        |> Enum.sort_by(fn {_n, m} -> m end, :desc)
        |> Enum.take(@max_recent_runs)
        |> Enum.map(fn {run_id, _} -> load_run_summary(runs_root, run_id) end)
        |> Enum.reject(&is_nil/1)
        |> Map.new(fn run -> {run.run_id, run} end)

      _ ->
        %{}
    end
  end

  defp load_run_summary(runs_root, run_id) do
    path = Path.join([runs_root, run_id, "events.jsonl"])

    case read_first_and_last_line(path) do
      {nil, nil} -> nil
      {first_line, last_line} -> build_run_summary(run_id, first_line, last_line)
    end
  end

  defp build_run_summary(run_id, first_line, last_line) do
    first = Jason.decode!(first_line)
    pack_id = get_in(first, ["payload", "pack_id"]) || "unknown"

    # Only show runs that begin with run_started — skip test artifacts
    if first["event_type"] != "run_started" or not real_run?(run_id, pack_id) do
      nil
    else
      last = if last_line == first_line, do: first, else: Jason.decode!(last_line)
      status = event_type_to_status(last["event_type"])
      warning_count = warning_count_from_payload(last["payload"] || %{})
      # M-WARN-04 merged_bug_001: partial runs with warnings are degraded.
      degraded = status in ["completed", "partial"] and warning_count > 0

      %{
        run_id: run_id,
        pack_id: pack_id,
        status: status,
        started_at: first["timestamp"],
        warning_count: warning_count,
        degraded: degraded
      }
    end
  end

  defp read_first_and_last_line(path) do
    case File.read(path) do
      {:ok, content} ->
        lines = content |> String.trim() |> String.split("\n") |> Enum.reject(&(&1 == ""))

        case lines do
          [] -> {nil, nil}
          [only] -> {only, only}
          _ -> {List.first(lines), List.last(lines)}
        end

      _ ->
        {nil, nil}
    end
  end

  defp events_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, stat} -> stat.mtime
      _ -> 0
    end
  end

  defp get_runs_root do
    Application.get_env(:liminara_core, :runs_root) ||
      Path.join(System.tmp_dir!(), "liminara_runs")
  end

  defp event_type_to_status("run_completed"), do: "completed"
  defp event_type_to_status("run_partial"), do: "partial"
  defp event_type_to_status("run_failed"), do: "failed"
  defp event_type_to_status(_), do: "running"

  defp update_status(_current, "run_completed"), do: "completed"
  defp update_status(_current, "run_partial"), do: "partial"
  defp update_status(_current, "run_failed"), do: "failed"
  defp update_status(current, _), do: current

  # Only show intentional runs (demo, manual, pack-initiated).
  # Test artifacts use short prefixes with numeric suffixes — exclude by default.
  # A run is considered "real" if its pack_id isn't "anonymous", or its ID
  # starts with a known prefix. This avoids maintaining a blocklist of test prefixes.
  @real_prefixes ~w(demo- run- radar- report- house- factory- software-)

  defp real_run?(run_id, pack_id) do
    pack_id != "anonymous" or Enum.any?(@real_prefixes, &String.starts_with?(run_id, &1))
  end
end
