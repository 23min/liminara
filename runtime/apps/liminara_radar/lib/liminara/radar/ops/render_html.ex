defmodule Liminara.Radar.Ops.RenderHtml do
  @behaviour Liminara.Op

  alias Liminara.Radar.Ops.Specs

  @impl true
  def name, do: "render_html"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execution_spec do
    Specs.inline(name(), version(), :pure, outputs: %{html: :artifact})
  end

  @impl true
  def execute(inputs) do
    briefing = Jason.decode!(inputs["briefing"])
    html = render(briefing)
    {:ok, %{"html" => html}}
  end

  defp render(briefing) do
    clusters = briefing["clusters"] || []
    stats = briefing["stats"] || %{}
    source_health = briefing["source_health"] || []

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Radar Briefing — #{esc(briefing["date"])}</title>
    <style>
    #{css()}
    </style>
    </head>
    <body>
    <div class="container">
    #{render_header(briefing, stats)}
    #{render_clusters(clusters)}
    #{render_source_health(source_health)}
    #{render_footer(briefing)}
    </div>
    </body>
    </html>
    """
  end

  defp render_header(briefing, stats) do
    """
    <header>
    <h1>Radar Briefing</h1>
    <p class="date">#{esc(briefing["date"])}</p>
    <p class="stats">#{stats["cluster_count"] || 0} clusters &middot; #{stats["item_count"] || 0} items &middot; #{stats["source_count"] || 0} sources</p>
    </header>
    """
  end

  defp render_clusters([]) do
    """
    <section class="no-items">
    <p>No items found in this run.</p>
    </section>
    """
  end

  defp render_clusters(clusters) do
    clusters
    |> Enum.map(&render_cluster/1)
    |> Enum.join("\n")
  end

  defp render_cluster(cluster) do
    items_html =
      (cluster["items"] || [])
      |> Enum.map(&render_item/1)
      |> Enum.join("\n")

    takeaways_html =
      (cluster["key_takeaways"] || [])
      |> Enum.map(fn t -> "<li>#{esc(t)}</li>" end)
      |> Enum.join("\n")

    """
    <section class="cluster">
    <h2>#{esc(cluster["label"])}</h2>
    <div class="summary">#{esc(cluster["summary"] || "")}</div>
    #{if takeaways_html != "", do: "<ul class=\"takeaways\">#{takeaways_html}</ul>", else: ""}
    <div class="items">
    #{items_html}
    </div>
    </section>
    """
  end

  defp render_item(item) do
    """
    <div class="item">
    <a href="#{esc(item["url"] || "#")}" target="_blank">#{esc(item["title"] || "Untitled")}</a>
    <span class="source">#{esc(item["source_id"] || "")}</span>
    </div>
    """
  end

  defp render_source_health([]), do: ""

  defp render_source_health(health) do
    rows =
      health
      |> Enum.map(fn h ->
        status = if h["error"], do: "&#x274C; #{esc(h["error"])}", else: "&#x2705;"

        "<tr><td>#{esc(h["source_id"] || "")}</td><td>#{h["items_fetched"] || 0}</td><td>#{status}</td></tr>"
      end)
      |> Enum.join("\n")

    """
    <section class="source-health">
    <h2>Source Health</h2>
    <table>
    <thead><tr><th>Source</th><th>Items</th><th>Status</th></tr></thead>
    <tbody>#{rows}</tbody>
    </table>
    </section>
    """
  end

  defp render_footer(briefing) do
    """
    <footer>
    <p>Run: #{esc(briefing["run_id"] || "")}</p>
    </footer>
    """
  end

  defp esc(nil), do: ""

  defp esc(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp esc(other), do: esc(to_string(other))

  defp css do
    """
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #1a1a2e; background: #f8f9fa; }
    .container { max-width: 800px; margin: 0 auto; padding: 2rem 1rem; }
    header { margin-bottom: 2rem; border-bottom: 2px solid #e0e0e0; padding-bottom: 1rem; }
    h1 { font-size: 1.8rem; font-weight: 700; }
    .date { font-size: 1.1rem; color: #555; }
    .stats { font-size: 0.9rem; color: #777; }
    .cluster { margin-bottom: 2rem; padding: 1.5rem; background: #fff; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
    .cluster h2 { font-size: 1.3rem; margin-bottom: 0.5rem; color: #16213e; }
    .summary { margin-bottom: 0.75rem; color: #333; }
    .takeaways { margin: 0.5rem 0 1rem 1.5rem; color: #444; }
    .takeaways li { margin-bottom: 0.25rem; }
    .items { border-top: 1px solid #eee; padding-top: 0.75rem; }
    .item { padding: 0.3rem 0; }
    .item a { color: #2563eb; text-decoration: none; }
    .item a:hover { text-decoration: underline; }
    .source { font-size: 0.8rem; color: #999; margin-left: 0.5rem; }
    .no-items { padding: 2rem; text-align: center; color: #777; }
    .source-health { margin-top: 2rem; }
    .source-health h2 { font-size: 1.1rem; margin-bottom: 0.5rem; }
    table { width: 100%; border-collapse: collapse; font-size: 0.85rem; }
    th, td { padding: 0.4rem 0.5rem; text-align: left; border-bottom: 1px solid #eee; }
    th { font-weight: 600; color: #555; }
    footer { margin-top: 2rem; padding-top: 1rem; border-top: 1px solid #e0e0e0; font-size: 0.8rem; color: #999; }
    """
  end
end
