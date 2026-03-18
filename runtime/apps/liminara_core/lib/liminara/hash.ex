defmodule Liminara.Hash do
  @moduledoc """
  SHA-256 hashing for Liminara artifacts, events, and decisions.

  All hashes are returned in the format `"sha256:{64 lowercase hex chars}"`.
  Uses `Liminara.Canonical` for deterministic JSON serialization.
  """

  alias Liminara.Canonical

  @doc """
  Return SHA-256 hash of raw bytes as `"sha256:{64 lowercase hex}"`.
  """
  @spec hash_bytes(binary()) :: String.t()
  def hash_bytes(raw_bytes) do
    hex = :crypto.hash(:sha256, raw_bytes) |> Base.encode16(case: :lower)
    "sha256:#{hex}"
  end

  @doc """
  Compute event hash: SHA-256 of canonical JSON of the four event fields.

  The `event_hash` field itself is NOT included in the hash input.
  """
  @spec hash_event(String.t(), map(), String.t() | nil, String.t()) :: String.t()
  def hash_event(event_type, payload, prev_hash, timestamp) do
    %{
      "event_type" => event_type,
      "payload" => payload,
      "prev_hash" => prev_hash,
      "timestamp" => timestamp
    }
    |> Canonical.encode_to_iodata()
    |> hash_bytes()
  end

  @doc """
  Compute decision hash: SHA-256 of canonical JSON of all fields except `decision_hash`.
  """
  @spec hash_decision(map()) :: String.t()
  def hash_decision(record) do
    record
    |> Map.delete("decision_hash")
    |> Canonical.encode_to_iodata()
    |> hash_bytes()
  end
end
