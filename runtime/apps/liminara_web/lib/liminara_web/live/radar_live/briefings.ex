defmodule LiminaraWeb.RadarLive.Briefings do
  use LiminaraWeb, :live_view

  alias Liminara.{Artifact, Decision, Event}
  alias Liminara.Radar.Scheduler

  @impl true
  def mount(_params, _session, socket) do
    briefings =
      if connected?(socket) do
        load_briefings()
      else
        []
      end

    scheduler = get_scheduler_status()

    {:ok, assign(socket, briefings: briefings, scheduler: scheduler)}
  end

  @impl true
  def handle_event("run_now", _params, socket) do
    case get_scheduler_pid() do
      nil -> :noop
      pid -> Scheduler.run_now(pid)
    end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="page">
      <nav><a href="/runs">&larr; runs</a></nav>
      <h1>Briefings</h1>

      <%= if @scheduler do %>
        <div style="font-size:11px; color:var(--dm-muted); margin-bottom:16px; padding:8px 12px; border:1px solid var(--dm-border); border-radius:4px; display:flex; justify-content:space-between; align-items:center;">
          <span>
            Scheduler: Next run at {format_scheduler_time(@scheduler.next_run_at)}
            <%= if @scheduler.last_run_at do %>
              · Last run {format_scheduler_time(@scheduler.last_run_at)}
            <% end %>
          </span>
          <button phx-click="run_now" style="font-size:10px; cursor:pointer; border:1px solid var(--dm-border); background:none; padding:2px 8px; border-radius:3px;">
            Run now
          </button>
        </div>
      <% end %>
      <%= if @briefings == [] do %>
        <p style="color:var(--dm-muted); font-size:12px;">No briefings yet</p>
      <% else %>
        <table style="width:100%; border-collapse:collapse; font-size:12px;">
          <thead>
            <tr style="border-bottom:2px solid var(--dm-border); text-align:left;">
              <th style="padding:8px 12px; color:var(--dm-muted);">Run</th>
              <th style="padding:8px 12px; color:var(--dm-muted);">Status</th>
              <th style="padding:8px 12px; color:var(--dm-muted);">Date</th>
              <th style="padding:8px 12px; color:var(--dm-muted);">Items</th>
              <th style="padding:8px 12px; color:var(--dm-muted);">Clusters</th>
              <th style="padding:8px 12px; color:var(--dm-muted);">Duration</th>
            </tr>
          </thead>
          <tbody>
            <%= for b <- @briefings do %>
              <tr style="border-bottom:1px solid var(--dm-border);">
                <td style="padding:8px 12px;">
                  <.link navigate={~p"/radar/briefings/#{b.run_id}"} style="color:var(--dm-ink); text-decoration:none;">
                    {b.run_id}
                  </.link>
                </td>
                <td style="padding:8px 12px;">
                  <span class={"status status--#{b.status}"}>{b.status}</span>
                </td>
                <td style="padding:8px 12px; color:var(--dm-muted);">{b.date}</td>
                <td style="padding:8px 12px;">{b.item_count}</td>
                <td style="padding:8px 12px;">{b.cluster_count}</td>
                <td style="padding:8px 12px; color:var(--dm-muted);">{b.duration || "—"}</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  defp load_briefings do
    runs_root = get_runs_root()
    store_root = get_store_root()

    run_ids = Event.Store.list_run_ids(runs_root)

    run_ids
    |> Enum.filter(&String.starts_with?(&1, "radar-"))
    |> Enum.map(fn run_id -> load_briefing_summary(runs_root, store_root, run_id) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(&(&1.run_id), :desc)
  end

  defp load_briefing_summary(runs_root, store_root, run_id) do
    case Event.Store.read_all(runs_root, run_id) do
      {:ok, []} ->
        nil

      {:ok, events} ->
        first = List.first(events)
        last = List.last(events)

        status =
          case last["event_type"] do
            "run_completed" -> "completed"
            "run_failed" -> "failed"
            _ -> "running"
          end

        duration = compute_duration(first["timestamp"], last["timestamp"])
        briefing_meta = extract_briefing_meta(run_id, store_root)

        %{
          run_id: run_id,
          status: status,
          date: extract_date(first["timestamp"]),
          item_count: briefing_meta[:item_count] || 0,
          cluster_count: briefing_meta[:cluster_count] || 0,
          source_count: briefing_meta[:source_count] || 0,
          duration: duration
        }
    end
  end

  defp extract_briefing_meta(run_id, store_root) do
    runs_root = get_runs_root()

    hash = get_output_hash(runs_root, run_id, "compose_briefing", "briefing")

    case hash && Artifact.Store.get(store_root, hash) do
      {:ok, json} ->
        briefing = Jason.decode!(json)
        stats = briefing["stats"] || %{}

        %{
          item_count: stats["item_count"] || 0,
          cluster_count: stats["cluster_count"] || 0,
          source_count: stats["source_count"] || 0
        }

      _ ->
        %{}
    end
  end

  defp get_output_hash(runs_root, run_id, node_id, output_key) do
    case Decision.Store.get_outputs(runs_root, run_id, node_id) do
      {:ok, hashes} -> Map.get(hashes, output_key)
      _ -> nil
    end
  end

  defp extract_date(nil), do: "—"

  defp extract_date(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> Calendar.strftime(dt, "%Y-%m-%d %H:%M")
      _ -> ts
    end
  end

  defp compute_duration(nil, _), do: nil
  defp compute_duration(_, nil), do: nil

  defp compute_duration(start_ts, end_ts) do
    with {:ok, s, _} <- DateTime.from_iso8601(start_ts),
         {:ok, e, _} <- DateTime.from_iso8601(end_ts) do
      diff = DateTime.diff(e, s, :second)

      cond do
        diff < 60 -> "#{diff}s"
        diff < 3600 -> "#{div(diff, 60)}m #{rem(diff, 60)}s"
        true -> "#{div(diff, 3600)}h #{div(rem(diff, 3600), 60)}m"
      end
    else
      _ -> nil
    end
  end

  defp get_runs_root do
    Application.get_env(:liminara_core, :runs_root) ||
      Path.join(System.tmp_dir!(), "liminara_runs")
  end

  defp get_store_root do
    Application.get_env(:liminara_core, :store_root) ||
      Path.join(System.tmp_dir!(), "liminara_store")
  end

  defp get_scheduler_pid do
    # Check explicit config first (for tests), then named process
    case Application.get_env(:liminara_radar, :scheduler_pid) do
      nil ->
        case Process.whereis(Liminara.Radar.Scheduler) do
          nil -> nil
          pid -> pid
        end

      pid ->
        pid
    end
  end

  defp get_scheduler_status do
    case get_scheduler_pid() do
      nil ->
        nil

      pid ->
        if Process.alive?(pid) do
          %{
            next_run_at: Scheduler.next_run_at(pid),
            last_run_at: Scheduler.last_run_at(pid)
          }
        else
          nil
        end
    end
  end

  defp format_scheduler_time(nil), do: "—"

  defp format_scheduler_time(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end
end
