defmodule Liminara.Event.Store do
  @moduledoc """
  Append-only, hash-chained event log stored as JSONL files.

  Each run gets one event log at `{runs_root}/{run_id}/events.jsonl`.
  Events are canonical JSON (RFC 8785), one per line, hash-chained
  via `prev_hash`.
  """

  alias Liminara.{Canonical, Hash}

  @doc """
  Append an event to the log. Returns `{:ok, event}` with computed hash and timestamp.

  The caller passes `prev_hash` (nil for the first event, or the previous event's hash).
  """
  @spec append(Path.t(), String.t(), String.t(), map(), String.t() | nil) ::
          {:ok, map()}
  def append(runs_root, run_id, event_type, payload, prev_hash) do
    timestamp = now_iso8601()
    event_hash = Hash.hash_event(event_type, payload, prev_hash, timestamp)

    event = %{
      event_hash: event_hash,
      event_type: event_type,
      payload: payload,
      prev_hash: prev_hash,
      timestamp: timestamp
    }

    # Write as canonical JSON with string keys (matching Python SDK output)
    line_map = %{
      "event_hash" => event_hash,
      "event_type" => event_type,
      "payload" => payload,
      "prev_hash" => prev_hash,
      "timestamp" => timestamp
    }

    events_path = events_path(runs_root, run_id)
    File.mkdir_p!(Path.dirname(events_path))
    File.write!(events_path, Canonical.encode(line_map) <> "\n", [:append])

    {:ok, event}
  end

  @doc """
  Read all events from a run's event log.

  Returns `{:ok, [event_map, ...]}` or `{:ok, []}` if no events exist.
  """
  @spec read_all(Path.t(), String.t()) :: {:ok, [map()]}
  def read_all(runs_root, run_id) do
    path = events_path(runs_root, run_id)

    if File.exists?(path) do
      events =
        path
        |> File.read!()
        |> String.trim()
        |> String.split("\n")
        |> Enum.map(&Jason.decode!/1)

      {:ok, events}
    else
      {:ok, []}
    end
  end

  @doc """
  Verify hash chain integrity.

  Returns `{:ok, event_count}` if valid, `{:error, index, reason}` on first mismatch.
  """
  @spec verify(Path.t(), String.t()) ::
          {:ok, non_neg_integer()} | {:error, non_neg_integer(), String.t()}
  def verify(runs_root, run_id) do
    {:ok, events} = read_all(runs_root, run_id)

    result =
      events
      |> Enum.with_index()
      |> Enum.reduce_while(nil, fn {event, index}, prev_hash ->
        cond do
          event["prev_hash"] != prev_hash ->
            {:halt, {:error, index, "prev_hash mismatch"}}

          Hash.hash_event(
            event["event_type"],
            event["payload"],
            event["prev_hash"],
            event["timestamp"]
          ) != event["event_hash"] ->
            {:halt, {:error, index, "event_hash mismatch"}}

          true ->
            {:cont, event["event_hash"]}
        end
      end)

    case result do
      {:error, index, reason} -> {:error, index, reason}
      _last_hash -> {:ok, length(events)}
    end
  end

  @doc """
  Write the run seal from the final event.

  Returns `{:ok, seal_map}`. The seal contains `run_id`, `run_seal`,
  `completed_at`, and `event_count`.
  """
  @spec write_seal(Path.t(), String.t()) :: {:ok, map()}
  def write_seal(runs_root, run_id) do
    {:ok, events} = read_all(runs_root, run_id)
    final_event = List.last(events)

    seal = %{
      "completed_at" => final_event["timestamp"],
      "event_count" => length(events),
      "run_id" => run_id,
      "run_seal" => final_event["event_hash"]
    }

    seal_path = Path.join([runs_root, run_id, "seal.json"])
    File.write!(seal_path, Canonical.encode(seal))

    {:ok, seal}
  end

  defp events_path(runs_root, run_id) do
    Path.join([runs_root, run_id, "events.jsonl"])
  end

  defp now_iso8601 do
    now = DateTime.utc_now()
    ms = now.microsecond |> elem(0) |> div(1000)

    Calendar.strftime(now, "%Y-%m-%dT%H:%M:%S") <>
      ".#{String.pad_leading(Integer.to_string(ms), 3, "0")}Z"
  end
end
