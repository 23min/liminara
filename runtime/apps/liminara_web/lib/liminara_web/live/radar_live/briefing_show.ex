defmodule LiminaraWeb.RadarLive.BriefingShow do
  use LiminaraWeb, :live_view

  alias Liminara.{Artifact, Decision, Event}

  @impl true
  def mount(%{"run_id" => run_id}, _session, socket) do
    briefing_data =
      if connected?(socket) do
        load_briefing(run_id)
      else
        nil
      end

    {:ok,
     assign(socket,
       run_id: run_id,
       briefing: briefing_data[:briefing],
       html_content: briefing_data[:html_content],
       source_health: briefing_data[:source_health] || [],
       meta: briefing_data[:meta] || %{},
       found: briefing_data != nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="page">
      <nav>
        <a href="/radar/briefings">&larr; briefings</a>
      </nav>

      <%= if !@found do %>
        <p style="color:var(--dm-muted); font-size:12px;">Briefing not found</p>
      <% else %>
        <h1 style="margin-bottom:8px;">Briefing {@run_id}</h1>

        <div class="run-meta">
          <dl>
            <dt>Date</dt>
            <dd>{@meta[:date] || "—"}</dd>
          </dl>
          <dl>
            <dt>Items</dt>
            <dd>{@meta[:item_count] || 0}</dd>
          </dl>
          <dl>
            <dt>Clusters</dt>
            <dd>{@meta[:cluster_count] || 0}</dd>
          </dl>
          <dl>
            <dt>Sources</dt>
            <dd>{@meta[:source_count] || 0}</dd>
          </dl>
          <dl>
            <dt>Duration</dt>
            <dd>{@meta[:duration] || "—"}</dd>
          </dl>
        </div>

        <div style="margin-bottom:16px;">
          <a href={"/runs/#{@run_id}"} style="font-size:11px; color:var(--dm-muted); text-decoration:none; letter-spacing:0.04em;">
            View full run details &rarr;
          </a>
        </div>

        <%= if @source_health != [] do %>
          <details style="margin-bottom:16px;">
            <summary style="font-size:11px; color:var(--dm-muted); cursor:pointer; letter-spacing:0.04em;">
              Source Health ({length(@source_health)} sources)
            </summary>
            <table style="width:100%; border-collapse:collapse; font-size:11px; margin-top:8px;">
              <thead>
                <tr style="border-bottom:1px solid var(--dm-border); text-align:left;">
                  <th style="padding:4px 8px; color:var(--dm-muted);">Source</th>
                  <th style="padding:4px 8px; color:var(--dm-muted);">Items</th>
                  <th style="padding:4px 8px; color:var(--dm-muted);">Status</th>
                </tr>
              </thead>
              <tbody>
                <%= for src <- @source_health do %>
                  <tr style="border-bottom:1px solid var(--dm-border);">
                    <td style="padding:4px 8px;">{src["source_id"]}</td>
                    <td style="padding:4px 8px;">{src["items_fetched"] || 0}</td>
                    <td style="padding:4px 8px;">
                      <%= if src["error"] do %>
                        <span style="color:#c62828;">{src["error"]}</span>
                      <% else %>
                        <span style="color:#2e7d32;">ok</span>
                      <% end %>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </details>
        <% end %>

        <%= if @html_content do %>
          <div style="border:1px solid var(--dm-border); padding:16px; border-radius:4px;">
            {Phoenix.HTML.raw(@html_content)}
          </div>
        <% end %>
      <% end %>
    </div>
    """
  end

  defp load_briefing(run_id) do
    runs_root = get_runs_root()
    store_root = get_store_root()

    case Event.Store.read_all(runs_root, run_id) do
      {:ok, []} ->
        nil

      {:ok, events} ->
        first = List.first(events)
        last = List.last(events)

        briefing_json = get_artifact(runs_root, store_root, run_id, "compose_briefing", "briefing")
        html_content = get_artifact(runs_root, store_root, run_id, "render_html", "html")

        briefing = if briefing_json, do: Jason.decode!(briefing_json), else: nil
        stats = (briefing && briefing["stats"]) || %{}
        source_health = (briefing && briefing["source_health"]) || []

        %{
          briefing: briefing,
          html_content: html_content,
          source_health: source_health,
          meta: %{
            date: extract_date(first["timestamp"]),
            item_count: stats["item_count"] || 0,
            cluster_count: stats["cluster_count"] || 0,
            source_count: stats["source_count"] || 0,
            duration: compute_duration(first["timestamp"], last["timestamp"])
          }
        }
    end
  end

  defp get_artifact(runs_root, store_root, run_id, node_id, output_key) do
    case Decision.Store.get_outputs(runs_root, run_id, node_id) do
      {:ok, hashes} ->
        hash = Map.get(hashes, output_key)

        case hash && Artifact.Store.get(store_root, hash) do
          {:ok, content} -> content
          _ -> nil
        end

      _ ->
        nil
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
end
