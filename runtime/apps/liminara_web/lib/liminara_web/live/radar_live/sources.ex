defmodule LiminaraWeb.RadarLive.Sources do
  use LiminaraWeb, :live_view

  alias Liminara.{Artifact, Decision, Event}
  alias Liminara.Radar.Config

  @max_health_runs 7

  @impl true
  def mount(_params, _session, socket) do
    {sources, health_history} =
      if connected?(socket) do
        {load_sources(), load_health_history()}
      else
        {[], %{}}
      end

    enriched = enrich_sources(sources, health_history)

    {:ok, assign(socket, sources: enriched, sources_path: get_sources_path())}
  end

  @impl true
  def handle_event("toggle_enabled", %{"id" => source_id}, socket) do
    path = socket.assigns.sources_path
    {:ok, raw_sources} = Config.load(path)

    updated =
      Enum.map(raw_sources, fn src ->
        if src["id"] == source_id do
          Map.put(src, "enabled", !src["enabled"])
        else
          src
        end
      end)

    content = Enum.map_join(updated, "\n", &Jason.encode!/1)
    File.write!(path, content)

    health_history = load_health_history()
    enriched = enrich_sources(updated, health_history)

    {:noreply, assign(socket, sources: enriched)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="page">
      <nav><a href="/radar/briefings">&larr; briefings</a></nav>
      <h1>Sources</h1>
      <%= if @sources == [] do %>
        <p style="color:var(--dm-muted); font-size:12px;">No sources configured</p>
      <% else %>
        <table style="width:100%; border-collapse:collapse; font-size:12px;">
          <thead>
            <tr style="border-bottom:2px solid var(--dm-border); text-align:left;">
              <th style="padding:8px 12px; color:var(--dm-muted);">Name</th>
              <th style="padding:8px 12px; color:var(--dm-muted);">Type</th>
              <th style="padding:8px 12px; color:var(--dm-muted);">Tags</th>
              <th style="padding:8px 12px; color:var(--dm-muted);">Status</th>
              <th style="padding:8px 12px; color:var(--dm-muted);">Last Items</th>
              <th style="padding:8px 12px; color:var(--dm-muted);">Avg (7 runs)</th>
              <th style="padding:8px 12px; color:var(--dm-muted);">Action</th>
            </tr>
          </thead>
          <tbody>
            <%= for src <- @sources do %>
              <tr style={"border-bottom:1px solid var(--dm-border);#{if src.inactive?, do: " background: #fff3e0;", else: ""}"}>
                <td style="padding:8px 12px;">
                  {src.name}
                  <%= if src.inactive? do %>
                    <span style="font-size:10px; color:#e65100; margin-left:4px;">(inactive — cull candidate)</span>
                  <% end %>
                </td>
                <td style="padding:8px 12px; color:var(--dm-muted);">{src.type}</td>
                <td style="padding:8px 12px; color:var(--dm-muted);">{Enum.join(src.tags, ", ")}</td>
                <td style="padding:8px 12px;">
                  <%= if src.enabled do %>
                    <span style="color:#2e7d32;">enabled</span>
                  <% else %>
                    <span style="color:#c62828;">disabled</span>
                  <% end %>
                </td>
                <td style="padding:8px 12px;">{src.last_items}</td>
                <td style="padding:8px 12px;">{src.avg_items}</td>
                <td style="padding:8px 12px;">
                  <button
                    phx-click="toggle_enabled"
                    phx-value-id={src.id}
                    style="font-size:10px; cursor:pointer; border:1px solid var(--dm-border); background:none; padding:2px 8px; border-radius:3px;"
                  >
                    <%= if src.enabled, do: "Disable", else: "Enable" %>
                  </button>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
    """
  end

  defp load_sources do
    path = get_sources_path()

    case Config.load(path) do
      {:ok, sources} -> sources
      _ -> []
    end
  end

  defp load_health_history do
    runs_root = get_runs_root()
    store_root = get_store_root()

    run_ids =
      Event.Store.list_run_ids(runs_root)
      |> Enum.filter(&String.starts_with?(&1, "radar-"))
      |> Enum.sort(:desc)
      |> Enum.take(@max_health_runs)

    Enum.reduce(run_ids, %{}, fn run_id, acc ->
      case extract_source_health(runs_root, store_root, run_id) do
        nil -> acc
        health ->
          Enum.reduce(health, acc, fn entry, a ->
            sid = entry["source_id"]
            items = entry["items_fetched"] || 0
            Map.update(a, sid, [items], &[items | &1])
          end)
      end
    end)
  end

  defp extract_source_health(runs_root, store_root, run_id) do
    case Decision.Store.get_outputs(runs_root, run_id, "collect_items") do
      {:ok, %{"source_health" => hash}} ->
        case Artifact.Store.get(store_root, hash) do
          {:ok, json} -> Jason.decode!(json)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp enrich_sources(sources, health_history) do
    sources
    |> Enum.map(fn src ->
      id = src["id"]
      history = Map.get(health_history, id, [])
      last_items = List.first(history) || 0
      avg_items = if history == [], do: 0, else: Float.round(Enum.sum(history) / length(history), 1)
      run_count = length(history)
      inactive? = run_count >= 7 and Enum.all?(history, &(&1 == 0))

      %{
        id: id,
        name: src["name"],
        type: src["type"],
        tags: src["tags"] || [],
        enabled: src["enabled"],
        last_items: last_items,
        avg_items: avg_items,
        inactive?: inactive?
      }
    end)
    |> Enum.sort_by(fn s -> {-s.last_items, s.name} end)
  end

  defp get_sources_path do
    Application.get_env(:liminara_radar, :sources_path) ||
      Application.app_dir(:liminara_radar, "priv/sources.jsonl")
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
