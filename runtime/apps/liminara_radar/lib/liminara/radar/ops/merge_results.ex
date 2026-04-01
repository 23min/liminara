defmodule Liminara.Radar.Ops.MergeResults do
  @behaviour Liminara.Op

  @impl true
  def name, do: "merge_results"

  @impl true
  def version, do: "1.0"

  @impl true
  def determinism, do: :pure

  @impl true
  def execute(inputs) do
    # Merge new items from dedup + kept items from LLM check
    dedup_result = Jason.decode!(inputs["dedup_result"])
    llm_result = Jason.decode!(inputs["llm_kept_items"])

    new_items = dedup_result["new_items"]
    llm_kept = llm_result

    all_items = new_items ++ llm_kept

    {:ok, %{"items" => Jason.encode!(all_items)}}
  end
end
