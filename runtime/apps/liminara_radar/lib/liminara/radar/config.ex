defmodule Liminara.Radar.Config do
  @moduledoc """
  Loads and validates Radar source configuration from JSONL files.
  """

  @required_fields ~w(id name type tags enabled)

  @doc """
  Load sources from a JSONL file (one JSON object per line).
  Returns `{:ok, [source_map]}` or `{:error, reason}`.
  """
  def load(path) do
    with {:ok, content} <- File.read(path),
         {:ok, sources} <- parse_jsonl(content),
         :ok <- validate_all(sources) do
      {:ok, sources}
    end
  end

  @doc "Filter sources to only enabled ones."
  def enabled(sources) do
    Enum.filter(sources, &(&1["enabled"] == true))
  end

  @doc "Filter sources that have any of the given tags."
  def by_tags(sources, tags) do
    tag_set = MapSet.new(tags)

    Enum.filter(sources, fn source ->
      source["tags"]
      |> MapSet.new()
      |> MapSet.intersection(tag_set)
      |> MapSet.size()
      |> Kernel.>(0)
    end)
  end

  defp parse_jsonl(content) do
    lines =
      content
      |> String.split("\n", trim: true)
      |> Enum.reject(&(String.trim(&1) == ""))

    results = Enum.map(lines, &Jason.decode/1)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil -> {:ok, Enum.map(results, fn {:ok, v} -> v end)}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp validate_all(sources) do
    case Enum.find(sources, &(!valid_source?(&1))) do
      nil -> :ok
      invalid -> {:error, {:missing_fields, missing_fields(invalid)}}
    end
  end

  defp valid_source?(source) do
    Enum.all?(@required_fields, &Map.has_key?(source, &1))
  end

  defp missing_fields(source) do
    Enum.reject(@required_fields, &Map.has_key?(source, &1))
  end
end
