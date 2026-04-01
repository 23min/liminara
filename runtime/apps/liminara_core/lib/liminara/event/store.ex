defmodule Liminara.Event.Store do
  @moduledoc """
  Append-only, hash-chained event log stored as JSONL files.

  Each run gets one event log at `{runs_root}/{run_id}/events.jsonl`.
  Events are canonical JSON (RFC 8785), one per line, hash-chained
  via `prev_hash`.

  Can be used in two modes:
  - **Supervised** (without runs_root): calls go through the named GenServer.
  - **Direct** (with explicit runs_root): stateless, for tests or standalone use.
  """

  use GenServer

  alias Liminara.{Canonical, Hash}

  # ── Supervised API (process-backed) ─────────────────────────────

  def start_link(opts) do
    runs_root = Keyword.fetch!(opts, :runs_root)
    GenServer.start_link(__MODULE__, runs_root, name: __MODULE__)
  end

  @doc "Append an event via the supervised process."
  @spec append(String.t(), String.t(), map(), String.t() | nil) :: {:ok, map()}
  def append(run_id, event_type, payload, prev_hash) do
    GenServer.call(__MODULE__, {:append, run_id, event_type, payload, prev_hash})
  end

  @doc "Read all events via the supervised process."
  @spec read_all(String.t()) :: {:ok, [map()]}
  def read_all(run_id) when is_binary(run_id) do
    GenServer.call(__MODULE__, {:read_all, run_id})
  end

  @doc "Verify hash chain via the supervised process."
  @spec verify(String.t()) :: {:ok, non_neg_integer()} | {:error, non_neg_integer(), String.t()}
  def verify(run_id) when is_binary(run_id) do
    GenServer.call(__MODULE__, {:verify, run_id})
  end

  @doc "Write run seal via the supervised process."
  @spec write_seal(String.t()) :: {:ok, map()}
  def write_seal(run_id) when is_binary(run_id) do
    GenServer.call(__MODULE__, {:write_seal, run_id})
  end

  @doc "List all run IDs via the supervised process."
  @spec list_run_ids() :: [String.t()]
  def list_run_ids do
    GenServer.call(__MODULE__, :list_run_ids)
  end

  @doc "Touch the events.jsonl file to update its mtime via the supervised process."
  @spec touch(String.t()) :: :ok
  def touch(run_id) when is_binary(run_id) do
    GenServer.call(__MODULE__, {:touch, run_id})
  end

  @doc "Write the plan for a run via the supervised process."
  @spec write_plan(String.t(), Liminara.Plan.t()) :: :ok
  def write_plan(run_id, plan) when is_binary(run_id) do
    GenServer.call(__MODULE__, {:write_plan, run_id, plan})
  end

  @doc "Read the plan for a run via the supervised process."
  @spec read_plan(String.t()) :: {:ok, Liminara.Plan.t()} | {:error, :not_found}
  def read_plan(run_id) when is_binary(run_id) do
    GenServer.call(__MODULE__, {:read_plan, run_id})
  end

  # ── Direct API (stateless, explicit runs_root) ──────────────────

  @doc """
  List all run IDs by scanning the runs directory for subdirectories.

  Returns a sorted list of run ID strings.
  """
  @spec list_run_ids(Path.t()) :: [String.t()]
  def list_run_ids(runs_root) do
    if File.dir?(runs_root) do
      runs_root
      |> File.ls!()
      |> Enum.filter(fn name -> File.dir?(Path.join(runs_root, name)) end)
      |> Enum.sort()
    else
      []
    end
  end

  @doc """
  Touch the events.jsonl file to update its mtime (direct API).
  """
  @spec touch(Path.t(), String.t()) :: :ok
  def touch(runs_root, run_id) do
    path = events_path(runs_root, run_id)

    if File.exists?(path) do
      File.touch!(path)
    end

    :ok
  end

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

  @doc "Write the plan as JSON to the run directory."
  @spec write_plan(Path.t(), String.t(), Liminara.Plan.t()) :: :ok
  def write_plan(runs_root, run_id, plan) do
    run_dir = Path.join(runs_root, run_id)
    File.mkdir_p!(run_dir)
    plan_path = Path.join(run_dir, "plan.json")
    File.write!(plan_path, Liminara.Plan.to_map(plan) |> Jason.encode!(pretty: true))
    :ok
  end

  @doc "Read the plan from the run directory."
  @spec read_plan(Path.t(), String.t()) :: {:ok, Liminara.Plan.t()} | {:error, :not_found}
  def read_plan(runs_root, run_id) do
    plan_path = Path.join([runs_root, run_id, "plan.json"])

    case File.read(plan_path) do
      {:ok, content} ->
        {:ok, content |> Jason.decode!() |> Liminara.Plan.from_map()}

      {:error, :enoent} ->
        {:error, :not_found}
    end
  end

  # ── GenServer callbacks ─────────────────────────────────────────

  @impl true
  def init(runs_root) do
    File.mkdir_p!(runs_root)
    {:ok, %{runs_root: runs_root}}
  end

  @impl true
  def handle_call(
        {:append, run_id, event_type, payload, prev_hash},
        _from,
        %{runs_root: root} = state
      ) do
    {:reply, append(root, run_id, event_type, payload, prev_hash), state}
  end

  def handle_call({:read_all, run_id}, _from, %{runs_root: root} = state) do
    {:reply, read_all(root, run_id), state}
  end

  def handle_call({:verify, run_id}, _from, %{runs_root: root} = state) do
    {:reply, verify(root, run_id), state}
  end

  def handle_call({:write_seal, run_id}, _from, %{runs_root: root} = state) do
    {:reply, write_seal(root, run_id), state}
  end

  def handle_call(:list_run_ids, _from, %{runs_root: root} = state) do
    {:reply, list_run_ids(root), state}
  end

  def handle_call({:touch, run_id}, _from, %{runs_root: root} = state) do
    {:reply, touch(root, run_id), state}
  end

  def handle_call({:write_plan, run_id, plan}, _from, %{runs_root: root} = state) do
    {:reply, write_plan(root, run_id, plan), state}
  end

  def handle_call({:read_plan, run_id}, _from, %{runs_root: root} = state) do
    {:reply, read_plan(root, run_id), state}
  end

  # ── Private ─────────────────────────────────────────────────────

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
