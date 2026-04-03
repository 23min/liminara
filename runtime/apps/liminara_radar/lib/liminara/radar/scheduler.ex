defmodule Liminara.Radar.Scheduler do
  use GenServer
  require Logger

  defstruct [:daily_at, :run_fn, :timer_ref, :task_ref, :last_run_at, :next_run_at]

  # --- Public API ---

  def start_link(opts) do
    name = Keyword.get(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  def next_run_at(pid), do: GenServer.call(pid, :next_run_at)
  def last_run_at(pid), do: GenServer.call(pid, :last_run_at)

  def run_now(pid), do: GenServer.call(pid, :run_now)

  @doc "Calculate milliseconds until the next occurrence of `target` time after `now`."
  def ms_until_next(%Time{} = target, %DateTime{} = now) do
    now_time = DateTime.to_time(now)
    now_seconds = Time.diff(now_time, ~T[00:00:00])
    target_seconds = Time.diff(target, ~T[00:00:00])

    diff_seconds = target_seconds - now_seconds

    seconds =
      if diff_seconds > 0 do
        diff_seconds
      else
        # Already passed today (or exactly now) → tomorrow
        diff_seconds + 86_400
      end

    seconds * 1_000
  end

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    daily_at = Keyword.fetch!(opts, :daily_at)
    run_fn = Keyword.fetch!(opts, :run_fn)

    now = DateTime.utc_now()
    ms = ms_until_next(daily_at, now)
    timer_ref = Process.send_after(self(), :trigger, ms)
    next_run_at = DateTime.add(now, ms, :millisecond)

    state = %__MODULE__{
      daily_at: daily_at,
      run_fn: run_fn,
      timer_ref: timer_ref,
      next_run_at: next_run_at
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:next_run_at, _from, state) do
    {:reply, state.next_run_at, state}
  end

  def handle_call(:last_run_at, _from, state) do
    {:reply, state.last_run_at, state}
  end

  def handle_call(:run_now, _from, %{task_ref: ref} = state) when is_reference(ref) do
    {:reply, :already_running, state}
  end

  def handle_call(:run_now, _from, state) do
    state = start_run(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:trigger, %{task_ref: ref} = state) when is_reference(ref) do
    # Previous run still active — skip, reschedule
    Logger.warning("Scheduler: skipping trigger, previous run still active")
    state = reschedule(state)
    {:noreply, state}
  end

  def handle_info(:trigger, state) do
    state = state |> start_run() |> reschedule()
    {:noreply, state}
  end

  def handle_info({ref, _result}, %{task_ref: ref} = state) do
    # Task completed successfully — clean up
    Process.demonitor(ref, [:flush])
    {:noreply, %{state | task_ref: nil}}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task_ref: ref} = state) do
    # Task crashed
    if reason != :normal do
      Logger.error("Scheduler: run failed: #{inspect(reason)}")
    end

    {:noreply, %{state | task_ref: nil}}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # --- Private ---

  defp start_run(state) do
    run_fn = state.run_fn

    task =
      Task.async(fn ->
        try do
          run_fn.()
        rescue
          e -> Logger.error("Scheduler: run raised: #{Exception.message(e)}")
        end
      end)

    %{state | task_ref: task.ref, last_run_at: DateTime.utc_now()}
  end

  defp reschedule(state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    now = DateTime.utc_now()
    ms = ms_until_next(state.daily_at, now)
    timer_ref = Process.send_after(self(), :trigger, ms)
    next_run_at = DateTime.add(now, ms, :millisecond)

    %{state | timer_ref: timer_ref, next_run_at: next_run_at}
  end
end
