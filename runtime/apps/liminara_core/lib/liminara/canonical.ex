defmodule Liminara.Canonical do
  @moduledoc """
  RFC 8785 canonical JSON encoding.

  Produces deterministic JSON with lexicographically sorted keys,
  no whitespace, and consistent number formatting. Used for hash
  computation across the Liminara runtime.
  """

  @doc """
  Encode a term to canonical JSON string (RFC 8785).

  Keys are sorted lexicographically, nested objects sort recursively,
  no whitespace between tokens.
  """
  @spec encode(term()) :: String.t()
  def encode(value) do
    value
    |> sort_keys()
    |> Jason.encode!()
  end

  @doc """
  Encode a term to canonical JSON bytes (UTF-8).
  """
  @spec encode_to_iodata(term()) :: binary()
  def encode_to_iodata(value) do
    value
    |> sort_keys()
    |> Jason.encode_to_iodata!()
    |> IO.iodata_to_binary()
  end

  defp sort_keys(%{} = map) do
    map
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map(fn {k, v} -> {k, sort_keys(v)} end)
    |> Jason.OrderedObject.new()
  end

  defp sort_keys(list) when is_list(list) do
    Enum.map(list, &sort_keys/1)
  end

  defp sort_keys(other), do: other
end
