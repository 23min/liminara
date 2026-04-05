defmodule Liminara.Radar.Ops.CollectItems do
  @behaviour Liminara.Op

  alias Liminara.Radar.Ops.Specs

  @impl true
  def name, do: "collect_items"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execution_spec do
    Specs.inline(name(), version(), :pure, outputs: %{items: :artifact, source_health: :artifact})
  end

  @impl true
  def execute(inputs) do
    # inputs is a map of "fetch_<source_id>" => JSON string of {items, error}
    {all_items, health} =
      inputs
      |> Enum.reduce({[], []}, fn {key, json_str}, {items_acc, health_acc} ->
        source_id = String.replace_prefix(key, "fetch_", "")
        parsed = Jason.decode!(json_str)
        source_items = parsed["items"] || []
        error = parsed["error"]

        health_entry = %{
          "source_id" => source_id,
          "items_fetched" => length(source_items),
          "error" => error
        }

        {items_acc ++ source_items, [health_entry | health_acc]}
      end)

    # Deduplicate by URL (keep first seen)
    deduped =
      all_items
      |> Enum.uniq_by(& &1["url"])

    {:ok,
     %{
       "items" => Jason.encode!(deduped),
       "source_health" => Jason.encode!(Enum.reverse(health))
     }}
  end
end
